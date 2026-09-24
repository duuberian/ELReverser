import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) static var shared: AppDelegate?
    weak var sharedViewModel: AudioReverserViewModel?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let viewModel = sharedViewModel,
              viewModel.items.contains(where: { $0.parentID != nil || $0.isDecoded }) else {
            return .terminateNow
        }

        let alert = NSAlert()
        alert.messageText = "Generated audio is temporary"
        alert.informativeText = "Scrambled and decoded files are stored in temporary storage. Save any audio you want to keep before quitting."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        return .terminateNow
    }
}

@main
struct ELReverserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate


    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 700, height: 580)
    }
}
