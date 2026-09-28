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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model: AppModel
    private let defaults: UserDefaults
    private(set) var panelController: HUDPanelController?
    private(set) var statusItem: NSStatusItem?
    private var timer: Timer?
    private var visibilityObserver: AnyCancellable?
    private var pinObserver: AnyCancellable?
    private var layoutObserver: AnyCancellable?
    private var visibilityMenuItem: NSMenuItem?
    private var pinMenuItem: NSMenuItem?
    private var layoutMenuItems: [HUDLayoutMode: NSMenuItem] = [:]

    override convenience init() {
        self.init(model: AppModel(), defaults: .standard)
    }

    init(model: AppModel, defaults: UserDefaults = .standard) {
        self.model = model
        self.defaults = defaults
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installHUDControls()
        model.startListening()
        timer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(timerFired), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func installHUDControls() {
        panelController = HUDPanelController(model: model, defaults: defaults)
        if model.isHUDVisible { panelController?.show() }
        configureStatusItem()
        observeHUDState(panel: panelController)
    }

    func observeHUDState(panel: HUDPanelController?) {
        panelController = panel
        visibilityObserver = model.$isHUDVisible.dropFirst().sink { [weak self] visible in
            if visible { self?.panelController?.show() } else { self?.panelController?.hide() }
            self?.scheduleMenuRefresh()
        }
        pinObserver = model.$isHUDPinned.dropFirst().sink { [weak self] _ in
            self?.scheduleMenuRefresh()
        }
        layoutObserver = model.$hudLayoutMode.dropFirst().sink { [weak self] _ in
            self?.scheduleMenuRefresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) { model.commitTransparency(); model.stopListening() }

    @objc private func didWake() {
        model.recheckCompletionTimeouts()
        panelController?.ensureVisible()
    }
    @objc private func screenChanged() { panelController?.ensureVisible() }
    @objc private func timerFired() { model.tick() }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.path.ecg", accessibilityDescription: "Traceflow")
        let menu = makeMenu()
        item.menu = menu
        statusItem = item
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        visibilityMenuItem = menu.addItem(withTitle: "显示 HUD", action: #selector(toggleHUD), keyEquivalent: "")
        pinMenuItem = menu.addItem(withTitle: "钉住 HUD", action: #selector(togglePin), keyEquivalent: "")
        let layoutItem = menu.addItem(withTitle: "HUD 布局", action: nil, keyEquivalent: "")
        let layoutMenu = NSMenu(title: "HUD 布局")
        layoutMenu.delegate = self
        layoutMenuItems.removeAll()
        for layout in HUDLayoutMode.allCases {
            let item = layoutMenu.addItem(withTitle: layout.menuTitle, action: #selector(selectLayout(_:)), keyEquivalent: "")
            item.representedObject = layout.rawValue
            item.target = self
            layoutMenuItems[layout] = item
        }
        layoutItem.submenu = layoutMenu
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 Traceflow", action: #selector(quit), keyEquivalent: "q")
        for menuItem in menu.items { menuItem.target = self }
        refreshMenuState()
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refreshMenuState() }

    private func scheduleMenuRefresh() {
        // @Published emits before its stored property changes.
        DispatchQueue.main.async { [weak self] in self?.refreshMenuState() }
    }

    func refreshMenuState() {
        visibilityMenuItem?.state = model.isHUDVisible ? .on : .off
        pinMenuItem?.state = model.isHUDPinned ? .on : .off
        for (layout, item) in layoutMenuItems {
            item.state = model.hudLayoutMode == layout ? .on : .off
        }
    }

    @objc private func toggleHUD() {
        model.isHUDVisible.toggle()
    }

    @objc private func togglePin() {
        model.isHUDPinned.toggle()
    }

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let layout = HUDLayoutMode(rawValue: rawValue),
              layout != model.hudLayoutMode else { return }
        model.hudLayoutMode = layout
    }

    @objc private func openSettings() { model.openSettingsWindow() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
