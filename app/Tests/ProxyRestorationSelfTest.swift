import Foundation

@main
struct ProxyRestorationSelfTest {
    @MainActor
    static func main() async throws {
        if CommandLine.arguments.dropFirst() == ["--stop-current-session"] {
            let paths = try ProjectPaths.resolve()
            guard let snapshot = try Backend.loadProxySnapshot(paths: paths) else {
                throw AppError.message("没有待恢复的会话。")
            }
            try AdministratorAuthorization.restoreProxy(snapshot)
            try await Backend.stopRuntime(paths: paths)
            try Backend.removeProxySnapshot(paths: paths)
            print("PASS: saved proxy restored and current isolation session stopped")
            return
        }

        let clash: [String: Any] = [
            "HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": 7897,
            "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 7897,
            "SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 7897,
            "ExcludeSimpleHostnames": 1
        ]
        precondition(Backend.autoProxyURL(from: "URL: (null)\nEnabled: No") == "")
        precondition(Backend.autoProxyURL(from: "URL: \nEnabled: No") == "")
        precondition(Backend.autoProxyURL(from: "URL: https://example.com/original.pac\nEnabled: Yes")
                     == "https://example.com/original.pac")
        var active = clash
        active["ProxyAutoConfigEnable"] = 1
        active["ProxyAutoConfigURLString"] = "http://127.0.0.1:16080/univpn.pac"
        active["ExceptionsList"] = ["localhost"]

        for (url, enabled) in [("", false), ("https://example.com/original.pac", false),
                                ("https://example.com/original.pac", true)] {
            for bypass in [[], ["10.0.0.0/8", "*.local", "<local>"]] {
                let snapshot = ProxySnapshot(
                    networkService: "Wi-Fi", autoProxyURL: url, autoProxyEnabled: enabled,
                    bypassDomains: bypass, capturedAt: Date()
                )
                let restored = try ProxyRestoration.configuration(restoring: snapshot, in: active)
                precondition(restored["ProxyAutoConfigURLString"] as? String == (url.isEmpty ? nil : url))
                precondition(restored["ProxyAutoConfigEnable"] as? Int == (enabled ? 1 : 0))
                precondition(restored["ExceptionsList"] as? [String] == (bypass.isEmpty ? nil : bypass))
                for (key, value) in clash {
                    precondition(NSDictionary(dictionary: [key: restored[key]!]).isEqual(to: [key: value]))
                }
                let repeated = try ProxyRestoration.configuration(restoring: snapshot, in: restored)
                precondition(NSDictionary(dictionary: restored).isEqual(to: repeated))
            }
        }

        let invalid = ProxySnapshot(
            networkService: "Wi-Fi", autoProxyURL: "", autoProxyEnabled: true,
            bypassDomains: [], capturedAt: Date()
        )
        do {
            _ = try ProxyRestoration.configuration(restoring: invalid, in: active)
            fatalError("An enabled PAC without a URL must fail before any changes")
        } catch is AppError {}

        print("PASS: empty/nonempty PAC URLs, enabled/disabled state, empty/populated bypass, Clash preservation, idempotence, invalid snapshot")
    }
}
