import AppKit
import SwiftUI
import Carbon
#if SWIFT_PACKAGE
import TasklistCore
#endif

final class TaskPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: TaskPanel!
    private var store: AppStore!
    private var statusItem: NSStatusItem!
    private var hotkey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var toggleSamples: [Double] = []
    private var diagnosticsURL: URL?
    private var lastToggleAction = "launch"
    private var lastToggleDuration = 0.0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launch Services normally enforces this; also guard direct executable launches.
        if let bundleID = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        let args = ProcessInfo.processInfo.arguments
        func argument(_ name: String) -> String? {
            guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
            return args[index + 1]
        }
        let dataURL = argument("--data-path").map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Tasklist/tasks.json")
        diagnosticsURL = argument("--diagnostics").map { URL(fileURLWithPath: $0) }
        store = AppStore(url: dataURL)
        store.hidePanel = { [weak self] in self?.hide() }
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        setupPanel()
        setupStatusItem()
        registerHotkey()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.store.handleKey(event) ? nil : event
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.panel, self.panel.isVisible else { return event }
            // Leave the horizontal tab strip's own scrolling alone.
            guard event.locationInWindow.y < self.panel.frame.height - 110 else { return event }
            return self.store.handleScroll(event) ? nil : event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(writeDiagnostics), name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(writeDiagnostics), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        if !args.contains("--hidden") { show() }
    }

    private func setupPanel() {
        panel = TaskPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 560), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Tasklist"
        panel.identifier = NSUserInterfaceItemIdentifier("TasklistPanel")
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = NSAppearance(named: .darkAqua)
        // Keep the window opaque at the compositor level so sharp background text
        // cannot leak through the blur. Translucency belongs to the backdrop only.
        panel.alphaValue = 1
        panel.hasShadow = true
        panel.isMovable = false
        panel.animationBehavior = .none
        let host = NSHostingView(rootView: PanelView(store: store))
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 560)
        host.autoresizingMask = [.width, .height]
        let backdrop = NSView(frame: host.frame)
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = 24
        backdrop.layer?.masksToBounds = true

        let blur = NSVisualEffectView(frame: host.frame)
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        backdrop.addSubview(blur)

        // A flat tint over the system blur: no refractive glass highlights or
        // vibrant content. The hosting view is a sibling, outside the effect.
        let tint = NSView(frame: host.frame)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.30).cgColor
        tint.autoresizingMask = [.width, .height]
        backdrop.addSubview(tint)
        backdrop.addSubview(host)
        panel.contentView = backdrop
    }

    private func setupMainMenu() {
        // Standard edit commands are needed for native text fields in an accessory app.
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Tasklist", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", Selector(("undo:")), "z"), ("Redo", Selector(("redo:")), "Z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Tasklist")
            button.toolTip = "Tasklist · ⌘⌥;"
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let toggle = menu.addItem(withTitle: "Show / Hide Tasklist", action: #selector(togglePanel), keyEquivalent: "")
            toggle.target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Tasklist", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else { togglePanel() }
    }

    private func registerHotkey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().togglePanel()
            }
            return noErr
        }, 1, &eventType, context, &eventHandler)
        guard handlerStatus == noErr else {
            store.hotkeyError = "Couldn’t install the shortcut handler (\(handlerStatus)). Use the menu-bar icon."
            return
        }
        let id = EventHotKeyID(signature: 0x544C5354, id: 1)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_Semicolon), UInt32(cmdKey | optionKey), id, GetApplicationEventTarget(), 0, &hotkey)
        if status != noErr { store.hotkeyError = "⌘⌥; is unavailable (\(status)). Check for another app using it; the menu-bar icon still works." }
    }

    @objc func togglePanel() {
        if panel.isVisible { hide() } else { show() }
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.minX + 16, y: frame.minY + 16))
    }
    @objc private func screenChanged() { if panel.isVisible { positionPanel() } }

    private func show() {
        let start = ProcessInfo.processInfo.systemUptime
        positionPanel()
        // A nonactivating panel can become key for typing without activating the app
        // or asking macOS to bring a different Space forward.
        panel.orderFrontRegardless()
        panel.makeKey()
        store.focusEntry()
        panel.displayIfNeeded()
        recordToggle(start: start, action: "show")
    }

    private func hide() {
        let start = ProcessInfo.processInfo.systemUptime
        store.cancelSwipe()
        store.draggedTaskID = nil
        store.dropTargetID = nil
        store.appearanceTabID = nil
        if NSColorPanel.sharedColorPanelExists { NSColorPanel.shared.orderOut(nil) }
        store.flush()
        panel.orderOut(nil)
        recordToggle(start: start, action: "hide")
    }

    private func recordToggle(start: TimeInterval, action: String) {
        guard diagnosticsURL != nil else { return }
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        toggleSamples.append(elapsed)
        toggleSamples = Array(toggleSamples.suffix(200))
        lastToggleAction = action
        lastToggleDuration = elapsed
        writeDiagnostics()
    }

    @objc private func writeDiagnostics() {
        guard let diagnosticsURL, let panel else { return }
        let data: [String: Any] = ["lastAction": lastToggleAction, "lastDurationMS": lastToggleDuration, "samplesMS": toggleSamples, "visible": panel.isVisible, "isKey": panel.isKeyWindow, "frame": NSStringFromRect(panel.frame), "spaceActive": panel.isOnActiveSpace, "onScreen": panel.occlusionState.contains(.visible), "frontmostApp": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "", "appActive": NSApp.isActive, "pid": ProcessInfo.processInfo.processIdentifier]
        if let json = try? JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]) { try? json.write(to: diagnosticsURL, options: .atomic) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return false }
    func applicationWillTerminate(_ notification: Notification) {
        store?.flush()
        if let hotkey { UnregisterEventHotKey(hotkey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
}
