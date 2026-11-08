import AppKit
import LazyClickCore

/// Settings panel. Built when opened, released when closed.
/// On macOS 26+ the cards are Liquid Glass (`NSGlassEffectView`); older systems get a blurred rounded card.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private static let leftWidth: CGFloat = GestureDemoView.size.width
    private static let rightWidth: CGFloat = GestureDemoView.size.width
    private static let gap: CGFloat = 18
    private static let margin: CGFloat = 22
    private static var contentWidth: CGFloat { margin * 2 + leftWidth }

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
    private let batteryLabel = NSTextField(labelWithString: "")

    private var styleRadios: [NSButton] = []
    private let permissionBanner = NSStackView()
    private let soundPopup = NSPopUpButton(frame: .zero, pullsDown: false)

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
        permissionBanner.isHidden = Permission.isTrusted
        for (key, s) in switches { s.state = Preferences.bool(key) ? .on : .off }
        for r in styleRadios { r.state = (r.tag == Preferences.style.rawValue) ? .on : .off }
        soundPopup.selectItem(withTitle: Preferences.clickSound)
        applyStyleVisibility(animated: animated)
    }

    private func applyStyleVisibility(animated: Bool) {
        let mouse = Preferences.style == .mouse
        trackpadOnly.forEach { $0.isHidden = mouse }
        mouseOnly.forEach { $0.isHidden = !mouse }
        let allowed = mouse ? DemoKind.mouse : DemoKind.trackpad
        if let k = demo.kind, allowed.contains(k) { select(k) } else { select(allowed[0]) }
        resizeToFit(animated: animated)
    }

    private func refreshBattery() {
        MouseBattery.read { [weak self] percent in
            self?.batteryLabel.stringValue = percent.map { "Battery \($0)%" } ?? ""
        }
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
        stack.addArrangedSubview(left)

        let lw = Self.leftWidth, rw = Self.rightWidth

        // ---- Left column: header, style, gestures
        left.addArrangedSubview(makeHeader())
        left.addArrangedSubview(makePermissionBanner(width: lw))

        // ---- Live preview
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
        captions.widthAnchor.constraint(equalToConstant: rw).isActive = true
        captionDetail.widthAnchor.constraint(equalToConstant: rw - 40).isActive = true
        let preview = NSStackView(views: [demo, captions])
        preview.orientation = .vertical
        preview.alignment = .centerX
        preview.spacing = 8
        left.insertArrangedSubview(preview, at: 1)

        left.addArrangedSubview(section("CHOOSE A STYLE", rows: [
            styleOptionRow(.trackpad, symbolName: "hand.point.up.left", title: "Trackpad style",
                           detail: "Tap with 1, 2 or 3 fingers = left, right, middle click. Three-finger drag."),
            styleOptionRow(.mouse, symbolName: "computermouse", title: "Mouse style",
                           detail: "Tap the left or right half of the mouse to click. Tap, touch again and move to drag."),
        ], width: lw))

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
        trackpadOnly = trackpadRows
        mouseOnly = mouseRows
        left.addArrangedSubview(section("GESTURES", rows: trackpadRows + mouseRows, width: lw))

        soundPopup.addItems(withTitles: ClickSound.names)
        soundPopup.target = self
        soundPopup.action = #selector(soundChanged(_:))
        let volume = NSSlider(value: Preferences.double(Preferences.Key.clickVolume), minValue: 0, maxValue: 1,
                              target: self, action: #selector(volumeChanged(_:)))
        volume.isContinuous = false // save and preview once on release, not on every step of the drag
        volume.widthAnchor.constraint(equalToConstant: 160).isActive = true
        left.addArrangedSubview(section("CLICK SOUND", rows: [
            controlRow("Sound", soundPopup),
            controlRow("Volume", volume),
        ], width: lw))

        w.center()
        return w
    }

    /// Shown only while Accessibility access is missing, so a first-time user knows why clicks do nothing.
    private func makePermissionBanner(width: CGFloat) -> NSView {
        let label = NSTextField(wrappingLabelWithString: "LazyClick needs Accessibility access before it can click for you.")
        label.font = .systemFont(ofSize: 12)
        label.preferredMaxLayoutWidth = width - 150
        let button = NSButton(title: "Open System Settings", target: self, action: #selector(openAccessibility))
        button.bezelStyle = .rounded
        permissionBanner.orientation = .horizontal
        permissionBanner.alignment = .centerY
        permissionBanner.spacing = 10
        permissionBanner.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        permissionBanner.wantsLayer = true
        permissionBanner.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.18).cgColor
        permissionBanner.layer?.cornerRadius = 10
        permissionBanner.setViews([label, button], in: .leading)
        permissionBanner.widthAnchor.constraint(equalToConstant: width).isActive = true
        return permissionBanner
    }

    @objc private func openAccessibility() {
        Permission.request()
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
        let flex = NSView()
        flex.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let row = NSStackView(views: [icon, labels, flex, batteryLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.widthAnchor.constraint(equalToConstant: Self.leftWidth).isActive = true
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
        d.preferredMaxLayoutWidth = Self.leftWidth - 32 - 20 - 28 - 20
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
        row.widthAnchor.constraint(equalToConstant: Self.leftWidth - 32).isActive = true
        labels.widthAnchor.constraint(equalToConstant: Self.leftWidth - 32 - 20 - 28 - 20).isActive = true
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

    private func controlRow(_ title: String, _ control: NSControl) -> NSView {
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 13, weight: .medium)
        t.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setAccessibilityLabel(title)
        let flex = NSView()
        flex.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        let row = NSStackView(views: [t, flex, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 8
        return row
    }

    // MARK: - Actions

    @objc private func soundChanged(_ sender: NSPopUpButton) {
        Preferences.clickSound = sender.titleOfSelectedItem ?? "None"
        ClickSound.play()
    }

    @objc private func volumeChanged(_ sender: NSSlider) {
        Preferences.set(sender.doubleValue, for: Preferences.Key.clickVolume)
        ClickSound.play()
    }

    @objc private func switchChanged(_ sender: NSSwitch) {
        guard let key = sender.identifier?.rawValue else { return }
        Preferences.set(sender.state == .on, for: key)
        if let k = demoForKey[key] { select(k) }
        onChange()
    }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        rootStack = nil
        switches.removeAll(); trackpadOnly.removeAll(); mouseOnly.removeAll(); demoForKey.removeAll()
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
