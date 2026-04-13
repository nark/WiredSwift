import SwiftUI

@available(macOS 12.0, *)
private enum UIConstants {
    static let contentMaxWidth: CGFloat = 860
    static let labelWidth: CGFloat = 260
    static let smallLabelWidth: CGFloat = 180
    static let numberFieldWidth: CGFloat = 90
}

@available(macOS 12.0, *)
private enum Formatters {
    static let integer: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.usesGroupingSeparator = false
        formatter.minimum = 1
        formatter.maximum = 65_535
        return formatter
    }()

    static let nonNegativeInteger: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.usesGroupingSeparator = false
        formatter.minimum = 0
        return formatter
    }()
}

@available(macOS 12.0, *)
private struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .frame(maxWidth: UIConstants.contentMaxWidth, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@available(macOS 12.0, *)
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(.top, 4)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}

@available(macOS 12.0, *)
private struct KeyValueRow<Control: View>: View {
    let title: String
    let labelWidth: CGFloat
    @ViewBuilder let control: Control

    init(title: String, labelWidth: CGFloat = UIConstants.labelWidth, @ViewBuilder control: () -> Control) {
        self.title = title
        self.labelWidth = labelWidth
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .frame(width: labelWidth, alignment: .trailing)

            control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

@available(macOS 12.0, *)
private struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }
}

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
        case .good: return .green
        case .warning: return .orange
        case .critical: return .red
        case .neutral: return .gray
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
        SettingsPane {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("dashboard.title"))
                            .font(.largeTitle.weight(.semibold))
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button(model.isRunning ? L("general.execution.stop") : L("general.execution.start")) {
                            if model.isRunning {
                                model.stopServer()
                            } else {
                                Task { await model.startServer() }
                            }
                        }

                        Button(L("logs.open")) {
                            model.openLogsInFinder()
                        }
                    }
                }

                LazyVGrid(columns: healthColumns, alignment: .leading, spacing: 14) {
                    DashboardHealthCard(title: L("dashboard.health.server"), summary: model.dashboardServerHealth, symbolName: "bolt.heart")
                    DashboardHealthCard(title: L("dashboard.health.host"), summary: model.dashboardHostHealth, symbolName: "desktopcomputer")
                    DashboardHealthCard(title: L("dashboard.health.database"), summary: model.dashboardDatabaseHealth, symbolName: "cylinder.split.1x2")
                    DashboardHealthCard(title: L("dashboard.health.files"), summary: model.dashboardFilesHealth, symbolName: "folder")
                }

                SettingsSection(title: L("dashboard.section.live")) {
                    LazyVGrid(columns: metricsColumns, alignment: .leading, spacing: 14) {
                        DashboardMetricCard(title: L("dashboard.metric.server_status"), value: model.isRunning ? L("general.execution.running") : L("general.execution.stopped"), detail: model.statusMessage, symbolName: model.isRunning ? "play.circle.fill" : "stop.circle.fill", tint: model.isRunning ? .green : .orange)
                        DashboardMetricCard(title: L("dashboard.metric.connected_users"), value: String(model.dashboardConnectedUsers), detail: L("dashboard.metric.connected_users.help"), symbolName: "person.2.fill", tint: .blue)
                        DashboardMetricCard(title: L("dashboard.metric.pid"), value: model.dashboardServerPID, detail: nil, symbolName: "number.square", tint: .secondary)
                        DashboardMetricCard(title: L("dashboard.metric.server_uptime"), value: model.dashboardServerUptime, detail: nil, symbolName: "clock.arrow.circlepath", tint: .mint)
                        DashboardMetricCard(title: L("dashboard.metric.cpu"), value: model.dashboardServerCPU, detail: nil, symbolName: "cpu", tint: .orange)
                        DashboardMetricCard(title: L("dashboard.metric.memory"), value: model.dashboardServerMemory, detail: nil, symbolName: "memorychip", tint: .pink)
                    }
                }

                SettingsSection(title: L("dashboard.section.storage")) {
                    LazyVGrid(columns: metricsColumns, alignment: .leading, spacing: 14) {
                        DashboardMetricCard(title: L("dashboard.metric.files_size"), value: model.dashboardFilesSize, detail: model.serverRootPathDisplay, symbolName: "folder.fill", tint: .teal)
                        DashboardMetricCard(title: L("dashboard.metric.database_size"), value: model.dashboardDatabaseSize, detail: model.databasePath, symbolName: "internaldrive.fill", tint: .indigo)
                        DashboardMetricCard(title: L("dashboard.metric.snapshot"), value: model.dashboardSnapshotSummary, detail: model.dashboardSnapshotSize == "-" ? nil : model.dashboardSnapshotSize, symbolName: "camera.metering.unknown", tint: model.databaseSnapshotInterval == 0 ? .secondary : .blue)
                        DashboardMetricCard(title: L("dashboard.metric.disk_free"), value: model.dashboardDiskFree, detail: model.dashboardDiskDetail, symbolName: "externaldrive.fill", tint: model.dashboardDiskFreeRatio < 0.10 ? .orange : .green)
                        DashboardMetricCard(title: L("dashboard.metric.host_uptime"), value: model.dashboardHostUptime, detail: nil, symbolName: "desktopcomputer", tint: .cyan)
                        DashboardMetricCard(title: L("dashboard.metric.port"), value: String(model.serverPort), detail: model.portStatus.description, symbolName: "network", tint: model.portStatus == .open ? .green : .orange)
                    }
                }

                SettingsSection(title: L("dashboard.section.database")) {
                    LazyVGrid(columns: metricsColumns, alignment: .leading, spacing: 14) {
                        DashboardMetricCard(title: L("dashboard.metric.accounts"), value: String(model.dashboardAccountsCount), detail: nil, symbolName: "person.crop.circle", tint: .blue)
                        DashboardMetricCard(title: L("dashboard.metric.groups"), value: String(model.dashboardGroupsCount), detail: nil, symbolName: "person.3", tint: .purple)
                        DashboardMetricCard(title: L("dashboard.metric.events"), value: String(model.dashboardEventsCount), detail: nil, symbolName: "list.bullet.rectangle", tint: .orange)
                        DashboardMetricCard(title: L("dashboard.metric.boards"), value: String(model.dashboardBoardsCount), detail: nil, symbolName: "text.bubble", tint: .brown)
                        DashboardMetricCard(title: L("dashboard.metric.snapshot_interval"), value: model.databaseSnapshotInterval == 0 ? L("dashboard.snapshot.disabled") : "\(model.databaseSnapshotInterval) s", detail: nil, symbolName: "timer", tint: .blue)
                        DashboardMetricCard(title: L("dashboard.metric.event_retention"), value: retentionLabel, detail: nil, symbolName: "trash.slash", tint: .red)
                    }
                }

                SettingsSection(title: L("dashboard.section.attention")) {
                    DashboardMetricCard(title: L("dashboard.metric.last_error"), value: model.dashboardLastErrorSummary, detail: nil, symbolName: model.dashboardLastErrorLine.isEmpty ? "checkmark.shield" : "exclamationmark.triangle.fill", tint: model.dashboardLastErrorLine.isEmpty ? .green : .orange)
                }
            }
        }
    }

    private var retentionLabel: String {
        model.eventRetentionOptions.first(where: { $0.id == model.eventRetentionPolicy })?.title ?? model.eventRetentionPolicy
    }
}

