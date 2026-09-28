import AppKit
import Combine
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
    private var visibilityObserver: AnyCancellable?
    private var pinObserver: AnyCancellable?
    private var visibilityMenuItem: NSMenuItem?
    private var pinMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = HUDPanelController(model: model)
        if model.isHUDVisible { panelController?.show() }
        configureStatusItem()
        visibilityObserver = model.$isHUDVisible.dropFirst().sink { [weak self] visible in
            if visible { self?.panelController?.show() } else { self?.panelController?.hide() }
            self?.visibilityMenuItem?.title = visible ? "隐藏 HUD" : "显示 HUD"
        }
        pinObserver = model.$isHUDPinned.dropFirst().sink { [weak self] pinned in
            self?.pinMenuItem?.title = pinned ? "取消钉住 HUD" : "钉住 HUD"
        }
        model.startListening()
        timer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) { model.stopListening() }

    @objc private func didWake() {
        model.recheckCompletionTimeouts()
        panelController?.ensureVisible()
    }
    @objc private func screenChanged() { panelController?.ensureVisible() }
    @objc private func timerFired() { model.tick() }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Traceflow")
        let menu = NSMenu()
        visibilityMenuItem = menu.addItem(withTitle: model.isHUDVisible ? "隐藏 HUD" : "显示 HUD", action: #selector(toggleHUD), keyEquivalent: "")
        pinMenuItem = menu.addItem(withTitle: model.isHUDPinned ? "取消钉住 HUD" : "钉住 HUD", action: #selector(togglePin), keyEquivalent: "")
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
        visibilityMenuItem?.title = model.isHUDVisible ? "隐藏 HUD" : "显示 HUD"
    }

    @objc private func togglePin() {
        model.isHUDPinned.toggle()
        pinMenuItem?.title = model.isHUDPinned ? "取消钉住 HUD" : "钉住 HUD"
    }

    @objc private func openSettings() { model.openSettingsWindow() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
