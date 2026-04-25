import SwiftUI

@available(macOS 12.0, *)
private struct DashboardHealthCard: View {
    let title: String
    let summary: DashboardHealthSummary
    let symbolName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(title)
                    .font(.headline)
                Spacer()
                Text(summary.title.uppercased())
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(color.opacity(0.12))
                    )
                    .foregroundStyle(color)
            }

            Text(summary.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(NSColor.controlBackgroundColor),
                            color.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var color: Color {
        switch summary.level {
        case .good:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        case .neutral:
            return .gray
        }
    }
}

@available(macOS 12.0, *)
private struct DashboardMetricCard: View {
    let title: String
    let value: String
    let detail: String?
    let symbolName: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(tint)
                    .frame(width: 14)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(primaryValueColor)
                .textSelection(.enabled)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(tint.opacity(0.10), lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var primaryValueColor: Color {
        value == "-" ? .secondary : .primary
    }
}

@available(macOS 12.0, *)
struct DashboardTabView: View {
    @EnvironmentObject private var model: WiredServerViewModel

    private let metricsColumns = [
        GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 14)
    ]

    private let healthColumns = [
        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 14)
    ]

    var body: some View {
        SettingsScrollPane {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("dashboard.title"))
                            .font(.largeTitle.weight(.semibold))
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button(
                            model.isServerActive
                                ? L("general.execution.stop")
                                : L("general.execution.start")
                        ) {
                            if model.isServerActive {
                                if model.installMode == .launchDaemon {
                                    model.stopDaemon()
                                } else {
                                    model.stopServer()
                                }
                            } else {
                                if model.installMode == .launchDaemon {
                                    model.startDaemon()
                                } else {
                                    Task { await model.startServer() }
                                }
                            }
                        }

                        Button(L("logs.open")) {
                            model.openLogsInFinder()
                        }
                    }
                }

                LazyVGrid(columns: healthColumns, alignment: .leading, spacing: 14) {
                    DashboardHealthCard(
                        title: L("dashboard.health.server"),
                        summary: model.dashboardServerHealth,
                        symbolName: "bolt.heart"
                    )
                    DashboardHealthCard(
                        title: L("dashboard.health.host"),
                        summary: model.dashboardHostHealth,
                        symbolName: "desktopcomputer"
                    )
                    DashboardHealthCard(
                        title: L("dashboard.health.database"),
                        summary: model.dashboardDatabaseHealth,
                        symbolName: "cylinder.split.1x2"
                    )
                    DashboardHealthCard(
                        title: L("dashboard.health.files"),
                        summary: model.dashboardFilesHealth,
                        symbolName: "folder"
                    )
                }

                SettingsSection(title: L("dashboard.section.live")) {
                    LazyVGrid(columns: metricsColumns, alignment: .leading, spacing: 14) {
                        DashboardMetricCard(
                            title: L("dashboard.metric.server_status"),
                            value: model.isServerActive
                                ? L("general.execution.running")
                                : L("general.execution.stopped"),
                            detail: model.statusMessage,
                            symbolName: model.isServerActive
                                ? "play.circle.fill"
                                : "stop.circle.fill",
                            tint: model.isServerActive ? .green : .orange
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.connected_users"),
                            value: String(model.dashboardConnectedUsers),
                            detail: L("dashboard.metric.connected_users.help"),
                            symbolName: "person.2.fill",
                            tint: .blue
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.pid"),
                            value: model.dashboardServerPID,
                            detail: nil,
                            symbolName: "number.square",
                            tint: .secondary
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.server_uptime"),
                            value: model.dashboardServerUptime,
                            detail: nil,
                            symbolName: "clock.arrow.circlepath",
                            tint: .mint
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.cpu"),
                            value: model.dashboardServerCPU,
                            detail: nil,
                            symbolName: "cpu",
                            tint: .orange
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.memory"),
                            value: model.dashboardServerMemory,
                            detail: nil,
                            symbolName: "memorychip",
                            tint: .pink
                        )
                    }
                }

                SettingsSection(title: L("dashboard.section.storage")) {
                    LazyVGrid(columns: metricsColumns, alignment: .leading, spacing: 14) {
                        DashboardMetricCard(
                            title: L("dashboard.metric.files_size"),
                            value: model.dashboardFilesSize,
                            detail: model.serverRootPathDisplay,
                            symbolName: "folder.fill",
                            tint: .teal
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.database_size"),
                            value: model.dashboardDatabaseSize,
                            detail: model.databasePath,
                            symbolName: "internaldrive.fill",
                            tint: .indigo
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.snapshot"),
                            value: model.dashboardSnapshotSummary,
                            detail: model.dashboardSnapshotSize == "-"
                                ? nil
                                : model.dashboardSnapshotSize,
                            symbolName: "camera.metering.unknown",
                            tint: model.databaseSnapshotInterval == 0
                                ? .secondary
                                : .blue
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.disk_free"),
                            value: model.dashboardDiskFree,
                            detail: model.dashboardDiskDetail,
                            symbolName: "externaldrive.fill",
                            tint: model.dashboardDiskFreeRatio < 0.10
                                ? .orange
                                : .green
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.host_uptime"),
                            value: model.dashboardHostUptime,
                            detail: nil,
                            symbolName: "desktopcomputer",
                            tint: .cyan
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.port"),
                            value: String(model.serverPort),
                            detail: model.portStatus.description,
                            symbolName: "network",
                            tint: model.portStatus == .open ? .green : .orange
                        )
                    }
                }

                SettingsSection(title: L("dashboard.section.database")) {
                    LazyVGrid(columns: metricsColumns, alignment: .leading, spacing: 14) {
                        DashboardMetricCard(
                            title: L("dashboard.metric.accounts"),
                            value: String(model.dashboardAccountsCount),
                            detail: nil,
                            symbolName: "person.crop.circle",
                            tint: .blue
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.groups"),
                            value: String(model.dashboardGroupsCount),
                            detail: nil,
                            symbolName: "person.3",
                            tint: .purple
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.events"),
                            value: String(model.dashboardEventsCount),
                            detail: nil,
                            symbolName: "list.bullet.rectangle",
                            tint: .orange
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.boards"),
                            value: String(model.dashboardBoardsCount),
                            detail: nil,
                            symbolName: "text.bubble",
                            tint: .brown
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.snapshot_interval"),
                            value: model.databaseSnapshotInterval == 0
                                ? L("dashboard.snapshot.disabled")
                                : "\(model.databaseSnapshotInterval) s",
                            detail: nil,
                            symbolName: "timer",
                            tint: .blue
                        )
                        DashboardMetricCard(
                            title: L("dashboard.metric.event_retention"),
                            value: retentionLabel,
                            detail: nil,
                            symbolName: "trash.slash",
                            tint: .red
                        )
                    }
                }

                SettingsSection(title: L("dashboard.section.attention")) {
                    DashboardMetricCard(
                        title: L("dashboard.metric.last_error"),
                        value: model.dashboardLastErrorSummary,
                        detail: nil,
                        symbolName: model.dashboardLastErrorLine.isEmpty
                            ? "checkmark.shield"
                            : "exclamationmark.triangle.fill",
                        tint: model.dashboardLastErrorLine.isEmpty ? .green : .orange
                    )
                }
            }
        }
    }

    private var retentionLabel: String {
        model.eventRetentionOptions.first(where: {
            $0.id == model.eventRetentionPolicy
        })?.title ?? model.eventRetentionPolicy
    }
}
