import SwiftUI

@available(macOS 14.0, *)
struct ContentView: View {
    @EnvironmentObject private var model: WiredServerViewModel
    @State private var selectedPane: SettingsPane = .dashboard

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                Label(pane.title, systemImage: pane.symbolName)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 240, ideal: 240, max: 260)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                if selectedPane == .logs {
                    detailView(for: selectedPane)
                        .padding(20)
                } else {
                    ScrollView {
                        detailView(for: selectedPane)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(20)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            model.startPolling()
            model.refreshAll()
        }
        .onDisappear {
            model.stopPolling()
        }
        .alert(L("alert.error.title"), isPresented: $model.showErrorAlert) {
            Button(L("common.ok"), role: .cancel) {}
        } message: {
            Text(model.lastErrorMessage)
        }
        .alert(L("alert.binary_updated.title"), isPresented: $model.showRestartAfterUpdateAlert) {
            Button(L("alert.binary_updated.restart")) {
                Task { await model.restartServer() }
            }
            Button(L("alert.binary_updated.later"), role: .cancel) {}
        } message: {
            Text(L("alert.binary_updated.message"))
        }
        .alert(L("alert.privileged_update.title"), isPresented: $model.showPrivilegedUpdateAlert) {
            Button(L("alert.privileged_update.install")) {
                model.applyPrivilegedUpdate()
            }
            Button(L("alert.privileged_update.later"), role: .cancel) {}
        } message: {
            Text(L("alert.privileged_update.message"))
        }
        .alert(L("alert.initial_password.title"), isPresented: $model.showInitialPasswordAlert) {
            Button(L("alert.initial_password.copy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.initialAdminPassword, forType: .string)
            }
            Button(L("common.ok"), role: .cancel) {}
        } message: {
            Text("\(L("alert.initial_password.message"))\n\n\(model.initialAdminPassword)")
        }
    }

    @ViewBuilder
    private func detailView(for pane: SettingsPane) -> some View {
        switch pane {
        case .dashboard:
            DashboardTabView()
        case .general:
            GeneralTabView()
        case .network:
            NetworkTabView()
        case .files:
            FilesTabView()
        case .database:
            DatabaseTabView()
        case .security:
            SecurityTabView()
        case .logs:
            LogsTabView()
        }
    }
}

@available(macOS 14.0, *)
private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case general
    case network
    case files
    case database
    case security
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return L("pane.dashboard")
        case .general: return L("pane.general")
        case .network: return L("pane.network")
        case .files: return L("pane.files")
        case .database: return L("pane.database")
        case .security: return L("pane.security")
        case .logs: return L("pane.logs")
        }
    }

    var symbolName: String {
        switch self {
        case .dashboard: return "rectangle.3.group.bubble"
        case .general: return "switch.2"
        case .network: return "network"
        case .files: return "folder"
        case .database: return "cylinder.split.1x2"
        case .security: return "key.horizontal"
        case .logs: return "doc.text"
        }
    }
}
