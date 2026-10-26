import Foundation

struct CommandResult: Sendable {
    let status: Int32
    let output: String
}

enum CommandRunner {
    static func run(
        _ executable: URL,
        _ arguments: [String] = [],
        allowFailure: Bool = false
    ) async throws -> CommandResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = executable
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let output = String(decoding: data, as: UTF8.self)
            let result = CommandResult(status: process.terminationStatus, output: output)
            if !allowFailure && result.status != 0 {
                let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
                throw AppError.commandFailed(detail.isEmpty ? "命令执行失败（\(result.status)）" : detail)
            }
            return result
        }.value
    }
}

enum Backend {
    private static let containerName = "univpn-isolation"

    static func fetchStatus(paths: ProjectPaths) async -> RuntimeStatus {
        async let containerResult = try? CommandRunner.run(
            paths.containerBinary,
            ["list", "--all"],
            allowFailure: true
        )
        async let listenersResult = try? CommandRunner.run(
            URL(fileURLWithPath: "/usr/sbin/lsof"),
            ["-nP", "-a", "-iTCP:15902", "-iTCP:16080", "-sTCP:LISTEN"],
            allowFailure: true
        )
        async let proxyResult = try? CommandRunner.run(
            URL(fileURLWithPath: "/usr/sbin/scutil"),
            ["--proxy"],
            allowFailure: true
        )
        async let backendResult = try? CommandRunner.run(
            paths.containerBinary,
            [
                "exec", containerName, "/bin/sh", "-c",
                "pgrep -x danted >/dev/null && echo dante=1 || echo dante=0; "
                    + "pgrep -f '[w]ebsockify' >/dev/null && echo novnc=1 || echo novnc=0"
            ],
            allowFailure: true
        )

        let containerOutput = await containerResult?.output ?? ""
        let listenerOutput = await listenersResult?.output ?? ""
        let proxyOutput = await proxyResult?.output ?? ""
        let backendOutput = await backendResult?.output ?? ""

        var status = RuntimeStatus()
        status.containerRunning = containerOutput
            .split(separator: "\n")
            .dropFirst()
            .contains { line in
                line.hasPrefix(containerName) && line.contains("running")
            }
        status.noVNCListening = listenerOutput.contains("127.0.0.1:16080 (LISTEN)")
            && backendOutput.split(separator: "\n").contains("novnc=1")
        status.socksListening = listenerOutput.contains("127.0.0.1:15902 (LISTEN)")
            && backendOutput.split(separator: "\n").contains("dante=1")
        status.proxyAutoConfigEnabled = proxyOutput.contains("ProxyAutoConfigEnable : 1")

        if let line = proxyOutput.split(separator: "\n").first(where: {
            $0.contains("ProxyAutoConfigURLString")
        }), let separator = line.firstIndex(of: ":") {
            status.proxyAutoConfigURL = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        status.pacIsOurs = status.proxyAutoConfigEnabled
            && status.proxyAutoConfigURL == paths.pacURL.absoluteString
        return status
    }

    static func startRuntime(paths: ProjectPaths) async throws {
        let systemStart = try await CommandRunner.run(
            paths.containerBinary,
            ["system", "start"],
            allowFailure: true
        )
        if systemStart.status != 0 {
            let normalized = systemStart.output.lowercased()
            if !normalized.contains("already") && !normalized.contains("running") {
                throw AppError.commandFailed(systemStart.output)
            }
        }

        let listing = try await CommandRunner.run(
            paths.containerBinary,
            ["list", "--all"],
            allowFailure: true
        )
        let isRunning = listing.output.split(separator: "\n").dropFirst().contains {
            $0.hasPrefix(containerName) && $0.contains("running")
        }
        if !isRunning {
            _ = try await CommandRunner.run(paths.containerBinary, ["start", containerName])
        }

        try await waitForNoVNC(paths: paths)

        // `container system start` can restore the container before vmnet NAT
        // has public egress. UniVPN immediately consumes its only automatic
        // connection attempt and then remains on "Fail to establish..." even
        // after NAT recovers. If the real gateway is not reachable on the
        // first probe, wait for it and restart only this container once.
        if try await !vpnGatewayIsReachable(paths: paths) {
            try await waitForVPNGateway(paths: paths)
            _ = try await CommandRunner.run(
                paths.containerBinary,
                ["stop", "--time", "10", containerName]
            )
            _ = try await CommandRunner.run(paths.containerBinary, ["start", containerName])
            try await waitForNoVNC(paths: paths)
        }
        try await publishPAC(paths: paths)
    }

    static func restartRuntime(paths: ProjectPaths) async throws {
        let listing = try await CommandRunner.run(
            paths.containerBinary,
            ["list", "--all"],
            allowFailure: true
        )
        let runningNames = listing.output
            .split(separator: "\n")
            .dropFirst()
            .filter { $0.contains("running") }
            .compactMap { $0.split(whereSeparator: \.isWhitespace).first.map(String.init) }
        let unrelated = runningNames.filter { $0 != containerName }
        if !unrelated.isEmpty {
            throw AppError.message(
                "检测到其他运行中的 Apple Container：\(unrelated.joined(separator: ", "))。"
                    + "为避免中断它们，本次没有重启容器后台。"
            )
        }

        if runningNames.contains(containerName) {
            _ = try await CommandRunner.run(
                paths.containerBinary,
                ["stop", "--time", "10", containerName]
            )
        }

        _ = try await CommandRunner.run(
            paths.containerBinary,
            ["system", "stop"],
            allowFailure: true
        )

        let systemStart = try await CommandRunner.run(
            paths.containerBinary,
            ["system", "start"],
            allowFailure: true
        )
        if systemStart.status != 0 {
            let normalized = systemStart.output.lowercased()
            if !normalized.contains("already") && !normalized.contains("running") {
                throw AppError.commandFailed(systemStart.output)
            }
        }

        _ = try await CommandRunner.run(paths.containerBinary, ["start", containerName])
        try await waitForNoVNC(paths: paths)

        // A freshly restarted vmnet NAT can accept management traffic before
        // public egress is usable. UniVPN starts immediately and may consume
        // its one automatic attempt during that warm-up window. Wait until the
        // real VPN gateway is reachable, then restart only this container once
        // so the retry starts on a stable NAT path.
        try await waitForVPNGateway(paths: paths)
        let statusAfterWarmup = await fetchStatus(paths: paths)
        if !statusAfterWarmup.socksListening {
            _ = try await CommandRunner.run(
                paths.containerBinary,
                ["stop", "--time", "10", containerName]
            )
            _ = try await CommandRunner.run(paths.containerBinary, ["start", containerName])
            try await waitForNoVNC(paths: paths)
        }
        try await publishPAC(paths: paths)
    }

    static func stopRuntime(paths: ProjectPaths) async throws {
        let listing = try await CommandRunner.run(
            paths.containerBinary,
            ["list", "--all"],
            allowFailure: true
        )
        let exists = listing.output.split(separator: "\n").dropFirst().contains {
            $0.hasPrefix(containerName)
        }
        if exists {
            _ = try await CommandRunner.run(
                paths.containerBinary,
                ["stop", "--time", "10", containerName],
                allowFailure: true
            )
        }
        _ = try await CommandRunner.run(
            paths.containerBinary,
            ["system", "stop"],
            allowFailure: true
        )
    }

    static func waitForRestrictedSOCKS(paths: ProjectPaths) async throws {
        for _ in 0..<900 {
            let status = await fetchStatus(paths: paths)
            if status.socksListening {
                return
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw AppError.message(
            "15 分钟内没有检测到受限 SOCKS。请检查 UniVPN 登录或服务器证书提示。"
        )
    }

    static func captureProxySnapshot() async throws -> ProxySnapshot {
        let service = try await activeNetworkService()
        let autoProxy = try await CommandRunner.run(
            URL(fileURLWithPath: "/usr/sbin/networksetup"),
            ["-getautoproxyurl", service]
        ).output
        let bypass = try await CommandRunner.run(
            URL(fileURLWithPath: "/usr/sbin/networksetup"),
            ["-getproxybypassdomains", service],
            allowFailure: true
        ).output

        let url = autoProxyURL(from: autoProxy)
        let enabledText = value(after: "Enabled:", in: autoProxy)?.lowercased() ?? "no"
        let noBypassMessage = bypass.lowercased().contains("aren't any bypass domains")
            || bypass.lowercased().contains("there are no bypass domains")
        let domains = noBypassMessage ? [] : bypass
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return ProxySnapshot(
            networkService: service,
            autoProxyURL: url,
            autoProxyEnabled: enabledText == "yes",
            bypassDomains: domains,
            capturedAt: Date()
        )
    }

    static func saveProxySnapshot(_ snapshot: ProxySnapshot, paths: ProjectPaths) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: paths.recoverySnapshot, options: .atomic)
    }

    static func autoProxyURL(from output: String) -> String {
        let url = value(after: "URL:", in: output) ?? ""
        // networksetup uses this sentinel when the optional URL key is absent.
        return url == "(null)" ? "" : url
    }

    static func loadProxySnapshot(paths: ProjectPaths) throws -> ProxySnapshot? {
        guard FileManager.default.fileExists(atPath: paths.recoverySnapshot.path) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProxySnapshot.self, from: Data(contentsOf: paths.recoverySnapshot))
    }

