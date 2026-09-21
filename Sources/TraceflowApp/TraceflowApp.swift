import AppKit
import SwiftUI
import TraceflowCore

@main
enum TraceflowMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var panelController: HUDPanelController?
    private var statusItem: NSStatusItem?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = HUDPanelController(model: model)
        if model.isHUDVisible { panelController?.show() }
        configureStatusItem()
        model.startListening()
        timer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) { model.stopListening() }

    @objc private func didWake() { model.recheckCompletionTimeouts() }
    @objc private func screenChanged() { panelController?.ensureVisible() }
    @objc private func timerFired() { model.tick() }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Traceflow")
        let menu = NSMenu()
        menu.addItem(withTitle: model.isHUDVisible ? "隐藏 HUD" : "显示 HUD", action: #selector(toggleHUD), keyEquivalent: "")
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Traceflow", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleHUD() {
        model.isHUDVisible.toggle()
        if model.isHUDVisible { panelController?.show() } else { panelController?.hide() }
        statusItem?.menu?.item(at: 0)?.title = model.isHUDVisible ? "隐藏 HUD" : "显示 HUD"
    }

    @objc private func openSettings() { model.openSettingsWindow() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
