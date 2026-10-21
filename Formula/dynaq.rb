class Dynaq < Formula
  desc "System-wide multi-band parametric and dynamic audio equalizer for macOS"
  homepage "https://github.com/Gabe-Macri/dynaQ"
  url "https://github.com/Gabe-Macri/dynaQ/archive/refs/tags/v0.1.tar.gz"
  sha256 "8a2d8687d2e4c75527982c1b579127e845ce82f3e569b476661a0898ca8c02d3"
  license "MIT"
  head "https://github.com/Gabe-Macri/dynaQ.git", branch: "main"

  depends_on macos: :sonoma
  depends_on xcode: ["15.0", :build]

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    bin.install ".build/release/dynaQ" => "dynaq"
    bin.install ".build/release/dynaQ-router" => "dynaq-router"
  end

  service do
    run [opt_bin/"dynaq-router"]
    keep_alive true
    log_path var/"log/dynaq-router.log"
    error_log_path var/"log/dynaq-router.error.log"
  end

  test do
    assert_match "dynaQ", shell_output("#{bin}/dynaq --help")
  end
end
