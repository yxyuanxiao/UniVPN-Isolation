import Foundation
import SystemConfiguration

enum ProxyRestoration {
    static func configuration(
        restoring snapshot: ProxySnapshot,
        in current: [String: Any]
    ) throws -> [String: Any] {
        guard !snapshot.autoProxyEnabled || !snapshot.autoProxyURL.isEmpty else {
            throw AppError.message("代理恢复快照的 PAC 已启用，但地址为空；快照已保留。")
        }

        // networksetup rejects an empty PAC URL. Remove the optional key to
        // restore an unset URL, while preserving unrelated Clash proxy keys.
        var restored = current
        let urlKey = kSCPropNetProxiesProxyAutoConfigURLString as String
        if snapshot.autoProxyURL.isEmpty {
            restored.removeValue(forKey: urlKey)
        } else {
            restored[urlKey] = snapshot.autoProxyURL
        }
        restored[kSCPropNetProxiesProxyAutoConfigEnable as String] = snapshot.autoProxyEnabled ? 1 : 0

        let bypassKey = kSCPropNetProxiesExceptionsList as String
        if snapshot.bypassDomains.isEmpty {
            restored.removeValue(forKey: bypassKey)
        } else {
            restored[bypassKey] = snapshot.bypassDomains
        }
        return restored
    }
}
