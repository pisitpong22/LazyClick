import AppKit
import MagicMouseTapCore

/// Simple on-demand settings panel. Created when opened, released when closed.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let onChange: () -> Void
    private let onClose: () -> Void

    private var checks: [String: NSButton] = [:]
    private var trackpadViews: [NSView] = []
    private var mouseViews: [NSView] = []
    private let stylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let styleHint = NSTextField(wrappingLabelWithString: "")
    private let sensitivity = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let dragDistance = NSSlider(value: 6, minValue: 2, maxValue: 30, target: nil, action: nil)
    private let dragLockTimeout = NSSlider(value: 1, minValue: 0.3, maxValue: 3, target: nil, action: nil)
    private let sensitivityLabel = NSTextField(labelWithString: "")
    private let dragDistanceLabel = NSTextField(labelWithString: "")
    private let dragLockLabel = NSTextField(labelWithString: "")

    init(onChange: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onChange = onChange
        self.onClose = onClose
        super.init()
    }

    func present() {
        if window == nil { window = makeWindow() }
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func reload() {
        for (key, b) in checks { b.state = Preferences.bool(key) ? .on : .off }
        sensitivity.doubleValue = Preferences.double(Preferences.Key.sensitivity)
        dragDistance.doubleValue = Preferences.double(Preferences.Key.dragDistance)
        dragLockTimeout.doubleValue = Preferences.double(Preferences.Key.dragLockTimeout)
        dragLockTimeout.isEnabled = Preferences.bool(Preferences.Key.dragLock)
        stylePopup.selectItem(at: Preferences.style.rawValue)
        applyStyleVisibility()
        updateLabels()
    }

    private func applyStyleVisibility() {
        let mouse = Preferences.style == .mouse
        trackpadViews.forEach { $0.isHidden = mouse }
        mouseViews.forEach { $0.isHidden = !mouse }
        styleHint.stringValue = mouse
            ? "Tap the left half = left click, right half = right click. Tap, then touch again and move the mouse while holding = drag (no three fingers)."
            : "1 / 2 / 3-finger tap = left / right / middle click. Three fingers + move = drag."
        if let w = window, let content = w.contentView { w.setContentSize(content.fittingSize) }
    }

    private func updateLabels() {
        let s = sensitivity.doubleValue
        sensitivityLabel.stringValue = s < 0.34 ? "Strict" : (s > 0.66 ? "Relaxed" : "Normal")
        dragDistanceLabel.stringValue = String(format: "%.0f pt", dragDistance.doubleValue)
        dragLockLabel.stringValue = String(format: "%.1f s", dragLockTimeout.doubleValue)
    }

    // MARK: - UI

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 100),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Magic Mouse Tap Settings"
        w.isReleasedWhenClosed = false
        w.delegate = self

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)

        stack.addArrangedSubview(header("Gesture style"))
        stylePopup.addItems(withTitles: ["Trackpad style", "Mouse style"])
        stylePopup.target = self
        stylePopup.action = #selector(styleChanged)
        stack.addArrangedSubview(stylePopup)
        styleHint.preferredMaxLayoutWidth = 380
        styleHint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(styleHint)
        stack.addArrangedSubview(spacer())

        stack.addArrangedSubview(header("Gestures"))
        for (title, key) in [("One-finger tap → Left Click", Preferences.Key.oneFinger),
                             ("Two-finger tap → Right Click", Preferences.Key.twoFinger),
                             ("Three-finger tap → Middle Click", Preferences.Key.threeFinger),
                             ("Three-finger drag", Preferences.Key.threeFingerDrag)] {
            let b = check(title, key)
            trackpadViews.append(b)
            stack.addArrangedSubview(b)
        }
        for (title, key) in [("Tap left side → Left Click (quick double tap = double-click)", Preferences.Key.leftSideTap),
                             ("Tap right side → Right Click", Preferences.Key.rightSideTap),
                             ("Tap, then touch and move the mouse → Drag", Preferences.Key.tapDrag),
                             ("Swap left and right sides", Preferences.Key.swapSides)] {
            let b = check(title, key)
            mouseViews.append(b)
            stack.addArrangedSubview(b)
        }
        stack.addArrangedSubview(check("Four fingers + move up → Mission Control", Preferences.Key.fourFingerSwipeUp))

        stack.addArrangedSubview(spacer())
        stack.addArrangedSubview(header("Advanced"))
        stack.addArrangedSubview(row("Tap sensitivity", sensitivity, sensitivityLabel, #selector(sensitivityChanged)))
        stack.addArrangedSubview(row("Drag activation", dragDistance, dragDistanceLabel, #selector(dragDistanceChanged)))
        stack.addArrangedSubview(check("Drag lock (keep dragging briefly after lifting fingers)", Preferences.Key.dragLock))
        stack.addArrangedSubview(row("Drag lock timeout", dragLockTimeout, dragLockLabel, #selector(dragLockTimeoutChanged)))

        let reset = NSButton(title: "Reset Advanced to Defaults", target: self, action: #selector(resetAdvanced))
        stack.addArrangedSubview(spacer())
        stack.addArrangedSubview(reset)

        w.contentView = stack
        w.setContentSize(stack.fittingSize)
        w.center()
        return w
    }

    private func header(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return l
    }

    private func spacer() -> NSView {
        let v = NSView()
        v.heightAnchor.constraint(equalToConstant: 6).isActive = true
        return v
    }

    private func check(_ title: String, _ key: String) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkChanged(_:)))
        b.identifier = NSUserInterfaceItemIdentifier(key)
        checks[key] = b
        return b
    }

    private func row(_ title: String, _ slider: NSSlider, _ value: NSTextField, _ action: Selector) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.widthAnchor.constraint(equalToConstant: 120).isActive = true
        slider.target = self
        slider.action = action
        slider.isContinuous = false // one write per adjustment, not a stream
        slider.widthAnchor.constraint(equalToConstant: 180).isActive = true
        value.widthAnchor.constraint(equalToConstant: 60).isActive = true
        let r = NSStackView(views: [label, slider, value])
        r.orientation = .horizontal
        r.spacing = 8
        return r
    }

    // MARK: - Actions

    @objc private func styleChanged() {
        Preferences.style = GestureStyle(rawValue: stylePopup.indexOfSelectedItem) ?? .trackpad
        applyStyleVisibility()
        onChange()
    }

    @objc private func checkChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        Preferences.set(sender.state == .on, for: key)
        if key == Preferences.Key.dragLock { dragLockTimeout.isEnabled = sender.state == .on }
        onChange()
    }

    @objc private func sensitivityChanged() {
        Preferences.set(sensitivity.doubleValue, for: Preferences.Key.sensitivity)
        updateLabels(); onChange()
    }

    @objc private func dragDistanceChanged() {
        Preferences.set(dragDistance.doubleValue, for: Preferences.Key.dragDistance)
        updateLabels(); onChange()
    }

    @objc private func dragLockTimeoutChanged() {
        Preferences.set(dragLockTimeout.doubleValue, for: Preferences.Key.dragLockTimeout)
        updateLabels(); onChange()
    }

    @objc private func resetAdvanced() {
        Preferences.resetAdvanced()
        Preferences.registerDefaults()
        reload()
        onChange()
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        trackpadViews.removeAll(); mouseViews.removeAll(); checks.removeAll()
        onClose()
    }
}
