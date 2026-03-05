import SwiftUI

@available(macOS 13.0, *)
struct ContentView: View {
    @EnvironmentObject private var model: WiredServerViewModel
    @State private var selectedPane: SettingsPane = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                Label(pane.title, systemImage: pane.symbolName)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
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
        .alert("Erreur", isPresented: $model.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastErrorMessage)
        }
    }

    @ViewBuilder
    private func detailView(for pane: SettingsPane) -> some View {
        switch pane {
        case .general:
            GeneralTabView()
        case .network:
            NetworkTabView()
        case .files:
            FilesTabView()
        case .advanced:
            AdvancedTabView()
        case .logs:
            LogsTabView()
        }
    }
}

@available(macOS 13.0, *)
private enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case network
    case files
    case advanced
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .network: return "Reseau"
        case .files: return "Fichiers"
        case .advanced: return "Avances"
        case .logs: return "Logs"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "switch.2"
        case .network: return "network"
        case .files: return "folder"
        case .advanced: return "gearshape"
        case .logs: return "doc.text"
        }
    }
}
