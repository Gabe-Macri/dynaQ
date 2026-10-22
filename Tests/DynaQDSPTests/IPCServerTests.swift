import XCTest
import DynaQCore
import DynaQAudioDriver

final class IPCServerTests: XCTestCase {

    func testIPCServerPingAndStatus() {
        let testPath = "/tmp/test_swift_dynaq_ipc.sock"
        let server = IPCServer(socketPath: testPath, tcpPort: 9890)
        server.start()
        defer { server.stop() }

        // Give server 50ms to bind
        usleep(50_000)

        // Connect client socket
        let clientFd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(clientFd, 0)
        defer { close(clientFd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            testPath.withCString { cstr in
                _ = strncpy(ptr, cstr, maxLen - 1)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        var connectRes: Int32 = -1
        withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                connectRes = connect(clientFd, sa, addrLen)
            }
        }
        XCTAssertEqual(connectRes, 0, "Client must connect to IPC socket")

        // Send ping command
        let pingReq = "{\"cmd\": \"ping\"}\n"
        _ = pingReq.withCString { write(clientFd, $0, strlen($0)) }

        // Read response
        var readBuf = [UInt8](repeating: 0, count: 1024)
        let bytesRead = read(clientFd, &readBuf, readBuf.count)
        XCTAssertGreaterThan(bytesRead, 0)

        let respData = Data(readBuf[0..<bytesRead])
        if let json = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] {
            XCTAssertEqual(json["status"] as? String, "ok")
            XCTAssertEqual(json["version"] as? String, "1.0.0-beta.2")
        } else {
            XCTFail("Response was not valid JSON: \(String(data: respData, encoding: .utf8) ?? "")")
        }
    }
}