    static func removeProxySnapshot(paths: ProjectPaths) throws {
        guard FileManager.default.fileExists(atPath: paths.recoverySnapshot.path) else { return }
        try FileManager.default.removeItem(at: paths.recoverySnapshot)
    }

    static func fetchTraffic(paths: ProjectPaths) async -> [TrafficSession] {
        let result = try? await CommandRunner.run(
            paths.containerBinary,
            [
                "exec", containerName, "/bin/sh", "-c",
                "test -f /tmp/danted.log && tail -n 1200 /tmp/danted.log || true"
            ],
            allowFailure: true
        )
        guard let output = result?.output else { return [] }
        return parseTraffic(output)
    }

    private static func activeNetworkService() async throws -> String {
        let route = try await CommandRunner.run(
            URL(fileURLWithPath: "/sbin/route"),
            ["-n", "get", "default"]
        ).output
        guard let interface = value(after: "interface:", in: route), !interface.isEmpty else {
            throw AppError.message("无法确定当前默认网络接口。")
        }

        let order = try await CommandRunner.run(
            URL(fileURLWithPath: "/usr/sbin/networksetup"),
            ["-listnetworkserviceorder"]
        ).output
        var currentService: String?
        for rawLine in order.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            if line.hasPrefix("("), let marker = line.range(of: ") ") {
                currentService = String(line[marker.upperBound...])
            }
            if line.contains("Device: \(interface)") && line.hasSuffix(")"), let currentService {
                return currentService
            }
        }
        throw AppError.message("无法把接口 \(interface) 映射到 macOS 网络服务。")
    }

    private static func waitForNoVNC(paths: ProjectPaths) async throws {
        for _ in 0..<60 {
            let status = await fetchStatus(paths: paths)
            if status.noVNCListening {
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw AppError.message("容器已启动，但登录窗口在 15 秒内没有就绪。")
    }

    private static func waitForVPNGateway(paths: ProjectPaths) async throws {
        for _ in 0..<35 {
            if try await vpnGatewayIsReachable(paths: paths) {
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw AppError.message(
            "容器仍无法连接 VPN 网关 210.75.253.1:443。"
                + "宿主机代理没有被修改，请稍后重试或检查当前网络。"
        )
    }

    private static func vpnGatewayIsReachable(paths: ProjectPaths) async throws -> Bool {
        let probe = try await CommandRunner.run(
            paths.containerBinary,
            [
                "exec", containerName, "/bin/sh", "-c",
                "timeout 2 nc -z -w 1 210.75.253.1 443"
            ],
            allowFailure: true
        )
        return probe.status == 0
    }

    private static func publishPAC(paths: ProjectPaths) async throws {
        _ = try await CommandRunner.run(
            paths.containerBinary,
            [
                "cp",
                paths.pacFile.path,
                "\(containerName):/usr/share/novnc/univpn.pac"
            ]
        )
    }

    private static func value(after prefix: String, in output: String) -> String? {
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    static func parseTraffic(_ log: String) -> [TrafficSession] {
        var sessions: [TrafficSession] = []
        var occurrence = 0

        for rawLine in log.split(separator: "\n") {
            let line = String(rawLine)
            guard line.contains("tcp/connect") else { continue }

            let isStart = line.contains("tcp/connect [:")
            let isRejected = line.contains("block(")
            let isError = line.lowercased().contains("error")
            guard isStart || isRejected || isError else { continue }
            guard let destination = lastIPv4Endpoint(in: line) else { continue }

            occurrence += 1
            let timestamp = String(line.prefix(min(15, line.count)))
            let outcome: TrafficSession.Outcome = isRejected ? .rejected : (isError ? .error : .connected)
            let detail: String
            switch outcome {
            case .connected:
                detail = "TCP 经 127.0.0.1:15902 和 cnem_vnic 转发"
            case .rejected:
                detail = "Dante ACL 阻止了目标"
            case .error:
                detail = "连接发生错误"
            }

            sessions.append(TrafficSession(
                id: "\(timestamp)-\(destination)-\(occurrence)",
                timestamp: timestamp,
                destination: destination,
                outcome: outcome,
                detail: detail
            ))
        }
        return Array(sessions.suffix(200).reversed())
    }

    private static func lastIPv4Endpoint(in line: String) -> String? {
        let pattern = #"(?:^|\s)((?:\d{1,3}\.){3}\d{1,3})\.(\d+)(?=\s|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.matches(in: line, range: range).last,
              let hostRange = Range(match.range(at: 1), in: line),
              let portRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        return "\(line[hostRange]):\(line[portRange])"
    }
}
