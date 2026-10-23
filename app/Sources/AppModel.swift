import AppKit
import Foundation

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var runtimeStatus = RuntimeStatus()
    @Published private(set) var phase: ConnectionPhase = .stopped
    @Published private(set) var isBusy = false
    @Published private(set) var actionText = ""
    @Published private(set) var traffic: [TrafficSession] = []
    @Published private(set) var lastError: String?
    @Published private(set) var hasRecoverySnapshot = false

    let paths: ProjectPaths?
    private var monitorTask: Task<Void, Never>?
    private var loginWindowController: LoginWindowController?
    private var trafficWindowController: TrafficWindowController?

    init() {
        do {
            paths = try ProjectPaths.resolve()
        } catch {
            paths = nil
            lastError = error.localizedDescription
            phase = .fault
        }

        monitorTask = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshStatus()
                if tick % 3 == 0 {
                    await self.refreshTraffic()
                }
                tick += 1
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    deinit {
        monitorTask?.cancel()
    }

    var isLegacySession: Bool {
        runtimeStatus.containerRunning && !hasRecoverySnapshot
    }

    var canStart: Bool {
        paths != nil && !isBusy && !runtimeStatus.containerRunning && !hasRecoverySnapshot
    }

    var canStopManagedSession: Bool {
        paths != nil && !isBusy && hasRecoverySnapshot
    }

    var canRestart: Bool {
        paths != nil && !isBusy && runtimeStatus.containerRunning
    }

    var canReloadPAC: Bool {
        paths != nil && !isBusy && runtimeStatus.socksListening
    }

    var trafficSummary: String {
        guard runtimeStatus.socksListening else { return "流量监视：未连接" }
        let passed = traffic.filter { $0.outcome == .connected }.count
        let targets = Set(traffic.filter { $0.outcome == .connected }.map(\.destination)).count
        return "最近记录：\(passed) 条 / \(targets) 个目标"
    }

    func start() {
        guard canStart, let paths else { return }
        Task {
            isBusy = true
            phase = .starting
            actionText = "正在保存当前代理设置…"
            lastError = nil
            var savedSnapshot: ProxySnapshot?
            var attemptedPACChange = false

            do {
                let snapshot = try await Backend.captureProxySnapshot()
                try Backend.saveProxySnapshot(snapshot, paths: paths)
                savedSnapshot = snapshot
                hasRecoverySnapshot = true

                actionText = "正在启动容器并预热网络…"
                try await Backend.startRuntime(paths: paths)

                actionText = "请完成 UniVPN 登录或证书确认…"
                showLoginWindow()
                try await Backend.waitForRestrictedSOCKS(paths: paths)

                actionText = "等待管理员授权以刷新 PAC…"
                attemptedPACChange = true
                try AdministratorAuthorization.reloadPAC(snapshot: snapshot, pacURL: paths.pacURL)

                actionText = "隔离连接与 PAC 已就绪"
            } catch {
                var reportedError = error.localizedDescription
                let authorizationCancelled: Bool
                if let authorizationError = error as? AdministratorAuthorization.AuthorizationError,
                   case .cancelled = authorizationError {
                    authorizationCancelled = true
                } else {
                    authorizationCancelled = false
                }

                if savedSnapshot != nil, !attemptedPACChange || authorizationCancelled {
                    try? await Backend.stopRuntime(paths: paths)
                    try? Backend.removeProxySnapshot(paths: paths)
                    hasRecoverySnapshot = false
                } else if let snapshot = savedSnapshot {
                    do {
                        try AdministratorAuthorization.restoreProxy(snapshot)
                        try await Backend.stopRuntime(paths: paths)
                        try Backend.removeProxySnapshot(paths: paths)
                        hasRecoverySnapshot = false
                    } catch {
                        reportedError += "\n\n自动恢复未完成，恢复快照已保留；请从菜单选择“恢复代理设置”。"
                        hasRecoverySnapshot = true
                    }
                }
                lastError = reportedError
                showError(reportedError)
            }

            isBusy = false
            actionText = ""
            await refreshStatus()
            await refreshTraffic()
        }
    }

    func stopManagedSession() {
        guard canStopManagedSession, let paths else { return }
        Task {
            isBusy = true
            phase = .starting
            actionText = "正在恢复启动前的代理设置…"
            lastError = nil

            do {
                guard let snapshot = try Backend.loadProxySnapshot(paths: paths) else {
                    throw AppError.message("找不到代理恢复快照，已停止操作。")
                }
                try AdministratorAuthorization.restoreProxy(snapshot)
                actionText = "正在停止隔离容器…"
                try await Backend.stopRuntime(paths: paths)
                try Backend.removeProxySnapshot(paths: paths)
                hasRecoverySnapshot = false
            } catch {
                lastError = error.localizedDescription
                showError(error.localizedDescription)
            }

            isBusy = false
            actionText = ""
            await refreshStatus()
            await refreshTraffic()
        }
    }

    func restartConnection() {
        guard canRestart, let paths else { return }

        let confirmation = NSAlert()
        confirmation.alertStyle = .warning
        confirmation.messageText = "重启隔离连接？"
        confirmation.informativeText = "这会断开当前 TCP 会话并重启 Apple Container 网络后台，"
            + "但不会更改宿主机代理、删除 UniVPN 配置卷或自动忽略证书警告。"
        confirmation.addButton(withTitle: "重启")
        confirmation.addButton(withTitle: "取消")
        guard confirmation.runModal() == .alertFirstButtonReturn else { return }

        Task {
            isBusy = true
            phase = .starting
            actionText = "正在重启容器网络…"
            lastError = nil

            do {
                try await Backend.restartRuntime(paths: paths)
                actionText = "请检查登录或证书提示"
                showLoginWindow()
                try await Backend.waitForRestrictedSOCKS(paths: paths)

                let currentProxy = try await Backend.captureProxySnapshot()
                if currentProxy.autoProxyEnabled,
                   currentProxy.autoProxyURL == paths.pacURL.absoluteString {
                    actionText = "等待管理员授权以刷新 PAC…"
                    try AdministratorAuthorization.reloadPAC(
                        snapshot: currentProxy,
                        pacURL: paths.pacURL
                    )
                }
            } catch {
                lastError = error.localizedDescription
                showError(error.localizedDescription)
            }

            isBusy = false
            actionText = ""
            await refreshStatus()
            await refreshTraffic()
        }
    }

    func reloadPAC() {
        guard canReloadPAC, let paths else { return }

        Task {
            isBusy = true
            actionText = "等待管理员授权以刷新 PAC…"
            lastError = nil

            do {
                let currentProxy = try await Backend.captureProxySnapshot()
                try AdministratorAuthorization.reloadPAC(
                    snapshot: currentProxy,
                    pacURL: paths.pacURL
                )
                actionText = "PAC 已刷新，请重新加载页面"
            } catch {
                lastError = error.localizedDescription
                showError(error.localizedDescription)
            }

            isBusy = false
            actionText = ""
            await refreshStatus()
        }
    }

    func refresh() {
        Task {
            await refreshStatus()
            await refreshTraffic()
        }
    }

    func showLoginWindow() {
        if loginWindowController == nil {
            loginWindowController = LoginWindowController()
        }
        loginWindowController?.show(
            URL(string: "http://127.0.0.1:16080/vnc.html?autoconnect=1&resize=scale")!,
            title: "UniVPN 登录 · 隔离容器"
        )
    }

    func showTrafficWindow() {
        if trafficWindowController == nil {
            trafficWindowController = TrafficWindowController(model: self)
        }
        trafficWindowController?.show()
        Task { await refreshTraffic() }
    }

    func openProjectFolder() {
        guard let paths else { return }
        NSWorkspace.shared.activateFileViewerSelecting([paths.root])
    }

    func openLegacyStopScript() {
        guard let paths else { return }
        NSWorkspace.shared.open(paths.legacyStopScript)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refreshStatus() async {
        guard !isBusy, let paths else { return }
        runtimeStatus = await Backend.fetchStatus(paths: paths)
        phase = runtimeStatus.phase
        hasRecoverySnapshot = FileManager.default.fileExists(atPath: paths.recoverySnapshot.path)
    }

    private func refreshTraffic() async {
        guard let paths, runtimeStatus.containerRunning else {
            traffic = []
            return
        }
        traffic = await Backend.fetchTraffic(paths: paths)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "UniVPN 隔离"
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
