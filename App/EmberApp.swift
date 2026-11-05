import SwiftUI

/// Container app. Its only job is to ship (and, on first launch, register) the Audio Unit extension.
@main
struct EmberApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .windowResizability(.contentSize)
        #endif
    }
}