@available(macOS 12.0, *)
struct GeneralTabView: View {
    @EnvironmentObject private var model: WiredServerViewModel

    var body: some View {
        SettingsPane {
            Form {
                Section(L("general.installation.section")) {
                    HStack(spacing: 8) {
                        Button(L("general.install.install")) {
                            Task { await model.installServer() }
                        }
                        .disabled(model.isInstalled || model.isBusy)

                        Button(L("general.install.uninstall")) {
                            model.uninstallServer()
                        }
                        .disabled(!model.isInstalled || model.isBusy || model.isRunning)

                        Spacer()

                        Image(systemName: model.isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(model.isInstalled ? .green : .secondary)

                        Text(model.isInstalled ? L("general.install.state.installed") : L("general.install.state.uninstalled"))
                            .foregroundStyle(model.isInstalled ? .green : .secondary)
                    }

                    HStack(spacing: 8) {
                        Text(L("general.install.directory"))
                            .bold()

                        Text(model.workingDirectory)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: model.workingDirectory))
                        } label: {
                            Image(systemName: "folder.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Spacer(minLength: 0)

                        Button(L("common.choose")) {
                            model.chooseWorkingDirectory()
                        }
                        .disabled(model.isRunning)
                    }
                }

                Section("Versions") {
                    HStack(spacing: 8) {
                        Text(L("general.install.version"))
                            .bold()
                        Spacer()
                        Text(model.installedServerVersion)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 8) {
                        Text(L("general.install.p7_version"))
                            .bold()
                        Spacer()
                        Text(model.p7ProtocolVersion)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    HStack(spacing: 8) {
                        Text(L("general.install.wired_protocol"))
                            .bold()
                        Spacer()
                        if model.wiredProtocolName != "-" && model.wiredProtocolVersion != "-" {
                            Text("\(model.wiredProtocolName) \(model.wiredProtocolVersion)")
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        } else {
                            Text(model.wiredProtocolVersion)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(L("general.execution.section")) {
                    HStack {
                        StatusDot(color: model.isRunning ? .green : .red)
                        Text(model.isRunning ? L("general.execution.running") : L("general.execution.stopped"))

                        Spacer()

                        Button(model.isRunning ? L("general.execution.stop") : L("general.execution.start")) {
                            if model.isRunning {
                                model.stopServer()
                            } else {
                                Task { await model.startServer() }
                            }
                        }
                    }

                    Toggle(L("general.execution.start_on_login"), isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.toggleLaunchAtLogin($0) }
                    ))
                }

//                if !model.statusMessage.isEmpty {
//                    Text(model.statusMessage)
//                        .font(.footnote)
//                        .foregroundStyle(.secondary)
//                        .frame(maxWidth: .infinity, alignment: .leading)
//                }
            }
            .formStyle(.grouped)
        }
    }
}

@available(macOS 12.0, *)
struct NetworkTabView: View {
    @EnvironmentObject private var model: WiredServerViewModel

    var body: some View {
        SettingsPane {
            Form {
                Section(L("network.section")) {
                    HStack {
                        Text(L("network.port"))
                            .bold()

                        Spacer()

                        TextField("", value: $model.serverPort, formatter: Formatters.integer)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: UIConstants.numberFieldWidth)

                        Button(L("common.save")) {
                            model.saveNetworkSettings()
                        }
                    }

                    HStack(spacing: 8) {
                        StatusDot(color: color(for: model.portStatus))
                        Text(model.portStatus.description)

                        Spacer()

                        Button(L("network.check")) {
                            model.checkPort()
                        }
                    }

                }

                Section {
                    Text(L("network.restart_required"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private func color(for status: PortStatus) -> Color {
        switch status {
        case .unknown:
            return .gray
        case .open:
            return .green
        case .closed:
            return .red
        }
    }
}

@available(macOS 12.0, *)
struct FilesTabView: View {
    @EnvironmentObject private var model: WiredServerViewModel

    var body: some View {
        SettingsPane {
            Form {
                Section(L("files.section")) {
                    HStack {
                        Text(L("files.directory"))
                            .bold()

                        Text(model.filesDirectory)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Button {
                            NSWorkspace.shared.open(URL(fileURLWithPath: model.filesDirectory))
                        } label: {
                            Image(systemName: "folder.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(L("common.choose")) {
                            model.chooseFilesDirectory()
                        }
                    }
                }

                Section(L("files.index.section")) {
                    HStack {
                        Text(L("files.index.every"))

                        TextField("", value: $model.filesReindexInterval, formatter: Formatters.integer)
                            .frame(width: UIConstants.numberFieldWidth)
                            .textFieldStyle(.roundedBorder)

                        Text(L("files.index.seconds"))

                        Spacer(minLength: 0)

                        Button(L("common.save")) {
                            model.saveFilesSettings()
                        }

                        Button(L("files.index.now")) {
                            Task { await model.reindexNow() }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

@available(macOS 12.0, *)
struct DatabaseTabView: View {
    @EnvironmentObject private var model: WiredServerViewModel

    var body: some View {
        SettingsPane {
            Form {
                Section(L("database.snapshot.section")) {
                    HStack {
                        Text(L("database.snapshot.interval"))

                        TextField("", value: $model.databaseSnapshotInterval, formatter: Formatters.nonNegativeInteger)
                            .frame(width: UIConstants.numberFieldWidth)
                            .textFieldStyle(.roundedBorder)

                        Text(L("database.snapshot.seconds"))

                        Spacer(minLength: 0)

                        Button(L("common.save")) {
                            model.saveDatabaseSettings()
                        }
                    }

                    Text(L("database.snapshot.help"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(L("database.events.section")) {
                    Picker(L("database.events.retention"), selection: $model.eventRetentionPolicy) {
                        ForEach(model.eventRetentionOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    .onChange(of: model.eventRetentionPolicy) { _ in
                        model.saveEventRetentionSetting()
                    }

                    Text(L("database.events.help"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }
}

@available(macOS 12.0, *)
struct SecurityTabView: View {
    @EnvironmentObject private var model: WiredServerViewModel
    @State private var fingerprintCopied = false

    var body: some View {
        SettingsPane {
            Form {
                Section(L("advanced.admin.section")) {
                    HStack {
                        StatusDot(color: model.hasAdminPassword ? .green : .red)
                        Text(model.adminStatus)
                    }

                    HStack(spacing: 8) {
                        SecureField(L("advanced.admin.password.placeholder"), text: $model.newAdminPassword)
                            .frame(width: 260)

                        Spacer()

                        Button(L("advanced.admin.set_password")) {
                            model.setAdminPassword()
                        }

                        Button(L("advanced.admin.create_user")) {
                            model.createAdminUser()
                        }
                    }
                }

                Section(L("advanced.security.section")) {
                    Picker(L("advanced.security.compression"), selection: $model.compressionMode) {
                        ForEach(model.compressionOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }

                    Picker(L("advanced.security.cipher"), selection: $model.cipherMode) {
                        ForEach(model.cipherOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }

                    Picker(L("advanced.security.checksum"), selection: $model.checksumMode) {
                        ForEach(model.checksumOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                }

                Section(L("advanced.identity.section")) {
                    // Fingerprint display
                    HStack(spacing: 8) {
                        StatusDot(color: model.identityFingerprint.isEmpty ? .red : .green)
                        if model.identityFingerprint.isEmpty {
                            Text(L("advanced.identity.fingerprint.none"))
                                .foregroundStyle(.secondary)
                                .font(.footnote)
                        } else {
                            Text(model.identityFingerprint)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(2)
                        }
                        Spacer()
                        if !model.identityFingerprint.isEmpty {
                            Button(fingerprintCopied ? L("advanced.identity.copied") : L("advanced.identity.export")) {
                                model.exportIdentityKey()
                            }
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(model.identityFingerprint, forType: .string)
                                fingerprintCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    fingerprintCopied = false
                                }
                            } label: {
                                Image(systemName: fingerprintCopied ? "checkmark" : "doc.on.doc")
                            }
                            .help(L("advanced.identity.copied"))
                        }
                    }

                    // Strict identity toggle
                    HStack(alignment: .top) {
                        Toggle(
                            L("advanced.identity.strict"),
                            isOn: Binding(
                                get: { model.strictIdentity },
                                set: { model.setStrictIdentity($0) }
                            )
                        )
                        Spacer()
                    }
                    Text(L("advanced.identity.strict.help"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button(L("security.save")) {
                        model.saveAdvancedSettings()
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear { model.refreshIdentityFingerprint() }
    }
}

@available(macOS 12.0, *)
struct LogsTabView: View {
    @EnvironmentObject private var model: WiredServerViewModel
    private let bottomAnchorID = "logs-bottom-anchor"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(L("logs.open")) {
                    model.openLogsInFinder()
                }
                Spacer()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.logsText.isEmpty ? L("logs.empty") : model.logsText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(10)

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onAppear {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
                .onChange(of: model.logsText) { _ in
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            }
            .frame(minHeight: 280)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.gray.opacity(0.35), lineWidth: 1)
            )

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
