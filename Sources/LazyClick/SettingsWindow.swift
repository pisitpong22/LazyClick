import AppKit
import LazyClickCore

/// Settings panel. Built when opened, released when closed.
/// On macOS 26+ the cards are Liquid Glass (`NSGlassEffectView`); older systems get a blurred rounded card.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private static let leftWidth: CGFloat = 440
    private static let rightWidth: CGFloat = 424
    private static let gap: CGFloat = 18
    private static let margin: CGFloat = 22
    private static var contentWidth: CGFloat { margin * 2 + leftWidth + gap + rightWidth }

    private var window: NSWindow?
    private var rootStack: NSStackView?
    private let onChange: () -> Void
    private let onClose: () -> Void

    private var switches: [String: NSSwitch] = [:]
    private var trackpadOnly: [NSView] = []   // visible in Trackpad style only
    private var multiFinger: [NSView] = []     // Trackpad and Both
    private let demo = GestureDemoView(frame: NSRect(origin: .zero, size: GestureDemoView.size))
    private let captionTitle = NSTextField(labelWithString: "")
    private let captionDetail = NSTextField(wrappingLabelWithString: "")
    private var demoForKey: [String: DemoKind] = [:]
    private var mouseOnly: [NSView] = []       // Mouse and Both

    private let styleControl = NSSegmentedControl(labels: ["Trackpad", "Mouse", "Both"], trackingMode: .selectOne, target: nil, action: nil)
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
        reload(animated: false)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func reload() { reload(animated: window?.isVisible ?? false) }

    private func reload(animated: Bool) {
        for (key, s) in switches { s.state = Preferences.bool(key) ? .on : .off }
        sensitivity.doubleValue = Preferences.double(Preferences.Key.sensitivity)
        dragDistance.doubleValue = Preferences.double(Preferences.Key.dragDistance)
        dragLockTimeout.doubleValue = Preferences.double(Preferences.Key.dragLockTimeout)
        dragLockTimeout.isEnabled = Preferences.bool(Preferences.Key.dragLock)
        styleControl.selectedSegment = Preferences.style.rawValue
        applyStyleVisibility(animated: animated)
        updateLabels()
    }

    private func updateLabels() {
        let s = sensitivity.doubleValue
        sensitivityLabel.stringValue = s < 0.34 ? "Strict" : (s > 0.66 ? "Relaxed" : "Normal")
        dragDistanceLabel.stringValue = String(format: "%.0f pt", dragDistance.doubleValue)
        dragLockLabel.stringValue = String(format: "%.1f s", dragLockTimeout.doubleValue)
    }

    private func applyStyleVisibility(animated: Bool) {
        let style = Preferences.style
        trackpadOnly.forEach { $0.isHidden = style != .trackpad }
        multiFinger.forEach { $0.isHidden = style == .mouse }
        mouseOnly.forEach { $0.isHidden = style == .trackpad }
        switch style {
        case .trackpad:
            styleHint.stringValue = "Tap with one, two or three fingers to click. Put three fingers down and move the mouse to drag."
        case .mouse:
            styleHint.stringValue = "Tap the left or right half of the mouse to click. Tap, then touch again and move the mouse to drag."
        case .both:
            styleHint.stringValue = "Everything at once. One-finger taps follow the mouse rule (left half = left click, right half = right click); two- and three-finger taps and three-finger drag still work."
        }
        let allowed = DemoKind.kinds(for: style)
        if let k = demo.kind, allowed.contains(k) { select(k) } else { select(allowed[0]) }
        resizeToFit(animated: animated)
    }

    /// Used by `--show-settings --demo <kind>` to preview one animation.
    func previewDemo(_ kind: DemoKind) { select(kind) }

    private func select(_ kind: DemoKind) {
        if demo.kind != kind { demo.show(kind) }
        captionTitle.stringValue = kind.caption.title
        captionDetail.stringValue = kind.caption.detail
    }

    private func resizeToFit(animated: Bool) {
        guard let w = window, let stack = rootStack else { return }
        stack.layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height + 40 + 22 // top inset + bottom padding
        let frame = w.frameRect(forContentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: height))
        var f = w.frame
        f.origin.y += f.height - frame.height // keep the top edge fixed
        f.size = frame.size
        w.setFrame(f, display: true, animate: animated)
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 600),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Settings"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.delegate = self

        let backdrop = NSVisualEffectView()
        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        w.contentView = backdrop

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .top
        stack.spacing = Self.gap
        stack.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 40),
            stack.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: Self.margin),
        ])
        rootStack = stack

        let left = NSStackView()
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 14
        let right = NSStackView()
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 14
        stack.addArrangedSubview(left)
        stack.addArrangedSubview(right)

        let lw = Self.leftWidth, rw = Self.rightWidth

        // ---- Left column: header, style, gestures
        left.addArrangedSubview(makeHeader())

        styleControl.target = self
        styleControl.action = #selector(styleChanged)
        styleControl.controlSize = .large
        styleControl.segmentDistribution = .fillEqually
        if let img = symbol("hand.point.up.left") { styleControl.setImage(img, forSegment: 0) }
        if let img = symbol("computermouse") { styleControl.setImage(img, forSegment: 1) }
        if let img = symbol("square.on.square") { styleControl.setImage(img, forSegment: 2) }
        styleHint.font = .systemFont(ofSize: 11)
        styleHint.textColor = .secondaryLabelColor
        styleHint.preferredMaxLayoutWidth = lw - 4
        left.addArrangedSubview(styleControl)
        left.addArrangedSubview(styleHint)
        styleControl.widthAnchor.constraint(equalToConstant: lw).isActive = true
        styleHint.widthAnchor.constraint(equalToConstant: lw - 4).isActive = true

        let trackpadRows = [
            toggleRow("One-finger tap", "Left click", Preferences.Key.oneFinger, demo: .oneTap),
            toggleRow("Two-finger tap", "Right click", Preferences.Key.twoFinger, demo: .twoTap),
            toggleRow("Three-finger tap", "Middle click", Preferences.Key.threeFinger, demo: .threeTap),
            toggleRow("Three-finger drag", "Three fingers down, then move the mouse", Preferences.Key.threeFingerDrag, demo: .threeDrag),
        ]
        let mouseRows = [
            toggleRow("Tap the left side", "Left click · two quick taps = double-click", Preferences.Key.leftSideTap, demo: .sideLeft),
            toggleRow("Tap the right side", "Right click", Preferences.Key.rightSideTap, demo: .sideRight),
            toggleRow("Tap, touch again and move", "Drag — lift your finger to drop", Preferences.Key.tapDrag, demo: .tapDrag),
            toggleRow("Swap left and right", "For left-handed use or a mirrored sensor", Preferences.Key.swapSides, demo: .swapSides),
        ]
        trackpadOnly = [trackpadRows[0]]
        multiFinger = Array(trackpadRows.dropFirst())
        mouseOnly = mouseRows
        left.addArrangedSubview(section("GESTURES", rows: trackpadRows + mouseRows, width: lw))

        // ---- Right column: live preview, fine-tuning
        captionTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        captionTitle.alignment = .center
        captionDetail.font = .systemFont(ofSize: 11)
        captionDetail.textColor = .secondaryLabelColor
        captionDetail.alignment = .center
        captionDetail.preferredMaxLayoutWidth = rw - 40
        let captions = NSStackView(views: [captionTitle, captionDetail])
        captions.orientation = .vertical
        captions.alignment = .centerX
        captions.spacing = 2
        captions.widthAnchor.constraint(equalToConstant: rw - 32).isActive = true
        captionDetail.widthAnchor.constraint(equalToConstant: rw - 40).isActive = true
        right.addArrangedSubview(section("PREVIEW", rows: [demo, captions], width: rw))

        let tuning: [NSView] = [
            sliderRow("Tap sensitivity", sensitivity, sensitivityLabel, #selector(sensitivityChanged)),
            sliderRow("Drag distance", dragDistance, dragDistanceLabel, #selector(dragDistanceChanged)),
            toggleRow("Drag lock", "Keep dragging briefly after lifting your fingers", Preferences.Key.dragLock),
            sliderRow("Drag lock time", dragLockTimeout, dragLockLabel, #selector(dragLockTimeoutChanged)),
        ]
        right.addArrangedSubview(section("FINE-TUNING", rows: tuning, width: rw))

        let reset = NSButton(title: "Reset Fine-Tuning", target: self, action: #selector(resetAdvanced))
        if #available(macOS 26.0, *) { reset.bezelStyle = .glass } else { reset.bezelStyle = .rounded }
        reset.controlSize = .large
        let footer = NSStackView(views: [NSView(), reset])
        footer.orientation = .horizontal
        footer.widthAnchor.constraint(equalToConstant: rw).isActive = true
        right.addArrangedSubview(footer)

        w.center()
        return w
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func makeHeader() -> NSView {
        let icon = NSImageView()
        let cfg = NSImage.SymbolConfiguration(pointSize: 30, weight: .regular)
        icon.image = (symbol("magicmouse") ?? symbol("computermouse"))?.withSymbolConfiguration(cfg)
        icon.contentTintColor = .controlAccentColor
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let name = (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? "LazyClick"
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        let title = NSTextField(labelWithString: name)
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let sub = NSTextField(labelWithString: version.isEmpty ? "Touch gestures for Apple Magic Mouse" : "Version \(version) · Touch gestures for Apple Magic Mouse")
        sub.font = .systemFont(ofSize: 11)
        sub.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [title, sub])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        let row = NSStackView(views: [icon, labels])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    // MARK: - Building blocks

    private func section(_ title: String, rows: [NSView], width: CGFloat) -> NSView {
        let header = NSTextField(labelWithString: title)
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = .secondaryLabelColor

        let rowsStack = NSStackView(views: rows)
        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.spacing = 12
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        let holder = NSView()
        holder.translatesAutoresizingMaskIntoConstraints = false
        holder.addSubview(rowsStack)
        NSLayoutConstraint.activate([
            rowsStack.topAnchor.constraint(equalTo: holder.topAnchor, constant: 14),
            rowsStack.bottomAnchor.constraint(equalTo: holder.bottomAnchor, constant: -14),
            rowsStack.leadingAnchor.constraint(equalTo: holder.leadingAnchor, constant: 16),
            rowsStack.trailingAnchor.constraint(equalTo: holder.trailingAnchor, constant: -16),
        ])

        let card: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 20
            glass.contentView = holder
            card = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .popover
            blur.blendingMode = .withinWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 14
            blur.layer?.masksToBounds = true
            blur.addSubview(holder)
            NSLayoutConstraint.activate([
                holder.topAnchor.constraint(equalTo: blur.topAnchor),
                holder.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
                holder.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
                holder.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            ])
            card = blur
        }
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: width).isActive = true

        let s = NSStackView(views: [header, card])
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 6
        return s
    }

    private func toggleRow(_ title: String, _ detail: String, _ key: String, demo kind: DemoKind? = nil) -> NSView {
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 13, weight: .medium)
        let d = NSTextField(labelWithString: detail)
        d.font = .systemFont(ofSize: 11)
        d.textColor = .secondaryLabelColor
        d.lineBreakMode = .byTruncatingTail
        let labels = NSStackView(views: [t, d])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        let sw = NSSwitch()
        sw.target = self
        sw.action = #selector(switchChanged(_:))
        sw.identifier = NSUserInterfaceItemIdentifier(key)
        switches[key] = sw

        labels.setContentHuggingPriority(.required, for: .horizontal)
        sw.setContentHuggingPriority(.required, for: .horizontal)
        let flex = NSView()
        flex.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        flex.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let row = HoverRow(views: [labels, flex, sw])
        if let kind {
            demoForKey[key] = kind
            row.onHover = { [weak self] in
                if ProcessInfo.processInfo.environment["LAZYCLICK_DEMO_FREEZE"] == nil { self?.select(kind) }
            }
        }
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    private func sliderRow(_ title: String, _ slider: NSSlider, _ value: NSTextField, _ action: Selector) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 112).isActive = true
        slider.target = self
        slider.action = action
        slider.isContinuous = false // one write per adjustment, not a stream
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: 52).isActive = true
        let r = NSStackView(views: [label, slider, value])
        r.orientation = .horizontal
        r.alignment = .centerY
        r.spacing = 10
        return r
    }

    // MARK: - Actions

    @objc private func styleChanged() {
        Preferences.style = GestureStyle(rawValue: styleControl.selectedSegment) ?? .trackpad
        applyStyleVisibility(animated: true)
        onChange()
    }

    @objc private func switchChanged(_ sender: NSSwitch) {
        guard let key = sender.identifier?.rawValue else { return }
        Preferences.set(sender.state == .on, for: key)
        if let k = demoForKey[key] { select(k) }
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
        reload(animated: false)
        onChange()
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        rootStack = nil
        switches.removeAll(); trackpadOnly.removeAll(); multiFinger.removeAll(); mouseOnly.removeAll(); demoForKey.removeAll()
        onClose()
    }
}

/// A settings row that reports when the pointer is over it, so the preview can follow.
final class HoverRow: NSStackView {
    var onHover: (() -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
}
