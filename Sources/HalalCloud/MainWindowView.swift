//
//  MainWindowView.swift
//  HalalCloud
//
//  A 1:1 reproduction of the Windows client's main window: profile block,
//  the action buttons (upload is disabled upstream as well) and the version /
//  link block.
//

import SwiftUI

struct MainWindowView: View {

    @EnvironmentObject private var model: AppModel
    @State private var isConfirmingSignOut = false

    var body: some View {
        VStack(spacing: 8) {
            profileBlock
            actionButton("Open Directory") { model.revealApplicationData() }
            actionButton("View Log") { model.openLog() }
            actionButton("Upload File", enabled: false) {}
            versionBlock
        }
        .padding(8)
        .frame(width: 336, height: 308)
        .alert("Sign out of Halal Cloud?", isPresented: $isConfirmingSignOut) {
            Button("Sign Out", role: .destructive) { model.signOut() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app will quit after signing out.")
        }
    }

    // MARK: - Blocks

    private var profileBlock: some View {
        HStack(spacing: 6) {
            profileIcon
                .frame(width: 80, height: 80)
                .background(Color.white)
                .clipped()

            VStack(alignment: .leading, spacing: 0) {
                Text(model.user?.name ?? "[Name]")
                    .font(.system(size: 20))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(model.user?.identity ?? "[Identity]")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button("Sign Out") {
                    isConfirmingSignOut = true
                }
                .font(.system(size: 14))
                .frame(height: 28)
                .frame(maxWidth: .infinity)
            }
            .frame(width: 220)
        }
        .frame(width: 320, height: 80)
    }

    @ViewBuilder
    private var profileIcon: some View {
        if let url = model.user?.iconURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    placeholderIcon
                }
            }
        } else {
            placeholderIcon
        }
    }

    private var placeholderIcon: some View {
        ZStack {
            Color.white
            Image(systemName: "person.crop.square")
                .resizable()
                .scaledToFit()
                .padding(16)
                .foregroundStyle(.tertiary)
        }
    }

    private var versionBlock: some View {
        VStack(spacing: 8) {
            Text(model.versionString)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                actionButton("Halal Cloud Website") { model.openWebsite() }
                actionButton("Client on GitHub") { model.openRepository() }
            }
        }
        .frame(width: 320, height: 80)
    }

    // MARK: - Components

    private func actionButton(
        _ title: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity)
                .frame(height: 28)
        }
        .disabled(!enabled)
    }
}
