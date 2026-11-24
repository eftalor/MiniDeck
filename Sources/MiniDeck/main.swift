import AppKit
import SwiftUI

final class PlayerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var panel: PlayerPanel!
    let model = PlayerModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PlayerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 100),
            // No system title bar: the player draws its own close and minimize buttons.
            styleMask: [.borderless, .miniaturizable, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        // Transparent window so the glass (and its rounded corners) shows through.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.title = "MiniDeck"   // shown on the minimized window in the Dock
        panel.delegate = self

        let floating = UserDefaults.standard.object(forKey: "floating") as? Bool ?? true
        panel.level = floating ? .floating : .normal

        let view = PlayerView(model: model, onToggleFloat: { [weak self] in self?.toggleFloat() },
                              isFloating: { [weak self] in self?.panel.level == .floating },
                              onClose: { NSApp.terminate(nil) },
                              onMinimize: { [weak self] in self?.minimize() })
        let host = NSHostingView(rootView: view)
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        if !panel.setFrameUsingName("MiniDeckPanel") { panel.center() }
        panel.setFrameAutosaveName("MiniDeckPanel")
        // A saved frame from an older version may have a different height; keep the top edge.
        let top = panel.frame.maxY
        panel.setContentSize(host.fittingSize)
        panel.setFrameTopLeftPoint(NSPoint(x: panel.frame.minX, y: top))
        panel.orderFrontRegardless()
        // The song list grows the window downward; keep the top edge where it is.
        model.onLayoutChange = { [weak self] in
            DispatchQueue.main.async { DispatchQueue.main.async { self?.fitToContent(animated: true) } }
        }
        // Stop redrawing and slow polling while the player can't be seen.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.model.windowVisible = self.panel.occlusionState.contains(.visible)
        }
        model.start()
    }

    func fitToContent(animated: Bool) {
        guard let host = panel.contentView else { return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let top = panel.frame.maxY
        panel.setFrame(NSRect(x: panel.frame.minX, y: top - size.height, width: size.width, height: size.height),
                       display: true, animate: animated)
        panel.invalidateShadow()
    }

    func toggleFloat() {
        panel.level = panel.level == .floating ? .normal : .floating
        UserDefaults.standard.set(panel.level == .floating, forKey: "floating")
    }

    // Yellow button: minimize to the Dock. Borderless windows can refuse to
    // minimize, so fall back to hiding; the Dock icon brings it back either way.
    func minimize() {
        panel.miniaturize(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.panel.isMiniaturized, self.panel.isVisible else { return }
            self.panel.orderOut(nil)
        }
    }

    // Clicking the Dock icon brings a minimized player back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.write("quit")
        model.saveResumePoint()
        model.quitMusicIfWanted()
    }
}

NSSetUncaughtExceptionHandler { e in
    Log.write("UNCAUGHT \(e.name.rawValue): \(e.reason ?? "") \(e.callStackSymbols.prefix(15).joined(separator: "\n"))")
}
Log.write("start \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "")")
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// A Dock icon is needed so a minimized player can be brought back, and for Cmd+Q.
app.setActivationPolicy(.regular)
let mainMenu = NSMenu()
let appItem = NSMenuItem()
mainMenu.addItem(appItem)
let appMenu = NSMenu()
appMenu.addItem(withTitle: "Quit MiniDeck", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
appItem.submenu = appMenu
app.mainMenu = mainMenu
app.run()
