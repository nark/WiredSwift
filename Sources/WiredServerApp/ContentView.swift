import SwiftUI

@available(macOS 12.0, *)
struct ContentView: View {
    @EnvironmentObject private var model: WiredServerViewModel
    @State private var selectedTab: WiredTab = .general

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                GeneralTabView()
                    .tabItem {
                        Label("General", systemImage: "switch.2")
                    }
                    .tag(WiredTab.general)

                NetworkTabView()
                    .tabItem {
                        Label("Reseau", systemImage: "network")
                    }
                    .tag(WiredTab.network)

                FilesTabView()
                    .tabItem {
                        Label("Fichiers", systemImage: "folder")
                    }
                    .tag(WiredTab.files)

                AdvancedTabView()
                    .tabItem {
                        Label("Avances", systemImage: "gearshape")
                    }
                    .tag(WiredTab.advanced)

                LogsTabView()
                    .tabItem {
                        Label("Logs", systemImage: "doc.text")
                    }
                    .tag(WiredTab.logs)
            }
        }
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
}

private enum WiredTab: Hashable {
    case general
    case network
    case files
    case advanced
    case logs
}
