import AppKit
import LazyClickCore
import Sparkle

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, SPUStandardUserDriverDelegate {
    private let adapter = MultitouchAdapter()
    private let controller: GestureController
    private var statusItem: NSStatusItem!
    private var settings: SettingsWindowController?
    private var onboarding: OnboardingWindowController?
    private var install: InstallWindowController?
    private var permissionObserver: NSObjectProtocol?
    private var signalSources: [DispatchSourceSignal] = []
    // A bare `swift run` binary has no Info.plist feed or key, so only a real .app checks for updates.
    private lazy var updater = SPUStandardUpdaterController(startingUpdater: Bundle.main.bundlePath.hasSuffix(".app"), updaterDelegate: nil, userDriverDelegate: self)
    /// Set while Sparkle holds a found update we chose not to pop up; the icon turns blue instead.
    private var availableUpdate: String?

    private var deviceCount = 0
    private var batteryPercent: Int?
    private var batteryTimer: Timer?
    private var abiFault = false

    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledItem = NSMenuItem(title: "Enabled", action: #selector(AppDelegate.toggleEnabled), keyEquivalent: "")
    private let trackpadItem = NSMenuItem(title: "Trackpad Style", action: #selector(AppDelegate.selectStyle(_:)), keyEquivalent: "")
    private let mouseItem = NSMenuItem(title: "Mouse Style", action: #selector(AppDelegate.selectStyle(_:)), keyEquivalent: "")
    private let soundItem = NSMenuItem(title: "Click Sound", action: #selector(AppDelegate.toggleClickSound), keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(AppDelegate.grantPermission), keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
    private let milestoneItem = NSMenuItem(title: "🎉 \(SupportWindowController.milestone.formatted()) clicks with LazyClick!", action: #selector(AppDelegate.openSupport), keyEquivalent: "")

    override init() {
        controller = GestureController(
            poster: CGEventPoster(),
            timer: OneShotTimer(),
            config: GestureConfig(),
            cursorProvider: CursorState.location,
            physicalButtonProvider: CursorState.physicalButtonDown,
            regionSelectingProvider: CursorState.regionSelecting,
            screenshotThumbnailProvider: CursorState.overScreenshotThumbnail
        )
        super.init()
    }

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A copy opened from Downloads offers to install itself first; the copy in Applications then does the rest.
        guard !InstallWindowController.shouldOffer else {
            install = InstallWindowController(onSkip: { [weak self] in
                self?.install = nil
                self?.start()
            })
            install?.present()
            return
        }
        start()
    }

    private func start() {
        Preferences.registerDefaults()
        controller.updateConfig(Preferences.gestureConfig())
        controller.onABIFault = { [weak self] in
            DispatchQueue.main.async {
                self?.abiFault = true
                self?.refreshStatusIcon()
            }
        }
        controller.onClick = { [weak self] in
            DispatchQueue.main.async {
                ClickSound.play()
                self?.countClick()
            }
        }

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

        buildMainMenu()
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
        if let install { install.present() } else if let onboarding { onboarding.present() } else { openSettings() }
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

    // MARK: - Menus

    /// Never visible in an accessory app, but its key equivalents are what make ⌘, ⌘Q and ⌘W work in our windows.
    private func buildMainMenu() {
        let app = NSMenu()
        app.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit LazyClick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let main = NSMenu()
        for submenu in [app, file] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        trackpadItem.tag = GestureStyle.trackpad.rawValue
        mouseItem.tag = GestureStyle.mouse.rawValue
        statusLine.isEnabled = false
        let menu = NSMenu()
        menu.autoenablesItems = false // the status line and style items are enabled by hand
        menu.delegate = self
        updateItem.target = updater
        for item in [statusLine, updateItem, milestoneItem, .separator(), enabledItem, .separator(), trackpadItem, mouseItem, soundItem, .separator(), permissionItem] {
            menu.addItem(item)
        }
        menu.addItem(withTitle: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "").target = updater
        menu.addItem(withTitle: "Send Feedback…", action: #selector(sendFeedback), keyEquivalent: "")
        menu.addItem(withTitle: "Support LazyClick…", action: #selector(openSupport), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Quit LazyClick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        refreshStatusIcon()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshBattery()
        let on = Preferences.bool(Preferences.Key.enabled)
        enabledItem.state = on ? .on : .off
        trackpadItem.state = Preferences.style == .trackpad ? .on : .off
        mouseItem.state = Preferences.style == .mouse ? .on : .off
        trackpadItem.isEnabled = on
        mouseItem.isEnabled = on
        soundItem.state = ClickSound.isOn ? .on : .off
        permissionItem.isHidden = Permission.isTrusted
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
        updateItem.title = "Update Available: \(availableUpdate ?? "")…"
        updateItem.isHidden = availableUpdate == nil
        milestoneItem.isHidden = !milestonePending
        button.contentTintColor = availableUpdate != nil || milestonePending ? .systemBlue : nil // "something to look at"
        let status = statusText + (batteryPercent.map { " · Battery \($0)%" } ?? "")
        statusLine.title = status
        button.setAccessibilityValue(status)
        button.toolTip = status
        if case let .unavailable(why) = adapter.availability { button.toolTip = "\(status) (\(why))" } // the technical reason, for bug reports
    }

    private func refreshBattery() {
        MouseBattery.read { [weak self] pct in
            guard let self, pct != self.batteryPercent else { return }
            self.batteryPercent = pct
            self.refreshStatusIcon()
        }
    }

    private var milestonePending: Bool {
        Preferences.int(Preferences.Key.clickCount) >= SupportWindowController.milestone && !Preferences.bool(Preferences.Key.supportSeen)
    }

    private func countClick() {
        let n = Preferences.int(Preferences.Key.clickCount) + 1
        Preferences.set(n, for: Preferences.Key.clickCount)
        if n == SupportWindowController.milestone { refreshStatusIcon() }
    }

    private var isActive: Bool {
        controller.isEnabled && Permission.isTrusted && !abiFault
    }

    private var statusText: String {
        if abiFault { return "Gestures stopped. Turn LazyClick off and on to retry." }
        if case .unavailable = adapter.availability { return "Gestures aren't available on this version of macOS" }
        if !Permission.isTrusted { return "Accessibility permission needed" }
        if !Preferences.bool(Preferences.Key.enabled) { return "Disabled" }
        return deviceCount > 0 ? "Magic Mouse connected" : "Magic Mouse disconnected"
    }

    // MARK: - Actions

    @objc func toggleEnabled() {
        Preferences.set(!Preferences.bool(Preferences.Key.enabled), for: Preferences.Key.enabled)
        enabledChanged()
    }

    private func enabledChanged() {
        if Preferences.bool(Preferences.Key.enabled) && !Permission.isTrusted { showPermissionAlert() }
        abiFault = false
        applyState()
    }

    @objc func selectStyle(_ sender: NSMenuItem) {
        Preferences.style = GestureStyle(rawValue: sender.tag) ?? .trackpad
        controller.updateConfig(Preferences.gestureConfig())
        settings?.reload()
    }

    @objc func toggleClickSound() {
        ClickSound.toggle()
        settings?.reload()
    }

    private func toggleLaunchAtLogin() {
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

    @objc func grantPermission() { showPermissionAlert() }

    @objc func sendFeedback() { Feedback.send() }

    @objc func openSupport() {
        SupportWindowController.show()
        refreshStatusIcon()
    }

    // MARK: - Sparkle gentle reminders (a background app shouldn't pop an update window on its own)

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !state.userInitiated else { return }
        availableUpdate = update.displayVersionString
        refreshStatusIcon()
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        availableUpdate = nil
        refreshStatusIcon()
    }

    func standardUserDriverWillFinishUpdateSession() {
        availableUpdate = nil
        refreshStatusIcon()
    }

    @objc func openSettings() {
        if settings == nil {
            settings = SettingsWindowController(onChange: { [weak self] in
                self?.controller.updateConfig(Preferences.gestureConfig())
            }, onClose: { [weak self] in
                self?.settings = nil // free the window when closed
            }, onEnabledChange: { [weak self] in
                self?.enabledChanged()
            }, onLaunchAtLogin: { [weak self] in
                self?.toggleLaunchAtLogin()
            })
        }
        settings?.present()
    }

    /// A user who skips the permission ends on Settings, where the banner explains it.
    private func openOnboarding() {
        onboarding = OnboardingWindowController(onClose: { [weak self] in
            self?.onboarding = nil
            if !Permission.isTrusted { self?.openSettings() }
        })
        onboarding?.present()
    }

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
