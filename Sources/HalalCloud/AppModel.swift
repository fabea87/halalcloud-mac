//
//  AppModel.swift
//  HalalCloud
//

import AppKit
import Combine
import Foundation
import HalalCloudCore

@MainActor
final class AppModel: ObservableObject {

    enum Phase: Equatable {
        case launching
        case signedOut
        case signedIn
    }

    @Published private(set) var phase: Phase = .launching
    @Published private(set) var user: UserInformation?
    @Published private(set) var authorization: AuthorizationRequest?
    @Published private(set) var authorizationState: AuthorizeState = .pendingLogin
    @Published private(set) var isPreparingSignIn = false
    @Published var errorMessage: String?
    @Published var isShowingError = false

    let versionString = AppInfo.versionString

    private let service = HalalCloudService()
    private var pollTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func start() async {
        guard phase == .launching else { return }
        AppLog.write("Restoring session")
        if await service.restoreSession() {
            await loadProfile()
            phase = .signedIn
        } else {
            phase = .signedOut
            beginSignIn()
        }
    }

    private func loadProfile() async {
        do {
            user = try await service.currentUser()
            AppLog.write("Loaded profile for \(user?.identity ?? "unknown")")
        } catch {
            AppLog.write("Loading the profile failed: \(error.localizedDescription)")
            present(error)
        }
    }

    // MARK: - Sign in

    func beginSignIn() {
        pollTask?.cancel()
        authorization = nil
        authorizationState = .pendingLogin
        isPreparingSignIn = true

        pollTask = Task { [weak self] in
            guard let self else { return }
            var request: AuthorizationRequest?

            while !Task.isCancelled {
                if request == nil {
                    do {
                        let created = try await self.service.startAuthorization()
                        if Task.isCancelled { return }
                        request = created
                        self.authorization = created
                        self.isPreparingSignIn = false
                        AppLog.write("Sign-in link issued")
                    } catch {
                        if Task.isCancelled { return }
                        self.isPreparingSignIn = false
                        AppLog.write("Requesting a sign-in link failed: \(error.localizedDescription)")
                        self.present(error)
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        continue
                    }
                }

                guard let current = request else { continue }

                do {
                    let state = try await self.service.authorizationState(code: current.code)
                    if Task.isCancelled { return }
                    if state != self.authorizationState {
                        AppLog.write("Sign-in state: \(state.rawValue)")
                    }
                    self.authorizationState = state

                    switch state {
                    case .failed:
                        request = nil
                        self.authorization = nil
                        self.authorizationState = .pendingLogin
                        self.isPreparingSignIn = true
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                        continue
                    case .tokenCreated, .success:
                        try await self.service.finishAuthorization(current)
                        if Task.isCancelled { return }
                        self.authorization = nil
                        await self.loadProfile()
                        self.phase = .signedIn
                        AppLog.write("Signed in")
                        return
                    case .pendingLogin, .pendingConfirmation:
                        break
                    }
                } catch {
                    if Task.isCancelled { return }
                }

                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    func cancelSignIn() {
        pollTask?.cancel()
        pollTask = nil
        authorization = nil
        isPreparingSignIn = false
        authorizationState = .pendingLogin
    }

    func signOut() {
        pollTask?.cancel()
        pollTask = nil
        AppLog.write("Signing out")
        Task {
            await service.signOut()
            user = nil
            NSApp.terminate(nil)
        }
    }

    // MARK: - Menu actions

    func revealApplicationData() {
        let directory = Support.applicationDataDirectory
        try? Support.ensureDirectory(directory)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    func openLog() {
        AppLog.flush()
        NSWorkspace.shared.open(AppLog.fileURL)
    }

    func openWebsite() {
        NSWorkspace.shared.open(AppInfo.websiteURL)
    }

    func openRepository() {
        NSWorkspace.shared.open(AppInfo.repositoryURL)
    }

    // MARK: - Errors

    func present(_ error: Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }
}
