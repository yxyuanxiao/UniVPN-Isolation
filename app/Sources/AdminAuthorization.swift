import Foundation

enum AdministratorAuthorization {
    enum AuthorizationError: LocalizedError {
        case cancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return "已取消管理员授权。"
            case .failed(let detail):
                return detail
            }
        }
    }

    @MainActor
    static func enablePAC(snapshot: ProxySnapshot, pacURL: URL) throws {
        let activeBypass = pacBypassDomains(from: snapshot)

        try run([
            ["/usr/sbin/networksetup", "-setautoproxyurl", snapshot.networkService, pacURL.absoluteString],
            ["/usr/sbin/networksetup", "-setautoproxystate", snapshot.networkService, "on"],
            ["/usr/sbin/networksetup", "-setproxybypassdomains", snapshot.networkService] + activeBypass
        ])
    }

    @MainActor
    static func reloadPAC(snapshot: ProxySnapshot, pacURL: URL) throws {
        let activeBypass = pacBypassDomains(from: snapshot)

        // Toggling the PAC state forces CFNetwork/Chromium to discard a SOCKS
        // endpoint that was marked bad while the VPN was still connecting.
        try run([
            ["/usr/sbin/networksetup", "-setautoproxystate", snapshot.networkService, "off"],
            ["/usr/sbin/networksetup", "-setautoproxyurl", snapshot.networkService, pacURL.absoluteString],
            ["/usr/sbin/networksetup", "-setproxybypassdomains", snapshot.networkService] + activeBypass,
            ["/usr/sbin/networksetup", "-setautoproxystate", snapshot.networkService, "on"]
        ])
    }

    @MainActor
    static func restoreProxy(_ snapshot: ProxySnapshot) throws {
        let bypass = snapshot.bypassDomains.isEmpty ? ["Empty"] : snapshot.bypassDomains
        var commands: [[String]] = []
        commands.append([
            "/usr/sbin/networksetup", "-setautoproxyurl", snapshot.networkService,
            snapshot.autoProxyURL
        ])
        commands.append([
            "/usr/sbin/networksetup", "-setproxybypassdomains", snapshot.networkService
        ] + bypass)
        commands.append([
            "/usr/sbin/networksetup", "-setautoproxystate", snapshot.networkService,
            snapshot.autoProxyEnabled ? "on" : "off"
        ])
        try run(commands)
    }

    @MainActor
    private static func run(_ commands: [[String]]) throws {
        let shellCommand = commands
            .map { $0.map(shellQuote).joined(separator: " ") }
            .joined(separator: " && ")
        let source = "do shell script \(appleScriptLiteral(shellCommand)) with administrator privileges"
        guard let script = NSAppleScript(source: source) else {
            throw AuthorizationError.failed("无法创建管理员授权请求。")
        }

        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        guard let error else { return }

        let number = error[NSAppleScript.errorNumber] as? Int
        if number == -128 {
            throw AuthorizationError.cancelled
        }
        let message = (error[NSAppleScript.errorMessage] as? String)
            ?? "管理员操作失败。"
        throw AuthorizationError.failed(message)
    }

    private static func pacBypassDomains(from snapshot: ProxySnapshot) -> [String] {
        let domains = snapshot.bypassDomains.filter {
            $0.caseInsensitiveCompare("10.0.0.0/8") != .orderedSame
                && $0.caseInsensitiveCompare("10.10.128.0/24") != .orderedSame
        }
        return domains.isEmpty ? ["Empty"] : domains
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func appleScriptLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
