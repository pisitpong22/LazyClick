import AppKit
import LazyClickCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let adapter = MultitouchAdapter()
    private let controller: GestureController
    private var statusItem: NSStatusItem!
    private var settings: SettingsWindowController?
    private var permissionObserver: NSObjectProtocol?
    private var signalSources: [DispatchSourceSignal] = []

    private var deviceCount = 0
    private var abiFault = false

    // Menu items updated in menuWillOpen
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let deviceItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantPermission), keyEquivalent: "")
    private let oneItem = NSMenuItem(title: "One-finger tap: Left Click", action: #selector(toggleGesture(_:)), keyEquivalent: "")
    private let twoItem = NSMenuItem(title: "Two-finger tap: Right Click", action: #selector(toggleGesture(_:)), keyEquivalent: "")
    private let threeItem = NSMenuItem(title: "Three-finger tap: Middle Click", action: #selector(toggleGesture(_:)), keyEquivalent: "")
    private let dragItem = NSMenuItem(title: "Three-finger drag", action: #selector(toggleGesture(_:)), keyEquivalent: "")
    private let styleTrackpadItem = NSMenuItem(title: "Style: Trackpad (1/2/3-finger taps, 3-finger drag)", action: #selector(selectStyle(_:)), keyEquivalent: "")
    private let styleMouseItem = NSMenuItem(title: "Style: Mouse (tap left/right side, tap-and-hold drag)", action: #selector(selectStyle(_:)), keyEquivalent: "")
    private let leftSideItem = NSMenuItem(title: "Tap left side: Left Click", action: #selector(toggleGesture(_:)), keyEquivalent: "")
    private let rightSideItem = NSMenuItem(title: "Tap right side: Right Click", action: #selector(toggleGesture(_:)), keyEquivalent: "")
    private let tapDragItem = NSMenuItem(title: "Tap, then touch and move: Drag", action: #selector(toggleGesture(_:)), keyEquivalent: "")
    private let missionItem = NSMenuItem(title: "Four fingers + move up: Mission Control", action: #selector(toggleGesture(_:)), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    override init() {
        controller = GestureController(
            poster: CGEventPoster(),
            timer: OneShotTimer(),
            config: GestureConfig(),
            cursorProvider: CursorState.location,
            physicalButtonProvider: CursorState.physicalButtonDown
        )
        super.init()
    }

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        controller.updateConfig(Preferences.gestureConfig())
        controller.onABIFault = { [weak self] in
            DispatchQueue.main.async {
                self?.abiFault = true
                self?.refreshStatusIcon()
            }
        }

        controller.onMissionControl = {
            DispatchQueue.main.async { MissionControl.show() }
        }
        MultitouchAdapter.frameHandler = { [controller] base, count, ts in
            controller.handleRawFrame(base, count: count, timestamp: ts)
        }
        adapter.onDevicesStopping = { [controller] in controller.deviceDisconnected() }
        adapter.onDeviceCountChanged = { [weak self] n in
            guard let self else { return }
            if n == 0 { self.controller.deviceDisconnected() }
            self.deviceCount = n
            self.refreshStatusIcon()
        }

        buildStatusItem()
        installSystemObservers()
        installSignalHandlers()

        if !Permission.isTrusted && !Preferences.bool(Preferences.Key.didPromptAccessibility) {
            Preferences.set(true, for: Preferences.Key.didPromptAccessibility)
            Permission.request()
        }
        applyState()
    }

    func applicationWillTerminate(_ notification: Notification) {
        teardown()
    }

    /// Release any held synthetic button, unregister touch callbacks, stop observing hot-plug.
    private func teardown() {
        controller.shutdown()
        adapter.stopMonitoring()
        MultitouchAdapter.frameHandler = nil
    }

    /// Single place that reconciles: enabled preference + permission -> gesture handling + device monitoring.
    private func applyState() {
        let wantsRun = Preferences.bool(Preferences.Key.enabled) && Permission.isTrusted
        if wantsRun {
            controller.setEnabled(true)
            adapter.startMonitoring()
        } else {
            controller.setEnabled(false) // releases any held synthetic button immediately
            adapter.stopMonitoring()
            deviceCount = 0
        }
        refreshStatusIcon()
    }

    // MARK: - Status item & menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        for item in [enabledItem, permissionItem, oneItem, twoItem, threeItem, dragItem, missionItem, loginItem,
                     styleTrackpadItem, styleMouseItem, leftSideItem, rightSideItem, tapDragItem] { item.target = self }
        oneItem.tag = 1; twoItem.tag = 2; threeItem.tag = 3; dragItem.tag = 4; missionItem.tag = 5
        leftSideItem.tag = 6; rightSideItem.tag = 7; tapDragItem.tag = 8
        styleTrackpadItem.tag = 0; styleMouseItem.tag = 1
        enabledItem.image = symbol("power")
        deviceItem.isEnabled = false
        permissionItem.image = symbol("lock.shield")

        menu.addItem(enabledItem)
        menu.addItem(deviceItem)
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(styleTrackpadItem)
        menu.addItem(styleMouseItem)
        menu.addItem(.separator())
        oneItem.image = symbol("hand.point.up.left")
        twoItem.image = symbol("hand.point.up.left.and.text") ?? symbol("hand.raised")
        threeItem.image = symbol("hand.raised")
        dragItem.image = symbol("arrow.up.and.down.and.arrow.left.and.right")
        missionItem.image = symbol("rectangle.3.group")
        [oneItem, twoItem, threeItem, dragItem, leftSideItem, rightSideItem, tapDragItem, missionItem].forEach(menu.addItem)
        leftSideItem.image = symbol("hand.point.up.left")
        rightSideItem.image = symbol("hand.point.up.left.and.text") ?? symbol("hand.raised")
        tapDragItem.image = symbol("arrow.up.and.down.and.arrow.left.and.right")
        menu.addItem(.separator())
        menu.addItem(loginItem)
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let aboutItem = NSMenuItem(title: "About LazyClick", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit LazyClick", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        refreshStatusIcon()
    }

    private func symbol(_ name: String, description: String? = nil) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)
    }

    private func refreshStatusIcon() {
        guard let button = statusItem?.button else { return }
        let name = symbol("magicmouse") != nil ? "magicmouse" : "computermouse"
        let img = symbol(name, description: "LazyClick")
        img?.isTemplate = true
        button.image = img
        button.appearsDisabled = !isActive // dim when not handling gestures
        button.toolTip = statusText
    }

    private var isActive: Bool {
        controller.isEnabled && Permission.isTrusted && !abiFault
    }

    private var statusText: String {
        if abiFault { return "Touch API returned unexpected data — gestures stopped" }
        if case let .unavailable(why) = adapter.availability { return "Touch API unavailable: \(why)" }
        if !Permission.isTrusted { return "Accessibility permission needed" }
        if !Preferences.bool(Preferences.Key.enabled) { return "Disabled" }
        return deviceCount > 0 ? "Magic Mouse connected" : "Magic Mouse disconnected"
    }

    func menuWillOpen(_ menu: NSMenu) {
        let on = Preferences.bool(Preferences.Key.enabled)
        enabledItem.state = on ? .on : .off
        enabledItem.isEnabled = true

        let connected = deviceCount > 0 && on && Permission.isTrusted
        var title = connected ? "Magic Mouse: Connected" : "Magic Mouse: Disconnected"
        var icon = connected ? "checkmark.circle.fill" : "xmark.circle"
        if case .unavailable = adapter.availability { title = "Touch API unavailable"; icon = "exclamationmark.triangle" }
        if abiFault { title = "Touch data unexpected — stopped"; icon = "exclamationmark.triangle" }
        deviceItem.title = title
        deviceItem.image = symbol(icon)

        permissionItem.isHidden = Permission.isTrusted
        for (item, key) in [(oneItem, Preferences.Key.oneFinger), (twoItem, Preferences.Key.twoFinger),
                            (threeItem, Preferences.Key.threeFinger), (dragItem, Preferences.Key.threeFingerDrag),
                            (missionItem, Preferences.Key.fourFingerSwipeUp), (leftSideItem, Preferences.Key.leftSideTap),
                            (rightSideItem, Preferences.Key.rightSideTap), (tapDragItem, Preferences.Key.tapDrag)] {
            item.state = Preferences.bool(key) ? .on : .off
            item.isEnabled = on
        }
        let mouse = Preferences.style == .mouse
        styleTrackpadItem.state = mouse ? .off : .on
        styleMouseItem.state = mouse ? .on : .off
        [oneItem, twoItem, threeItem, dragItem].forEach { $0.isHidden = mouse }
        [leftSideItem, rightSideItem, tapDragItem].forEach { $0.isHidden = !mouse }
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        Preferences.set(!Preferences.bool(Preferences.Key.enabled), for: Preferences.Key.enabled)
        if Preferences.bool(Preferences.Key.enabled) && !Permission.isTrusted { showPermissionAlert() }
        abiFault = false
        applyState()
    }

    @objc private func toggleGesture(_ sender: NSMenuItem) {
        let key: String
        switch sender.tag {
        case 1: key = Preferences.Key.oneFinger
        case 2: key = Preferences.Key.twoFinger
        case 3: key = Preferences.Key.threeFinger
        case 5: key = Preferences.Key.fourFingerSwipeUp
        case 6: key = Preferences.Key.leftSideTap
        case 7: key = Preferences.Key.rightSideTap
        case 8: key = Preferences.Key.tapDrag
        default: key = Preferences.Key.threeFingerDrag
        }
        Preferences.set(!Preferences.bool(key), for: key)
        controller.updateConfig(Preferences.gestureConfig())
        settings?.reload()
    }

    @objc private func selectStyle(_ sender: NSMenuItem) {
        Preferences.style = GestureStyle(rawValue: sender.tag) ?? .trackpad
        controller.updateConfig(Preferences.gestureConfig())
        settings?.reload()
    }

    @objc private func toggleLaunchAtLogin() {
        let target = !LaunchAtLogin.isEnabled
        if let err = LaunchAtLogin.set(target) {
            let a = NSAlert()
            a.messageText = "Could not change Launch at Login"
            a.informativeText = err.localizedDescription + "\n\nTip: move LazyClick.app to /Applications and try again."
            a.runModal()
        } else if LaunchAtLogin.needsApproval {
            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc private func grantPermission() { showPermissionAlert() }

    @objc private func openSettings() {
        if settings == nil {
            settings = SettingsWindowController(onChange: { [weak self] in
                self?.controller.updateConfig(Preferences.gestureConfig())
            }, onClose: { [weak self] in
                self?.settings = nil // free the window when closed
            })
        }
        settings?.present()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Touch taps, three-finger drag and four-finger Mission Control for Apple Magic Mouse.\nUses the private MultitouchSupport framework; no network access.")
        ])
    }

    @objc private func quit() { NSApp.terminate(nil) }

    private func showPermissionAlert() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Accessibility access is required"
        a.informativeText = """
        LazyClick needs Accessibility access to send click and drag events.

        1. Click “Open System Settings”.
        2. Switch on “LazyClick” under Privacy & Security → Accessibility.

        Nothing is changed automatically. Gestures start as soon as access is granted.
        """
        a.addButton(withTitle: "Open System Settings")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn {
            Permission.request()
            Permission.openSettings()
        }
    }

    // MARK: - System events (all event driven)

    private func installSystemObservers() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.controller.systemWillSleep()
            self?.adapter.pauseDevices()
        }
        ws.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.adapter.scheduleRefresh(after: 1.0)
        }
        // Fires when any app's Accessibility trust changes; avoids polling AXIsProcessTrusted.
        permissionObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.applyState() }
        }
    }

    /// SIGTERM/SIGINT/SIGHUP: release the button and unregister before exiting.
    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                self?.teardown()
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }
}
