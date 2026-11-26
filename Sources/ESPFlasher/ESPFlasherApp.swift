import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ESPFlasherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var theme = ThemeStore()
    @StateObject private var scanner = PortScanner()
    @StateObject private var flasher = Flasher()
    @StateObject private var monitor = SerialMonitor()

    var body: some Scene {
        WindowGroup("ESP Flasher") {
            ContentView()
                .environmentObject(theme)
                .environmentObject(scanner)
                .environmentObject(flasher)
                .environmentObject(monitor)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
