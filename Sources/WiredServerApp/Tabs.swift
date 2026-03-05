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
            SettingsSection(title: "Installation") {
                HStack(spacing: 8) {
                    Button("Installer") {
                        Task { await model.installServer() }
                    }
                    .disabled(model.isBusy)

                    Button("Desinstaller") {
                        model.uninstallServer()
                    }
                    .disabled(model.isBusy || model.isRunning)

                    Spacer()

                    Text(model.isInstalled ? "Installe" : "Non installe")
                        .foregroundStyle(model.isInstalled ? .green : .secondary)
                }

                KeyValueRow(title: "Dossier runtime") {
                    HStack(spacing: 8) {
                        Text(model.workingDirectory)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Spacer(minLength: 0)

                        Button("Choisir") {
                            model.chooseWorkingDirectory()
                        }
                        .disabled(model.isRunning)
                    }
                }

                KeyValueRow(title: "Binaire") {
                    HStack(spacing: 8) {
                        Text(model.binaryPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Spacer(minLength: 0)

                        Button("Choisir") {
                            model.chooseBinaryPath()
                        }
                        .disabled(model.isRunning)
                    }
                }
            }

            SettingsSection(title: "Execution") {
                HStack {
                    StatusDot(color: model.isRunning ? .green : .red)
                    Text(model.isRunning ? "Serveur actif" : "Serveur arrete")
                    Spacer()
                    Button(model.isRunning ? "Arreter" : "Demarrer") {
                        if model.isRunning {
                            model.stopServer()
                        } else {
                            Task { await model.startServer() }
                        }
                    }
                }

                Toggle("Demarrer le serveur a l'ouverture de l'app", isOn: Binding(
                    get: { model.launchServerAtAppStart },
                    set: { model.toggleLaunchAtAppStart($0) }
                ))

                Toggle("Demarrer a la connexion macOS", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.toggleLaunchAtLogin($0) }
                ))
            }

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

@available(macOS 12.0, *)
struct NetworkTabView: View {
    @EnvironmentObject private var model: WiredServerViewModel

    var body: some View {
        SettingsPane {
            SettingsSection(title: "Reseau") {
                KeyValueRow(title: "Port en ecoute", labelWidth: UIConstants.smallLabelWidth) {
                    HStack(spacing: 8) {
                        TextField("Port", value: $model.serverPort, formatter: Formatters.integer)
                            .frame(width: UIConstants.numberFieldWidth)

                        Button("Enregistrer") {
                            model.saveNetworkSettings()
                        }
                    }
                }

                KeyValueRow(title: "Statut du port", labelWidth: UIConstants.smallLabelWidth) {
                    HStack(spacing: 8) {
                        StatusDot(color: color(for: model.portStatus))
                        Text(model.portStatus.description)
                        Button("Verifier le port") {
                            model.checkPort()
                        }
                    }
                }

                Text("Le serveur doit etre redemarre apres un changement de port.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
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
            SettingsSection(title: "Fichiers") {
                KeyValueRow(title: "Repertoire de fichiers") {
                    HStack(spacing: 8) {
                        Text(model.filesDirectory)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)

                        Spacer(minLength: 0)

                        Button("Choisir") {
                            model.chooseFilesDirectory()
                        }
                    }
                }

                KeyValueRow(title: "Re-indexer toutes les") {
                    HStack(spacing: 8) {
                        TextField("Secondes", value: $model.filesReindexInterval, formatter: Formatters.integer)
                            .frame(width: UIConstants.numberFieldWidth)
                        Text("sec.")

                        Spacer(minLength: 0)

                        Button("Enregistrer") {
                            model.saveFilesSettings()
                        }

                        Button("Re-indexer") {
                            Task { await model.reindexNow() }
                        }
                    }
                }
            }
        }
    }
}

@available(macOS 12.0, *)
struct AdvancedTabView: View {
    @EnvironmentObject private var model: WiredServerViewModel

    var body: some View {
        SettingsPane {
            SettingsSection(title: "Compte admin") {
                HStack {
                    StatusDot(color: model.hasAdminPassword ? .green : .red)
                    Text(model.adminStatus)
                }

                KeyValueRow(title: "Nouveau mot de passe") {
                    HStack(spacing: 8) {
                        SecureField("Mot de passe admin", text: $model.newAdminPassword)
                            .frame(width: 260)

                        Button("Definir") {
                            model.setAdminPassword()
                        }

                        Button("Creer admin") {
                            model.createAdminUser()
                        }
                    }
                }
            }

            SettingsSection(title: "Serveur") {
                KeyValueRow(title: "Nom du serveur") {
                    TextField("", text: $model.serverName)
                        .frame(width: 340)
                }

                KeyValueRow(title: "Description") {
                    TextField("", text: $model.serverDescription)
                        .frame(width: 340)
                }
            }

            SettingsSection(title: "Transfers") {
                KeyValueRow(title: "Telechargements simultanes") {
                    TextField("", value: $model.transferDownloads, formatter: Formatters.integer)
                        .frame(width: UIConstants.numberFieldWidth)
                }

                KeyValueRow(title: "Envois simultanes") {
                    TextField("", value: $model.transferUploads, formatter: Formatters.integer)
                        .frame(width: UIConstants.numberFieldWidth)
                }

                KeyValueRow(title: "Limite download (0 = illimite)") {
                    TextField("", value: $model.downloadSpeed, formatter: Formatters.integer)
                        .frame(width: UIConstants.numberFieldWidth)
                }

                KeyValueRow(title: "Limite upload (0 = illimite)") {
                    TextField("", value: $model.uploadSpeed, formatter: Formatters.integer)
                        .frame(width: UIConstants.numberFieldWidth)
                }
            }

            SettingsSection(title: "Trackers") {
                Toggle("Enregistrer sur trackers", isOn: $model.registerWithTrackers)

                KeyValueRow(title: "Trackers (separes par virgule)") {
                    TextField("", text: $model.trackers)
                        .frame(minWidth: 360)
                }
            }

            SettingsSection(title: "Crypto") {
                KeyValueRow(title: "Compression") {
                    Picker("", selection: $model.compressionMode) {
                        ForEach(model.compressionOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 320, alignment: .leading)
                }

                KeyValueRow(title: "Cipher") {
                    Picker("", selection: $model.cipherMode) {
                        ForEach(model.cipherOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 420, alignment: .leading)
                }

                KeyValueRow(title: "Checksum") {
                    Picker("", selection: $model.checksumMode) {
                        ForEach(model.checksumOptions) { option in
                            Text(option.title).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 320, alignment: .leading)
                }
            }

            HStack {
                Spacer()
                Button("Enregistrer les parametres avances") {
                    model.saveAdvancedSettings()
                }
            }
        }
    }
}

@available(macOS 12.0, *)
struct LogsTabView: View {
    @EnvironmentObject private var model: WiredServerViewModel

    var body: some View {
        SettingsPane {
            SettingsSection(title: "Logs") {
                ScrollView {
                    Text(model.logsText.isEmpty ? "Aucun log pour l'instant" : model.logsText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(10)
                }
                .frame(minHeight: 280)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                )

                HStack {
                    Button("Ouvrir les logs") {
                        model.openLogsInFinder()
                    }
                    Spacer()
                }
            }
        }
    }
}
