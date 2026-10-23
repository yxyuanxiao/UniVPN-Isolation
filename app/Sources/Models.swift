import Foundation

enum ConnectionPhase: Sendable {
    case stopped
    case starting
    case waitingForLogin
    case connected
    case fault

    var title: String {
        switch self {
        case .stopped:
            return "未启动"
        case .starting:
            return "正在处理…"
        case .waitingForLogin:
            return "等待 UniVPN 登录"
        case .connected:
            return "隔离 VPN 已连接"
        case .fault:
            return "运行异常"
        }
    }

    var symbolName: String {
        switch self {
        case .stopped:
            return "shield.slash"
        case .starting:
            return "hourglass"
        case .waitingForLogin:
            return "shield.lefthalf.filled"
        case .connected:
            return "checkmark.shield.fill"
        case .fault:
            return "exclamationmark.shield.fill"
        }
    }
}

struct RuntimeStatus: Sendable {
    var containerRunning = false
    var noVNCListening = false
    var socksListening = false
    var pacIsOurs = false
    var proxyAutoConfigEnabled = false
    var proxyAutoConfigURL = ""

    var phase: ConnectionPhase {
        if socksListening {
            return .connected
        }
        if containerRunning && noVNCListening {
            return .waitingForLogin
        }
        if containerRunning {
            return .fault
        }
        return .stopped
    }
}

struct ProxySnapshot: Codable, Sendable {
    let networkService: String
    let autoProxyURL: String
    let autoProxyEnabled: Bool
    let bypassDomains: [String]
    let capturedAt: Date
}

struct TrafficSession: Identifiable, Hashable, Sendable {
    enum Outcome: String, Sendable {
        case connected
        case rejected
        case error

        var title: String {
            switch self {
            case .connected:
                return "已通过"
            case .rejected:
                return "已拒绝"
            case .error:
                return "失败"
            }
        }
    }

    let id: String
    let timestamp: String
    let destination: String
    let outcome: Outcome
    let detail: String
}

struct ProjectPaths: Sendable {
    let root: URL
    let containerBinary: URL
    let pacFile: URL
    let pacURL: URL
    let legacyStopScript: URL
    let recoverySnapshot: URL

    static func resolve() throws -> ProjectPaths {
        let fileManager = FileManager.default
        var candidates: [URL] = []

        if let override = ProcessInfo.processInfo.environment["UNIVPN_ISOLATION_ROOT"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override, isDirectory: true))
        }

        if let bundledRoot = Bundle.main.object(forInfoDictionaryKey: "UniVPNProjectRoot") as? String,
           !bundledRoot.isEmpty,
           bundledRoot != "__PROJECT_ROOT__" {
            candidates.append(URL(fileURLWithPath: bundledRoot, isDirectory: true))
        }

        let appBundle = Bundle.main.bundleURL
        candidates.append(appBundle.deletingLastPathComponent().deletingLastPathComponent())
        candidates.append(URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true))

        guard let root = candidates.first(where: {
            fileManager.isExecutableFile(atPath: $0.appendingPathComponent("runtime/bin/container").path)
                && fileManager.fileExists(atPath: $0.appendingPathComponent("univpn.pac").path)
        }) else {
            throw AppError.message("找不到 UniVPN-Isolation 运行目录。请从项目 dist 目录打开 App。")
        }

        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("UniVPN Isolation", isDirectory: true)
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)

        return ProjectPaths(
            root: root,
            containerBinary: root.appendingPathComponent("runtime/bin/container"),
            pacFile: root.appendingPathComponent("univpn.pac"),
            pacURL: URL(string: "http://127.0.0.1:16080/univpn.pac")!,
            legacyStopScript: root.appendingPathComponent("stop.command"),
            recoverySnapshot: supportDirectory.appendingPathComponent("proxy-before-start.json")
        )
    }
}

enum AppError: LocalizedError, Sendable {
    case message(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .message(let text), .commandFailed(let text):
            return text
        }
    }
}
