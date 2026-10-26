import Foundation
import Security
import SystemConfiguration

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
        var authorization: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &authorization)
        guard status == errAuthorizationSuccess, let authorization else {
            throw AuthorizationError.failed("无法创建网络设置授权（\(status)）。")
        }
        defer { AuthorizationFree(authorization, []) }

        guard let preferences = SCPreferencesCreateWithAuthorization(
            nil, "UniVPN Isolation" as CFString, nil, authorization
        ) else {
            throw proxyError("读取网络设置")
        }
        guard SCPreferencesLock(preferences, false) else {
            throw proxyError("锁定网络设置")
        }
        defer { SCPreferencesUnlock(preferences) }

        // Other network locations may contain another service named Wi-Fi.
        // networksetup addresses the current location, so restore that one.
        guard let networkSet = SCNetworkSetCopyCurrent(preferences),
              let services = SCNetworkSetCopyServices(networkSet) as? [SCNetworkService] else {
            throw proxyError("读取当前网络位置")
        }
        let matches = services.filter { (SCNetworkServiceGetName($0) as String?) == snapshot.networkService }
        guard matches.count == 1, let service = matches.first,
              let proxies = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeProxies) else {
            throw AuthorizationError.failed("无法唯一定位网络服务“\(snapshot.networkService)”的代理设置；恢复快照已保留。")
        }

        let current = (SCNetworkProtocolGetConfiguration(proxies) as? [String: Any]) ?? [:]
        let restored = try ProxyRestoration.configuration(restoring: snapshot, in: current)
        guard SCNetworkProtocolSetConfiguration(proxies, restored as CFDictionary) else {
            throw proxyError("恢复代理设置")
        }
        guard SCPreferencesCommitChanges(preferences) else {
            throw proxyError("保存代理设置")
        }
        guard SCPreferencesApplyChanges(preferences) else {
            throw proxyError("应用代理设置")
        }
    }

    private static func proxyError(_ action: String) -> AuthorizationError {
        let code = SCError()
        let detail = String(cString: SCErrorString(code))
        return .failed("\(action)失败：\(detail)（\(code)）。恢复快照已保留，请重试。")
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
