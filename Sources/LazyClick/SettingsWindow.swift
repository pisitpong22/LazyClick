import AppKit
import LazyClickCore

/// Settings panel. Built when opened, released when closed.
/// On macOS 26+ the cards are Liquid Glass (`NSGlassEffectView`); older systems get a blurred rounded card.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private static let bodyWidth: CGFloat = GestureDemoView.size.width
    private static let margin: CGFloat = 22
    private static var contentWidth: CGFloat { margin * 2 + bodyWidth }

    private var window: NSWindow?
    private var rootStack: NSStackView?
    private let onChange: () -> Void
    private let onClose: () -> Void

    private var switches: [String: NSSwitch] = [:]
    private var trackpadOnly: [NSView] = []
    private let demo = GestureDemoView(frame: NSRect(origin: .zero, size: GestureDemoView.size))
    private let captionTitle = NSTextField(labelWithString: "")
    private let captionDetail = NSTextField(wrappingLabelWithString: "")
    private var demoForKey: [String: DemoKind] = [:]
    private var mouseOnly: [NSView] = []
    private var tabPages: [NSView] = []
    private let tabs = NSSegmentedControl(labels: ["Point & Click", "More Gestures"], trackingMode: .selectOne, target: nil, action: nil)
    private let batteryLabel = NSTextField(labelWithString: "")

    private var styleRadios: [NSButton] = []
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
        refreshBattery()
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
        for r in styleRadios { r.state = (r.tag == Preferences.style.rawValue) ? .on : .off }
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
        let mouse = Preferences.style == .mouse
        trackpadOnly.forEach { $0.isHidden = mouse }
        mouseOnly.forEach { $0.isHidden = !mouse }
        applyTab()
        resizeToFit(animated: animated)
    }

    /// Demos that belong to each tab: clicks on the first, drags on the second.
    private static let dragKinds: [DemoKind] = [.threeDrag, .tapDrag]

    private func applyTab() {
        let tab = tabs.selectedSegment
        for (i, page) in tabPages.enumerated() { page.isHidden = i != tab }
        let mouse = Preferences.style == .mouse
        let allowed = (mouse ? DemoKind.mouse : DemoKind.trackpad).filter { Self.dragKinds.contains($0) == (tab == 1) }
        if let k = demo.kind, allowed.contains(k) { select(k) } else { select(allowed[0]) }
    }

    @objc private func tabChanged() {
        applyTab()
        resizeToFit(animated: true)
    }

    /// Battery of the paired Magic Mouse, read from the IO registry (no Bluetooth permission needed).
    private func refreshBattery() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
            p.arguments = ["-r", "-k", "BatteryPercent", "-l"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            var text = ""
            if (try? p.run()) != nil {
                text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                p.waitUntilExit()
            }
            var percent: Int?
            for block in text.components(separatedBy: "+-o ") where block.contains("\"ProductID\" = 617") || block.contains("\"ProductID\" = 781") {
                if let r = block.range(of: #""BatteryPercent" = (\d+)"#, options: .regularExpression) {
                    percent = Int(block[r].split(separator: "=").last?.trimmingCharacters(in: .whitespaces) ?? "")
                    break
                }
            }
            DispatchQueue.main.async {
                self?.batteryLabel.stringValue = percent.map { "Battery \($0)%" } ?? ""
            }
        }
    }

    /// Used by `--show-settings --tab <0|1>` to open on a given tab.
    func previewTab(_ index: Int) {
        tabs.selectedSegment = index
        tabChanged()
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
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 40),
            stack.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: Self.margin),
        ])
        rootStack = stack

        let bw = Self.bodyWidth

        // ---- Header, then the two preview cards (mouse + desktop), like System Settings > Mouse
        stack.addArrangedSubview(makeHeader())

        captionTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        captionTitle.alignment = .center
        captionDetail.font = .systemFont(ofSize: 11)
        captionDetail.textColor = .secondaryLabelColor
        captionDetail.alignment = .center
        captionDetail.preferredMaxLayoutWidth = bw - 40
        let captions = NSStackView(views: [captionTitle, captionDetail])
        captions.orientation = .vertical
        captions.alignment = .centerX
        captions.spacing = 2
        captions.widthAnchor.constraint(equalToConstant: bw).isActive = true
        captionDetail.widthAnchor.constraint(equalToConstant: bw - 40).isActive = true
        let preview = NSStackView(views: [demo, captions])
        preview.orientation = .vertical
        preview.alignment = .centerX
        preview.spacing = 8
        stack.addArrangedSubview(preview)

        // ---- Tabs
        tabs.segmentStyle = .automatic
        tabs.segmentDistribution = .fillEqually
        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabChanged)
        tabs.controlSize = .large
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.widthAnchor.constraint(equalToConstant: bw).isActive = true
        stack.addArrangedSubview(tabs)

        // ---- Tab 1: Point & Click
        let trackpadClicks = [
            toggleRow("One-finger tap", "Left click", Preferences.Key.oneFinger, demo: .oneTap),
            toggleRow("Two-finger tap", "Right click", Preferences.Key.twoFinger, demo: .twoTap),
            toggleRow("Three-finger tap", "Middle click", Preferences.Key.threeFinger, demo: .threeTap),
        ]
        let mouseClicks = [
            toggleRow("Tap the left side", "Left click · two quick taps = double-click", Preferences.Key.leftSideTap, demo: .sideLeft),
            toggleRow("Tap the right side", "Right click", Preferences.Key.rightSideTap, demo: .sideRight),
            toggleRow("Swap left and right", "For left-handed use or a mirrored sensor", Preferences.Key.swapSides, demo: .swapSides),
        ]
        let trackpadDrag = toggleRow("Three-finger drag", "Three fingers down, then move the mouse", Preferences.Key.threeFingerDrag, demo: .threeDrag)
        let mouseDrag = toggleRow("Tap, touch again and move", "Drag — lift your finger to drop", Preferences.Key.tapDrag, demo: .tapDrag)
        trackpadOnly = trackpadClicks + [trackpadDrag]
        mouseOnly = mouseClicks + [mouseDrag]

        let page1 = NSStackView(views: [
            section("CHOOSE A STYLE", rows: [
                styleOptionRow(.trackpad, symbolName: "hand.point.up.left", title: "Trackpad style",
                               detail: "Tap with 1, 2 or 3 fingers = left, right, middle click. Three-finger drag."),
                styleOptionRow(.mouse, symbolName: "computermouse", title: "Mouse style",
                               detail: "Tap the left or right half of the mouse to click. Tap, touch again and move to drag."),
            ], width: bw),
            section("CLICK", rows: trackpadClicks + mouseClicks
                    + [sliderRow("Tap sensitivity", sensitivity, sensitivityLabel, #selector(sensitivityChanged))], width: bw),
        ])
        page1.orientation = .vertical
        page1.alignment = .leading
        page1.spacing = 14

        // ---- Tab 2: More Gestures
        let reset = NSButton(title: "Reset Fine-Tuning", target: self, action: #selector(resetAdvanced))
        if #available(macOS 26.0, *) { reset.bezelStyle = .glass } else { reset.bezelStyle = .rounded }
        reset.controlSize = .large
        let footer = NSStackView(views: [NSView(), reset])
        footer.orientation = .horizontal
        footer.widthAnchor.constraint(equalToConstant: bw).isActive = true

        let page2 = NSStackView(views: [
            section("DRAG", rows: [trackpadDrag, mouseDrag], width: bw),
            section("FINE-TUNING", rows: [
                sliderRow("Drag distance", dragDistance, dragDistanceLabel, #selector(dragDistanceChanged)),
                toggleRow("Drag lock", "Keep dragging briefly after lifting your fingers", Preferences.Key.dragLock),
                sliderRow("Drag lock time", dragLockTimeout, dragLockLabel, #selector(dragLockTimeoutChanged)),
            ], width: bw),
            footer,
        ])
        page2.orientation = .vertical
        page2.alignment = .leading
        page2.spacing = 14

        tabPages = [page1, page2]
        stack.addArrangedSubview(page1)
        stack.addArrangedSubview(page2)

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

        batteryLabel.font = .systemFont(ofSize: 11)
        batteryLabel.textColor = .secondaryLabelColor
        batteryLabel.alignment = .right
        let flex = NSView()
        flex.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let row = NSStackView(views: [icon, labels, flex, batteryLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.widthAnchor.constraint(equalToConstant: Self.bodyWidth).isActive = true
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

    private func styleOptionRow(_ style: GestureStyle, symbolName: String, title: String, detail: String) -> NSView {
        let radio = NSButton(radioButtonWithTitle: "", target: self, action: #selector(styleRadioChanged(_:)))
        radio.tag = style.rawValue
        radio.setContentHuggingPriority(.required, for: .horizontal)
        radio.setContentCompressionResistancePriority(.required, for: .horizontal)
        radio.widthAnchor.constraint(equalToConstant: 20).isActive = true
        styleRadios.append(radio)

        let icon = NSImageView()
        icon.image = symbol(symbolName)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        icon.contentTintColor = .controlAccentColor
        icon.imageAlignment = .alignCenter
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 28).isActive = true

        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 13, weight: .semibold)
        let d = NSTextField(wrappingLabelWithString: detail)
        d.font = .systemFont(ofSize: 11)
        d.textColor = .secondaryLabelColor
        d.preferredMaxLayoutWidth = Self.bodyWidth - 32 - 20 - 28 - 20
        let labels = NSStackView(views: [t, d])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        labels.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = ClickRow(views: [radio, icon, labels])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 10
        row.widthAnchor.constraint(equalToConstant: Self.bodyWidth - 32).isActive = true
        labels.widthAnchor.constraint(equalToConstant: Self.bodyWidth - 32 - 20 - 28 - 20).isActive = true
        row.onClick = { [weak self, weak radio] in
            guard let radio else { return }
            radio.state = .on
            self?.styleRadioChanged(radio)
        }
        return row
    }

    @objc private func styleRadioChanged(_ sender: NSButton) {
        Preferences.style = GestureStyle(rawValue: sender.tag) ?? .trackpad
        for r in styleRadios { r.state = (r.tag == sender.tag) ? .on : .off }
        applyStyleVisibility(animated: true)
        onChange()
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
        switches.removeAll(); trackpadOnly.removeAll(); mouseOnly.removeAll(); demoForKey.removeAll(); tabPages.removeAll()
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

/// Stack row that acts as one big click target (used for the style choices).
private final class ClickRow: NSStackView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
}
