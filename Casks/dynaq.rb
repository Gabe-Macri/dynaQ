cask "dynaq" do
  version "1.0.0"
  sha256 :no_check

  url "https://github.com/Gabe-Macri/dynaQ/releases/download/v#{version}/dynaQ-Installer.dmg"
  name "dynaQ"
  desc "System-wide multi-band parametric and dynamic audio equalizer for macOS"
  homepage "https://github.com/Gabe-Macri/dynaQ"

  depends_on macos: ">= :sonoma"

  app "dynaQ.app"
  binary "#{appdir}/dynaQ.app/Contents/MacOS/dynaQ", target: "dynaq"
  binary "#{appdir}/dynaQ.app/Contents/Helpers/dynaQ-router", target: "dynaq-router"
  binary "#{appdir}/dynaQ.app/Contents/Helpers/dynaq-opt", target: "dynaq-opt"
  binary "#{appdir}/dynaQ.app/Contents/Helpers/dynaq-cli", target: "dynaq-cli"

  zap trash: [
    "~/Library/Application Support/dynaQ",
    "~/Library/Preferences/com.dynaq.audio.plist",
    "~/Library/Preferences/dynaq.pref.*.plist",
    "/Library/Audio/Plug-Ins/HAL/DynaQDriver.driver",
    "/Library/LaunchAgents/com.dynaq.router.plist",
  ]
end
