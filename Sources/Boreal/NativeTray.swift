import AppKit
import Combine

/// A menu is a snapshot. Never change its items or status-button geometry while tracking.
@MainActor final class NativeTray: NSObject, NSMenuDelegate {
    private let model: AppModel
    let item: NSStatusItem
    let menu = NSMenu(title: "Boreal")
    private(set) var tracking = false
    private var subscription: AnyCancellable?
    private let openWindow: () -> Void

    init(model: AppModel, openWindow: @escaping () -> Void, install: Bool = true) {
        self.model = model
        self.openWindow = openWindow
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.isVisible = install
        item.button?.image = NSImage(systemSymbolName: "fanblades", accessibilityDescription: "Boreal")
        item.button?.imagePosition = .imageLeading
        subscription = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshLabel() }
        }
        refreshLabel()
        rebuildMenu()
    }
    func refreshLabel() {
        guard !tracking else { return }
        item.button?.title = model.demo ? " DEMO · \(model.trayText)" : " \(model.trayText)"
        item.button?.toolTip = "Boreal — \(model.controlStatus)"
    }
    @discardableResult private func add(_ title: String, action: Selector? = nil, enabled: Bool = true, to parent: NSMenu? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.isEnabled = enabled && action != nil
        (parent ?? menu).addItem(entry)
        return entry
    }
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        tracking = true
        rebuildMenu()
    }
    private func rebuildMenu() {
        menu.removeAllItems()
        add(model.demo ? "Boreal · simulazione" : "Boreal")
        add(model.trayText)
        add(model.controlStatus)
        menu.addItem(.separator())
        add("Apri Boreal", action: #selector(showWindow))
        add("Automatico Apple", action: #selector(restore), enabled: model.canRestore)
        add("Massima ventilazione", action: #selector(fullSpeed), enabled: model.canControl)
        if !model.preferences.profiles.isEmpty {
            let profiles = NSMenu(title: "Profili")
            profiles.autoenablesItems = false
            let parent = NSMenuItem(title: "Profili", action: nil, keyEquivalent: "")
            parent.submenu = profiles
            menu.addItem(parent)
            for profile in model.preferences.profiles {
                let entry = add(profile.name, action: #selector(loadProfile(_:)), enabled: model.canControl, to: profiles)
                entry.representedObject = profile.id.uuidString
            }
        }
        menu.addItem(.separator())
        add("Esci e richiedi Auto", action: #selector(quit))
    }
    func menuDidClose(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        tracking = false
        refreshLabel()
    }
    func showQuickMenu(in view: NSView?) {
        guard let view = view ?? item.button else { return }
        let y = view.isFlipped ? min(50, view.bounds.height) : max(0, view.bounds.height - 50)
        let point = NSPoint(x: max(0, view.bounds.width - 340), y: y)
        menu.popUp(positioning: nil, at: point, in: view)
    }
    @objc private func showWindow() { openWindow() }
    @objc private func restore() { model.restore() }
    @objc private func fullSpeed() { model.fullSpeed() }
    @objc private func loadProfile(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let profile = model.preferences.profiles.first(where: { $0.id.uuidString == id }) else { return }
        model.loadProfile(profile)
    }
    @objc private func quit() { NSApp.terminate(nil) }
    func remove() { subscription = nil; NSStatusBar.system.removeStatusItem(item) }
}
