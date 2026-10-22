import Foundation
import Darwin

/// High-Performance Lightweight IPC Server for dynaQ.
/// Accepts JSON-RPC newline-delimited requests over Unix Domain Socket (/tmp/dynaq_ipc.sock)
/// and TCP loopback (127.0.0.1:9876).
/// Integrates Python backend scripts, AutoEQ optimizers, and CLI telemetry monitors.
public final class IPCServer: @unchecked Sendable {
    public static let shared = IPCServer()

    public let socketPath: String
    public let tcpPort: UInt16
    private var unixListenFd: Int32 = -1
    private var tcpListenFd: Int32 = -1
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.dynaq.ipc.server", qos: .utility)

    public var commandHandler: ((String, [String: Any]) -> [String: Any]?)?

    public init(socketPath: String = "/tmp/dynaq_ipc.sock", tcpPort: UInt16 = 9876) {
        self.socketPath = socketPath
        self.tcpPort = tcpPort
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        queue.async { [weak self] in
            guard let self = self else { return }
            self.setupUnixSocket()
            self.setupTCPSocket()
            self.eventLoop()
        }
    }

    public func stop() {
        isRunning = false
        if unixListenFd >= 0 {
            close(unixListenFd)
            unixListenFd = -1
        }
        if tcpListenFd >= 0 {
            close(tcpListenFd)
            tcpListenFd = -1
        }
        unlink(socketPath)
    }

    private func setupUnixSocket() {
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            socketPath.withCString { cstr in
                _ = strncpy(ptr, cstr, maxLen - 1)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        var bindRes: Int32 = -1
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bindRes = bind(fd, sa, addrLen)
            }
        }

        guard bindRes == 0 else {
            close(fd)
            return
        }

        listen(fd, 5)
        unixListenFd = fd
    }

    private func setupTCPSocket() {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var opt: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = tcpPort.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        var bindRes: Int32 = -1
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bindRes = bind(fd, sa, addrLen)
            }
        }

        guard bindRes == 0 else {
            close(fd)
            return
        }

        listen(fd, 5)
        tcpListenFd = fd
    }

    private func eventLoop() {
        while isRunning {
            var fds = [pollfd]()
            if unixListenFd >= 0 {
                fds.append(pollfd(fd: unixListenFd, events: Int16(POLLIN), revents: 0))
            }
            if tcpListenFd >= 0 {
                fds.append(pollfd(fd: tcpListenFd, events: Int16(POLLIN), revents: 0))
            }
            guard !fds.isEmpty else { break }

            let pollRes = poll(&fds, nfds_t(fds.len), 500)
            if pollRes > 0 {
                for p in fds {
                    if (p.revents & Int16(POLLIN)) != 0 {
                        let clientFd = accept(p.fd, nil, nil)
                        if clientFd >= 0 {
                            DispatchQueue.global(qos: .utility).async { [weak self] in
                                self?.handleClient(clientFd)
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleClient(_ clientFd: Int32) {
        var buf = [UInt8](repeating: 0, count: 4096)
        var accumData = Data()

        while isRunning {
            let bytesRead = read(clientFd, &buf, buf.count)
            guard bytesRead > 0 else { break }
            accumData.append(buf, count: bytesRead)

            while let newlineIdx = accumData.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = accumData.subdata(in: 0..<newlineIdx)
                accumData.removeSubrange(0...newlineIdx)

                if let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                   let cmd = json["cmd"] as? String {
                    let resp = dispatch(cmd: cmd, params: json)
                    if let respData = try? JSONSerialization.data(withJSONObject: resp),
                       var respStr = String(data: respData, encoding: .utf8) {
                        respStr.append("\n")
                        respStr.withCString { cstr in
                            _ = write(clientFd, cstr, strlen(cstr))
                        }
                    }
                }
            }
        }
        close(clientFd)
    }

    private func dispatch(cmd: String, params: [String: Any]) -> [String: Any] {
        if let custom = commandHandler?(cmd, params) {
            return custom
        }

        let engine = AudioEngineManager.shared
        switch cmd {
        case "ping":
            return ["status": "ok", "version": "1.0.0-beta.2"]

        case "get_status":
            return [
                "status": "online",
                "sample_rate": engine.currentSampleRate,
                "buffer_frames": engine.currentBufferFrames,
                "capture_source": engine.captureSource.rawValue,
                "feedback_protection": engine.feedbackProtectionEnabled,
                "underrun_count": engine.underrunCount
            ]

        case "get_telemetry":
            return [
                "status": "ok",
                "peak_left_db": -12.0,
                "peak_right_db": -12.0,
                "lufs_integrated": -14.0,
                "correlation": 0.95
            ]

        default:
            return ["status": "error", "message": "Unknown command '\(cmd)'"]
        }
    }
}

private extension Array {
    var len: Int { count }
}

