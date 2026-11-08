import AppKit
import LazyClickCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, StatusPanelActions {
    private let adapter = MultitouchAdapter()
    private let controller: GestureController
    private var statusItem: NSStatusItem!
    private var settings: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var permissionObserver: NSObjectProtocol?
    private var signalSources: [DispatchSourceSignal] = []

    private var deviceCount = 0
    private var batteryPercent: Int?
    private var batteryTimer: Timer?
    private var abiFault = false

    private let popover = NSPopover()
    private lazy var panel = StatusPanelController(actions: self)
    private var lastPanelClose = Date.distantPast

    override init() {
        controller = GestureController(
            poster: CGEventPoster(),
            timer: OneShotTimer(),
            config: GestureConfig(),
            cursorProvider: CursorState.location,
            physicalButtonProvider: CursorState.physicalButtonDown,
            regionSelectingProvider: CursorState.regionSelecting
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
            openOnboarding()
        }
        applyState()
    }

    /// Opening the app again (Finder/Launchpad) shows Settings, so a menu bar icon hidden by a crowded bar or the notch is never a dead end.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let onboarding { onboarding.present() } else { openSettings() }
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
        onboarding?.reload()
        refreshStatusIcon()
    }

    // MARK: - Status item & panel

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        popover.behavior = .transient
        popover.contentViewController = panel
        popover.delegate = self
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePanel)
        statusItem.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        refreshStatusIcon()
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        if popover.isShown { popover.performClose(sender); return }
        // A click on the icon can dismiss the transient popover first; don't let the same click reopen it.
        guard Date().timeIntervalSince(lastPanelClose) > 0.2 else { return }
        reloadPanel()
        refreshBattery()
        NSApp.activate(ignoringOtherApps: true) // Without this, ⌘Q and click-away dismissal don't work.
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    func popoverWillClose(_ notification: Notification) { lastPanelClose = Date() }

    func popoverDidClose(_ notification: Notification) {
        if settings == nil && onboarding == nil && NSApp.modalWindow == nil { NSApp.hide(nil) } // hand focus back to the app the user was in
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
        if popover.isShown { reloadPanel() }
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

    private func reloadPanel() {
        let on = Preferences.bool(Preferences.Key.enabled)
        let connected = deviceCount > 0 && on && Permission.isTrusted
        var detail = on ? "Magic Mouse \(connected ? "Connected" : "Disconnected")" : "Gestures are off"
        if connected, let pct = batteryPercent { detail += " · \(pct)%" }
        var icon = connected ? "checkmark.circle.fill" : "xmark.circle.fill"
        var tint: NSColor = connected ? .systemGreen : .systemGray
        if !Permission.isTrusted && on { detail = "Needs Accessibility permission"; icon = "lock.shield.fill"; tint = .systemOrange }
        if case .unavailable = adapter.availability { detail = "Touch API unavailable"; icon = "exclamationmark.triangle.fill"; tint = .systemOrange }
        if abiFault { detail = "Touch data unexpected — stopped"; icon = "exclamationmark.triangle.fill"; tint = .systemOrange }
        panel.update(.init(
            enabled: on, detail: detail, icon: icon, tint: tint,
            needsPermission: !Permission.isTrusted,
            isMouseStyle: Preferences.style == .mouse,
            clickSound: ClickSound.isOn,
            launchAtLogin: LaunchAtLogin.isEnabled
        ))
    }

    // MARK: - Actions

    func toggleEnabled() {
        Preferences.set(!Preferences.bool(Preferences.Key.enabled), for: Preferences.Key.enabled)
        if Preferences.bool(Preferences.Key.enabled) && !Permission.isTrusted { showPermissionAlert() }
        abiFault = false
        applyState()
    }

    func selectStyle(_ sender: NSSegmentedControl) {
        Preferences.style = GestureStyle(rawValue: sender.selectedSegment) ?? .trackpad
        controller.updateConfig(Preferences.gestureConfig())
        settings?.reload()
    }

    func toggleClickSound() {
        ClickSound.toggle()
        settings?.reload()
    }

    func toggleLaunchAtLogin() {
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
        reloadPanel() // a failed change must snap the switch back
    }

    func grantPermission() { showPermissionAlert() }

    func openSettings() {
        popover.performClose(nil)
        if settings == nil {
            settings = SettingsWindowController(onChange: { [weak self] in
                self?.controller.updateConfig(Preferences.gestureConfig())
            }, onClose: { [weak self] in
                self?.settings = nil // free the window when closed
            })
        }
        settings?.present()
    }

    /// Ends on Settings, so a user who skips the permission still sees the banner explaining it.
    private func openOnboarding() {
        onboarding = OnboardingWindowController(onClose: { [weak self] in
            self?.onboarding = nil
            self?.openSettings()
        })
        onboarding?.present()
    }

    func quit() { NSApp.terminate(nil) }

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
