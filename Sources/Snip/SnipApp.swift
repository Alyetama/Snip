import SwiftUI
import AppKit

@main
struct SnipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var model = PlayerModel.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 820, minHeight: 540)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Video…") { PlayerModel.shared.presentOpenPanel() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Export Trimmed…") { PlayerModel.shared.beginExport() }
                    .keyboardShortcut("e", modifiers: .command)
                    .disabled(!model.hasVideo || model.isExporting)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Finder "Open With" / drag onto Dock icon
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in await PlayerModel.shared.load(url: url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
