import SwiftUI

if #available(macOS 13.0, *) {
    WiredServerApplication.main()
} else {
    fputs("WiredServerApp requires macOS 13.0 or newer.\n", stderr)
}

@available(macOS 13.0, *)
struct WiredServerApplication: App {
    @StateObject private var model = WiredServerViewModel()

    var body: some Scene {
        WindowGroup("Wired Server") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
        }
    }
}
