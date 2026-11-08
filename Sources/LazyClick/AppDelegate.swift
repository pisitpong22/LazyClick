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
    private var batteryPercent: Int?
    private var batteryTimer: Timer?
    private var abiFault = false

    // Menu items updated in menuWillOpen
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
    private let deviceItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(grantPermission), keyEquivalent: "")
    private let styleTrackpadItem = NSMenuItem(title: "Trackpad style", action: #selector(selectStyle(_:)), keyEquivalent: "")
    private let styleMouseItem = NSMenuItem(title: "Mouse style", action: #selector(selectStyle(_:)), keyEquivalent: "")
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
        controller.onClick = { DispatchQueue.main.async { ClickSound.play() } }

        MultitouchAdapter.frameHandler = { [controller] base, count, ts in
            controller.handleRawFrame(base, count: count, timestamp: ts)
        }
        adapter.onDevicesStopping = { [controller] in controller.deviceDisconnected() }
        adapter.onDeviceCountChanged = { [weak self] n in
            guard let self else { return }
            if n == 0 { self.controller.deviceDisconnected() }
            self.deviceCount = n
            self.refreshBattery()
            self.refreshStatusIcon()
        }

        buildStatusItem()
        refreshBattery()
        // The battery level changes slowly; one cheap check every 5 minutes is plenty.
        let t = Timer(timeInterval: 300, repeats: true) { [weak self] _ in self?.refreshBattery() }
        t.tolerance = 60
        RunLoop.main.add(t, forMode: .common)
        batteryTimer = t
        installSystemObservers()
        installSignalHandlers()

        if !Permission.isTrusted && !Preferences.bool(Preferences.Key.didPromptAccessibility) {
            Preferences.set(true, for: Preferences.Key.didPromptAccessibility)
            Permission.request()
            openSettings() // first launch: show something so the user knows the app is running
        }
        applyState()
    }

    /// Opening the app again (Finder/Launchpad) shows Settings, so a menu bar icon hidden by a crowded bar or the notch is never a dead end.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
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
        settings?.reload() // updates the permission banner
        refreshStatusIcon()
    }

    // MARK: - Status item & menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false

        for item in [enabledItem, permissionItem, loginItem, styleTrackpadItem, styleMouseItem] { item.target = self }
        styleTrackpadItem.tag = 0; styleMouseItem.tag = 1
        enabledItem.image = symbol("power")
        deviceItem.isEnabled = false
        permissionItem.image = symbol("lock.shield")
        styleTrackpadItem.image = symbol("hand.point.up.left")
        styleMouseItem.image = symbol("computermouse")

        menu.addItem(enabledItem)
        menu.addItem(deviceItem)
        menu.addItem(permissionItem)
        menu.addItem(.separator())
        menu.addItem(styleTrackpadItem)
        menu.addItem(styleMouseItem)
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(loginItem)
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
        button.toolTip = statusText + (batteryPercent.map { " · Battery \($0)%" } ?? "")
    }

    private func refreshBattery() {
        MouseBattery.read { [weak self] pct in
            guard let self, pct != self.batteryPercent else { return }
            self.batteryPercent = pct
            self.refreshStatusIcon()
        }
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
        if connected, let pct = batteryPercent { title += " · \(pct)%" }
        var icon = connected ? "checkmark.circle.fill" : "xmark.circle"
        if !Permission.isTrusted && on { title = "Needs Accessibility permission"; icon = "lock.shield" }
        if case .unavailable = adapter.availability { title = "Touch API unavailable"; icon = "exclamationmark.triangle" }
        if abiFault { title = "Touch data unexpected — stopped"; icon = "exclamationmark.triangle" }
        deviceItem.title = title
        deviceItem.image = symbol(icon)
        refreshBattery()

        permissionItem.isHidden = Permission.isTrusted
        let mouse = Preferences.style == .mouse
        styleTrackpadItem.state = mouse ? .off : .on
        styleMouseItem.state = mouse ? .on : .off
        styleTrackpadItem.isEnabled = on
        styleMouseItem.isEnabled = on
        loginItem.state = LaunchAtLogin.isEnabled ? .on : .off
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        Preferences.set(!Preferences.bool(Preferences.Key.enabled), for: Preferences.Key.enabled)
        if Preferences.bool(Preferences.Key.enabled) && !Permission.isTrusted { showPermissionAlert() }
        abiFault = false
        applyState()
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

    @objc private func quit() { NSApp.terminate(nil) }

    private func showPermissionAlert() {
        Permission.request() // the system prompt already offers "Open System Settings"; a second dialog is redundant
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
