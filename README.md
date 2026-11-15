# Halal Cloud for macOS

A native macOS client for [Halal Cloud](https://2dland.cn/), reproducing the
Windows client ([`halalcloud/halalcloud-client`](https://github.com/halalcloud/halalcloud-client))
with SwiftUI and a dependency-free Swift implementation of the same HL6 API.

The upstream client is Qt/C++ and Windows-only. This project keeps the same
window, the same sign-in flow and the same Open API, so both clients talk to
the same account with the same tokens.

> **Status:** work in progress, feature parity with the Windows client's window.
> See [Parity](#parity-with-the-windows-client) for the two deliberate gaps.

## Install

```bash
brew tap fabea87/halalcloud
brew install --cask --no-quarantine halalcloud
```

`--no-quarantine` is required until the app is signed with a Developer ID and
notarized (see [Signing](#signing-and-notarization)).

## Parity with the Windows client

| Windows client | This client |
| --- | --- |
| "New Credential" dialog: QR code + copyable link + "open in browser" | same, in the same two-column layout |
| Main window (336×308): avatar, name, identity, sign out | same, same size |
| `打开目录` / Open Directory | opens the client's application-data folder (the store that backs the drive) |
| `查看日志` / View Log | opens `~/Library/Logs/HalalCloud/HalalCloud.log` |
| `上传文件` / Upload File (disabled upstream) | disabled as well |
| Website / GitHub buttons | same two buttons |
| System tray icon | menu bar extra with show/quit |
| WinFsp read-only drive via FUSE | **not implemented** |

Two gaps, both on purpose:

1. **No mounted volume.** Upstream mounts a read-only drive through WinFsp; the
   macOS equivalent (macFUSE) cannot be shipped in an ad-hoc-signed, unsigned
   Homebrew cask, and macOS 15 replaced it with FSKit / File Provider
   extensions, which need a Developer ID and a provisioning profile. The block
   download path is implemented in `HalalCloudCore` (`FileStorageInformation`,
   `BlockStore`, `FileDownloader`) so a File Provider or macFUSE front end can
   be added without touching the protocol layer.
2. **No upload.** Upstream's upload is commented out too — it needs Baidu
   Object Storage signing (`HccBcePutObject`).

Everything else — the HL6 request signing, PKCE sign-in, token refresh, file
listing, block addresses, XOR decryption and CID verification — is implemented.

## Build from source

Requirements: macOS 13 or later, Xcode command line tools (Swift 5.9+).

```bash
swift build            # builds the app and the core library
swift test             # protocol, signing and layout tests
./scripts/build-app.sh # produces dist/HalalCloud.app
```

Useful environment variables for `build-app.sh`:

| Variable | Default | Meaning |
| --- | --- | --- |
| `VERSION` | latest git tag, else `0.1.0` | `CFBundleShortVersionString` |
| `BUILD_NUMBER` | git commit count | `CFBundleVersion` |
| `BUNDLE_ID` | `cn.halalcloud.mac` | bundle identifier |
| `ARCHS` | host architecture | e.g. `"arm64 x86_64"` for a universal build |
| `SIGN_IDENTITY` | `-` (ad-hoc) | codesign identity |

## Repository layout

```
Sources/HalalCloudCore     protocol and networking (no UI)
  HccSigner.swift          HL6-HMAC-SHA256 request signing
  HccAPI.swift             HTTP transport, status code mapping
  HalalCloudService.swift  sign-in, tokens, account, listing, downloads
  BlockStore.swift         block download + XOR + CID verification + cache
  JSON.swift               tolerant JSON accessors
Sources/HalalCloud         SwiftUI app (mirrors the Windows UI)
Tests/HalalCloudCoreTests  signing test vectors, CID, base32, layout
packaging/                 Info.plist, icon, Homebrew cask template
scripts/                   app bundle, icns and cask generation
docs/PROTOCOL.md           the Open API as used by the clients
```

## Releasing

`v*` tags trigger `.github/workflows/release.yml`, which builds a universal
`HalalCloud.app`, zips it, publishes a GitHub release, and commits the updated
cask to `<owner>/homebrew-halalcloud` using the `TAP_DEPLOY_KEY` secret (an
ed25519 deploy key with write access to the tap repository).

```bash
git tag v0.1.0 && git push origin v0.1.0
```

One-time tap setup:

```bash
gh repo create homebrew-halalcloud --public
ssh-keygen -t ed25519 -N "" -C "halalcloud-mac release workflow" -f tapkey
gh repo deploy-key add tapkey.pub --repo <owner>/homebrew-halalcloud \
  --title "release workflow" --allow-write
gh secret set TAP_DEPLOY_KEY --repo <owner>/halalcloud-mac < tapkey
```

### Signing and notarization

The release is ad-hoc signed, so Gatekeeper blocks it on other machines until
the quarantine flag is removed. To ship a proper build, set repository secrets
`APPLE_ID`, `APPLE_TEAM_ID` and `APPLE_APP_PASSWORD`, import a Developer ID
Application certificate, and change `SIGN_IDENTITY` in the release workflow to
that identity before adding a `notarytool submit --wait` + `stapler staple`
step.

## Credits

- Protocol, wire format and UI are those of the
  [Halal Cloud Client](https://github.com/halalcloud/halalcloud-client) by
  MouriNaruto (MIT).
- This project is not affiliated with Halal Cloud.

## License

MIT — see [LICENSE](LICENSE).
