import SwiftUI

if #available(macOS 14.0, *) {
    WiredServerApplication.main()
} else {
    fputs("WiredServerApp requires macOS 14.0 or newer.\n", stderr)
}

@available(macOS 14.0, *)
struct WiredServerApplication: App {
    @StateObject private var model = WiredServerViewModel()

    var body: some Scene {
        WindowGroup("Wired Server") {
            ContentView()
                .environmentObject(model)
                .frame(width: 880, height: 440)
        }
        .defaultSize(width: 880, height: 440)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
    }
}
