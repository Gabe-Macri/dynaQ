class Dynaq < Formula
  desc "System-wide multi-band parametric and dynamic audio equalizer for macOS"
  homepage "https://github.com/Gabe-Macri/dynaQ"
  url "https://github.com/Gabe-Macri/dynaQ/archive/refs/tags/v1.0.0.tar.gz"
  license "MIT"
  head "https://github.com/Gabe-Macri/dynaQ.git", branch: "main"

  depends_on macos: :sonoma
  depends_on xcode: ["15.0", :build]
  depends_on "rust" => :build

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    system "cargo", "build", "--release", "--manifest-path", "native/dynaq-rust/Cargo.toml"

    bin.install ".build/release/dynaQ" => "dynaq"
    bin.install ".build/release/dynaQ-router" => "dynaq-router"
    bin.install "native/dynaq-rust/target/release/dynaq-opt" => "dynaq-opt"
    lib.install "native/dynaq-rust/target/release/libdynaq_rust.dylib" => "libdynaq_rust.dylib"
  end

  service do
    run [opt_bin/"dynaq-router"]
    keep_alive true
    log_path var/"log/dynaq-router.log"
    error_log_path var/"log/dynaq-router.error.log"
  end

  test do
    assert_match "dynaQ", shell_output("#{bin}/dynaq --help")
    assert_match "dynaq-opt", shell_output("#{bin}/dynaq-opt --help")
  end
end
