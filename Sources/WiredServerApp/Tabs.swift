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
        formatter.numberStyle = .decimal
        formatter.allowsFloats = false
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
struct GeneralTabView: View {
    @EnvironmentObject private var model: WiredServerViewModel

    var body: some View {
        SettingsPane {
            Form {
                Section("Installation") {
                    HStack(spacing: 8) {
                        Button("Install") {
                            Task { await model.installServer() }
                        }
                        .disabled(model.isInstalled || model.isBusy)

                        Button("Uninstall") {
                            model.uninstallServer()
                        }
                        .disabled(!model.isInstalled || model.isBusy || model.isRunning)

                        Spacer()
                        
                        Image(systemName: model.isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(model.isInstalled ? .green : .secondary)
                        
                        Text(model.isInstalled ? "Installed" : "Uninstalled")
                            .foregroundStyle(model.isInstalled ? .green : .secondary)
                    }
                    
                    HStack(spacing: 8) {
                        Text("Install directory")
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

                        Button("Choisir") {
                            model.chooseWorkingDirectory()
                        }
                        .disabled(model.isRunning)
                    }

                    HStack(spacing: 8) {
                        Text("Version")
                            .bold()
                        
                        Spacer()
                        
                        Text(model.installedServerVersion)
                            .textSelection(.enabled)
                        
                    }
                }
                
                Section("Execution") {
                    HStack {
                        StatusDot(color: model.isRunning ? .green : .red)
                        Text(model.isRunning ? "Server is running" : "Server is not running")
                        
                        Spacer()
                        
                        Button(model.isRunning ? "Stop" : "Start") {
                            if model.isRunning {
                                model.stopServer()
                            } else {
                                Task { await model.startServer() }
                            }
                        }
                    }
                    
                    Toggle("Automatically start on system startup", isOn: Binding(
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
                Section("Network") {
                    HStack {
                        Text("Listening Port")
                            .bold()
                        
                        Spacer()
                        
                        TextField("", value: $model.serverPort, formatter: Formatters.integer)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: UIConstants.numberFieldWidth)
                        
                        Button("Save") {
                            model.saveNetworkSettings()
                        }
                    }
                    
                    HStack(spacing: 8) {
                        StatusDot(color: color(for: model.portStatus))
                        Text(model.portStatus.description)
                        
                        Spacer()
                        
                        Button("Check") {
                            model.checkPort()
                        }
                    }
                    
                }
                
                Section {
                    Text("Server must be restarted after port change.")
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
                Section("Files") {
                    HStack {
                        Text("Files directory")
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
                        
                        Button("Choisir") {
                            model.chooseFilesDirectory()
                        }
                    }
                }
                
                Section("Index") {
                    HStack {
                        Text("Re-index server files every")
                        
                        TextField("", value: $model.filesReindexInterval, formatter: Formatters.integer)
                            .frame(width: UIConstants.numberFieldWidth)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("sec.")

                        Spacer(minLength: 0)

                        Button("Save") {
                            model.saveFilesSettings()
                        }

                        Button("Re-index") {
                            model.saveFilesSettings()
                            
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
struct AdvancedTabView: View {
    @EnvironmentObject private var model: WiredServerViewModel

    var body: some View {
        SettingsPane {
            Form {
                Section("Admin account") {
                    HStack {
                        StatusDot(color: model.hasAdminPassword ? .green : .red)
                        Text(model.adminStatus)
                    }
                    
                    HStack(spacing: 8) {
                        SecureField("Mot de passe admin", text: $model.newAdminPassword)
                            .frame(width: 260)
                        
                        Spacer()

                        Button("Definir") {
                            model.setAdminPassword()
                        }

                        Button("Creer admin") {
                            model.createAdminUser()
                        }
                    }
                }
                
                Section("Security") {
                    Picker("Preferred Compression", selection: $model.compressionMode) {
                        ForEach(model.compressionOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    
                    Picker("Preferred Cipher", selection: $model.cipherMode) {
                        ForEach(model.cipherOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    
                    Picker("Preferred Checksum", selection: $model.checksumMode) {
                        ForEach(model.checksumOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                }
                
                HStack {
                    Spacer()
                    Button("Enregistrer les parametres avances") {
                        model.saveAdvancedSettings()
                    }
                }
            }
            .formStyle(.grouped)
        }
    }
}

@available(macOS 12.0, *)
struct LogsTabView: View {
    @EnvironmentObject private var model: WiredServerViewModel
    private let bottomAnchorID = "logs-bottom-anchor"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button("Ouvrir les logs") {
                    model.openLogsInFinder()
                }
                Spacer()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(model.logsText.isEmpty ? "Aucun log pour l'instant" : model.logsText)
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
