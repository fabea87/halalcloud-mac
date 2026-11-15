cask "halalcloud" do
  version "@@VERSION@@"
  sha256 "@@SHA256@@"

  url "https://github.com/@@REPO@@/releases/download/v#{version}/HalalCloud-#{version}.zip",
      verified: "github.com/@@REPO@@/"
  name "Halal Cloud"
  desc "Native macOS client for Halal Cloud"
  homepage "https://github.com/@@REPO@@"

  depends_on macos: ">= :ventura"

  app "HalalCloud.app"

  caveats <<~EOS
    Halal Cloud is not notarized yet, so macOS quarantines the download.
    Install with:

      brew install --cask --no-quarantine halalcloud

    or remove the quarantine attribute yourself:

      xattr -dr com.apple.quarantine "#{appdir}/HalalCloud.app"
  EOS
end
