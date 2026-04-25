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
struct SettingsScrollPane<Content: View>: View {
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
struct SettingsSection<Content: View>: View {
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
private struct ExternalVolumeWarningView: View {
    let hasFDA: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: hasFDA ? "externaldrive.fill.badge.checkmark" : "externaldrive.badge.exclamationmark")
                .foregroundStyle(hasFDA ? .green : .orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(hasFDA ? "Full Disk Access granted for wired3." : "Files directory is on an external volume.")
                    .font(.footnote).bold()
                    .foregroundStyle(hasFDA ? .primary : .orange)
                Text(hasFDA
                    ? "The daemon can access the external drive."
                    : "Grant Full Disk Access to wired3 so the LaunchDaemon can read and write files on this volume."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if !hasFDA {
                Button("Open Settings…") { onOpenSettings() }
                    .font(.footnote)
            }
        }
        .padding(8)
        .background((hasFDA ? Color.green : Color.orange).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
struct GeneralTabView: View {
    @EnvironmentObject private var model: WiredServerViewModel

    var body: some View {
        SettingsScrollPane {
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

                Section("System Data Directory") {
                    if model.isUsingSystemDirectory {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("/Library/Wired3/ (system-wide)")
                                .textSelection(.enabled)
                        }
                    } else if model.systemMigrationAvailable {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Migrate server data to /Library/Wired3/ to enable LaunchDaemon support. The original data will be preserved as a backup.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 10) {
                                Button("Migrate to /Library/Wired3/") {
                                    Task { await model.migrateToSystemDirectory() }
                                }
                                .disabled(model.isSystemMigrating || model.isBusy)

                                if model.isSystemMigrating {
                                    ProgressView().controlSize(.small)
                                }
                            }

                            if !model.systemMigrationStatus.isEmpty {
                                Text(model.systemMigrationStatus)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                Section("Install Mode") {
                    if !model.isUsingSystemDirectory {
                        Label("Migrate to /Library/Wired3/ first to enable LaunchDaemon mode.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    } else {
                        Picker("Mode", selection: Binding(
                            get: { model.installMode },
                            set: { newMode in
                                Task { await model.switchInstallMode(to: newMode) }
                            }
                        )) {
                            Text("LaunchAgent (current user)").tag(ServerInstallMode.launchAgent)
                            Text("LaunchDaemon (system service)").tag(ServerInstallMode.launchDaemon)
                        }
                        .disabled(model.isSwitchingMode || model.isBusy)

                        if model.installMode == .launchDaemon {
                            HStack(spacing: 8) {
                                Text("User")
                                    .bold()
                                    .frame(width: 40, alignment: .leading)
                                TextField("_wired", text: $model.daemonUserName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                    .disabled(model.isSwitchingMode || model.launchDaemonInstalled)
                                Image(systemName: model.daemonUserExists ? "person.fill.checkmark" : "person.fill.xmark")
                                    .foregroundStyle(model.daemonUserExists ? .green : .secondary)

                                Text("Group")
                                    .bold()
                                    .frame(width: 44, alignment: .leading)
                                TextField("staff", text: $model.daemonGroupName)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                                    .disabled(model.isSwitchingMode || model.launchDaemonInstalled)
                                Image(systemName: model.daemonGroupExists ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(model.daemonGroupExists ? .green : .secondary)

                                Spacer()
                                Button("Save") { model.saveDaemonSettings() }
                                    .disabled(model.isSwitchingMode)
                            }
                        }

                        if model.installMode == .launchDaemon && model.filesDirectoryIsOnExternalVolume {
                            ExternalVolumeWarningView(hasFDA: model.wired3HasFullDiskAccess) {
                                model.openFullDiskAccessSettings()
                            }
                        }

                        if model.isSwitchingMode {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(model.modeSwitchStatus)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } else if !model.modeSwitchStatus.isEmpty {
                            Text(model.modeSwitchStatus)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
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
                    if model.installMode == .launchDaemon {
                        HStack {
                            StatusDot(color: model.daemonRunning ? .green : .red)
                            Text(model.daemonRunning ? "Running (daemon)" : "Stopped (daemon)")
                            Spacer()
                            Button(model.daemonRunning ? "Stop" : "Start") {
                                if model.daemonRunning { model.stopDaemon() }
                                else { model.startDaemon() }
                            }
                            .disabled(!model.launchDaemonInstalled)
                        }

                        Toggle("Start at Boot", isOn: Binding(
                            get: { model.daemonStartAtBoot },
                            set: { model.toggleDaemonStartAtBoot($0) }
                        ))
                        .disabled(!model.launchDaemonInstalled)
                    } else {
                        HStack {
                            StatusDot(color: model.isRunning ? .green : .red)
                            Text(model.isRunning ? L("general.execution.running") : L("general.execution.stopped"))
                            Spacer()
                            Button(model.isRunning ? L("general.execution.stop") : L("general.execution.start")) {
                                if model.isRunning { model.stopServer() }
                                else { Task { await model.startServer() } }
                            }
                        }

                        Toggle(L("general.execution.start_on_login"), isOn: Binding(
                            get: { model.launchAtLogin },
                            set: { model.toggleLaunchAtLogin($0) }
                        ))
                    }
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
        SettingsScrollPane {
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
        SettingsScrollPane {
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

                    if model.installMode == .launchDaemon && model.filesDirectoryIsOnExternalVolume {
                        ExternalVolumeWarningView(hasFDA: model.wired3HasFullDiskAccess) {
                            model.openFullDiskAccessSettings()
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
        SettingsScrollPane {
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

                Section(L("database.migration.section")) {
                    // Warning when server is running
                    if model.isRunning {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(L("database.migration.server_warning"))
                                .foregroundStyle(.orange)
                        }
                    }

                    // File picker row
                    HStack(spacing: 8) {
                        Text(L("database.migration.source"))
                            .bold()

                        if model.migrationSourcePath.isEmpty {
                            Text(L("database.migration.source.none"))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text(model.migrationSourcePath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }

                        Spacer(minLength: 0)

                        Button(L("common.choose")) {
                            model.chooseMigrationSource()
                        }
                        .disabled(model.isMigrating)
                    }

                    // Overwrite toggle
                    Toggle(L("database.migration.overwrite"), isOn: $model.migrationOverwrite)
                        .disabled(model.isMigrating)

                    // Start button
                    HStack {
                        Spacer()
                        if model.isMigrating {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 20, height: 20)
                            Text(L("database.migration.running"))
                                .foregroundStyle(.secondary)
                        } else {
                            Button(L("database.migration.run")) {
                                Task { await model.runMigration() }
                            }
                            .disabled(model.migrationSourcePath.isEmpty || model.isRunning)
                        }
                    }

                    // Output area (shown once migration has run)
                    if !model.migrationOutput.isEmpty {
                        ScrollView {
                            Text(model.migrationOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(8)
                        }
                        .frame(minHeight: 180, maxHeight: 300)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    }

                    Text(L("database.migration.help"))
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
        SettingsScrollPane {
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
