import AppKit
import SwiftUI

@main
struct UniVPNIsolationMenuBarApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.phase.symbolName)
                .symbolRenderingMode(.hierarchical)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            Label(model.isBusy ? model.actionText : model.phase.title, systemImage: model.phase.symbolName)

            if model.runtimeStatus.containerRunning {
                Text(model.runtimeStatus.socksListening
                     ? "SOCKS 127.0.0.1:15902 · 已就绪"
                     : "SOCKS 127.0.0.1:15902 · 等待 VPN")
                Text(model.runtimeStatus.pacIsOurs
                     ? "PAC 分流 · 已启用"
                     : "PAC 分流 · 未由本 App 确认")
            }

            Divider()

            Button("启动隔离 VPN") {
                model.start()
            }
            .disabled(!model.canStart)

            Button("打开 UniVPN 登录窗口") {
                model.showLoginWindow()
            }
            .disabled(!model.runtimeStatus.noVNCListening)

            Button("重启隔离连接…") {
                model.restartConnection()
            }
            .disabled(!model.canRestart)

            Button("重新加载分流 PAC…") {
                model.reloadPAC()
            }
            .disabled(!model.canReloadPAC)

            Button("查看经过 VPN 的流量…") {
                model.showTrafficWindow()
            }
            .disabled(!model.runtimeStatus.containerRunning)

            if model.canStopManagedSession {
                Button(model.runtimeStatus.containerRunning ? "停止隔离 VPN" : "恢复代理设置") {
                    model.stopManagedSession()
                }
            } else if model.isLegacySession {
                Button("用旧脚本停止本次会话…") {
                    model.openLegacyStopScript()
                }
            }

            Divider()

            Text(model.trafficSummary)
            Button("刷新状态") {
                model.refresh()
            }
            .disabled(model.isBusy)

            Button("打开项目目录") {
                model.openProjectFolder()
            }

            Divider()

            Button("退出菜单栏程序") {
                model.quit()
            }
        }
    }
}

struct TrafficView: View {
    @ObservedObject var model: AppModel

    private var passedCount: Int {
        model.traffic.filter { $0.outcome == .connected }.count
    }

    private var rejectedCount: Int {
        model.traffic.filter { $0.outcome == .rejected }.count
    }

    private var uniqueTargets: Int {
        Set(model.traffic.filter { $0.outcome == .connected }.map(\.destination)).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("隔离 VPN 流量")
                        .font(.title2.weight(.semibold))
                    Text("实际进入容器内 Dante SOCKS 的 TCP 连接")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
            }

            HStack(spacing: 12) {
                MetricCard(title: "已通过", value: "\(passedCount)", color: .green)
                MetricCard(title: "目标", value: "\(uniqueTargets)", color: .blue)
                MetricCard(title: "已拒绝", value: "\(rejectedCount)", color: .orange)
            }

            if model.traffic.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("暂时没有 TCP 会话")
                        .font(.headline)
                    Text("访问 10.10.128.0/24 后，这里会显示目标 IP 和端口。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.traffic) { session in
                    HStack(spacing: 12) {
                        Image(systemName: icon(for: session.outcome))
                            .foregroundStyle(color(for: session.outcome))
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.destination)
                                .font(.system(.body, design: .monospaced).weight(.medium))
                            Text(session.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(session.outcome.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(color(for: session.outcome))
                            Text(session.timestamp)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }

            Text("只统计经过 127.0.0.1:15902 的 TCP。DIRECT、Clash 公网流量、UDP 和 ping 不在此列表中；日志保留在隔离容器的 /tmp/danted.log。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(minWidth: 720, minHeight: 480)
    }

    private func icon(for outcome: TrafficSession.Outcome) -> String {
        switch outcome {
        case .connected: return "arrow.right.circle.fill"
        case .rejected: return "hand.raised.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }

    private func color(for outcome: TrafficSession.Outcome) -> Color {
        switch outcome {
        case .connected: return .green
        case .rejected: return .orange
        case .error: return .red
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}
