//
//  LoginView.swift
//  HalalCloud
//
//  Mirrors the Windows client's "New Credential" dialog: a link that can be
//  opened in the local browser, and a QR code for signing in on another device.
//

import AppKit
import SwiftUI

struct LoginView: View {

    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL

    private var link: String {
        model.authorization?.redirectURI ?? ""
    }

    var body: some View {
        HStack(spacing: 0) {
            webLinkColumn
            Divider()
            qrCodeColumn
        }
        .frame(width: 720, height: 352)
    }

    private var webLinkColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Copy the link to sign in with your browser")
                .font(.system(size: 20))

            ScrollView {
                Text(link.isEmpty ? " " : link)
                    .font(.system(size: 13, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 120)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Button("Open with the local browser") {
                guard let url = URL(string: link) else { return }
                openURL(url)
            }
            .font(.system(size: 20))
            .disabled(link.isEmpty)

            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 16, leading: 32, bottom: 32, trailing: 32))
        .frame(width: 360)
    }

    private var qrCodeColumn: some View {
        VStack(spacing: 16) {
            Text("Scan with another device to sign in")
                .font(.system(size: 20))

            QRCodeView(text: link)
                .frame(width: 208, height: 208)
                .padding(8)
                .background(Color.white)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.35), lineWidth: 1))

            HStack(spacing: 8) {
                if model.isPreparingSignIn {
                    ProgressView().controlSize(.small)
                }
                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 16, leading: 24, bottom: 32, trailing: 24))
        .frame(maxWidth: .infinity)
    }

    private var statusText: String {
        if model.isPreparingSignIn {
            return "Requesting a sign-in link…"
        }
        return model.authorizationState.localizedDescription
    }
}
