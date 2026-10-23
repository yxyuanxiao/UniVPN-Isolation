import Foundation

@main
struct TrafficParserSelfTest {
    static func main() {
        let log = """
        Aug 26 13:17:05 (1787750225.286010) danted[259]: info: pass(1): tcp/connect [: 192.168.64.1.52106 192.168.64.2.5900 -> 172.20.31.26.52106 10.10.128.2.25899
        Aug 26 13:17:19 (1787750239.295410) danted[259]: info: pass(1): tcp/connect ]: 4252093 -> 192.168.64.1.52106 192.168.64.2.5900 -> 15334, 15334 -> 172.20.31.26.52106 10.10.128.2.25899 -> 4252093: local client closed. Session duration: 7s
        Aug 26 13:17:20 (1787750240.000000) danted[242]: info: pass(1): tcp/accept [: 192.168.64.1.52105 192.168.64.2.5900
        Aug 26 13:18:00 (1787750280.000000) danted[300]: info: block(3): tcp/connect ]: 192.168.64.1.52200 192.168.64.2.5900 -> 0.0.0.0.0 1.1.1.1.80
        """

        let sessions = Backend.parseTraffic(log)
        let passed = sessions.last
        let rejected = sessions.first

        guard sessions.count == 2,
              passed?.destination == "10.10.128.2:25899",
              passed?.outcome == .connected,
              rejected?.destination == "1.1.1.1:80",
              rejected?.outcome == .rejected else {
            FileHandle.standardError.write(Data("Traffic parser self-test failed\n".utf8))
            Foundation.exit(1)
        }

        print("Traffic parser self-test passed")
    }
}
