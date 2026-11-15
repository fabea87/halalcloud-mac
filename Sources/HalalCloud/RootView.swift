//
//  RootView.swift
//  HalalCloud
//

import SwiftUI

struct RootView: View {

    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                LaunchView()
            case .signedOut:
                LoginView()
            case .signedIn:
                MainWindowView()
            }
        }
        .task { await model.start() }
        .alert("Something went wrong", isPresented: $model.isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct LaunchView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Connecting to Halal Cloud…")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(width: 336, height: 308)
    }
}
