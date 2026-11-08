import AppKit

@objc protocol StatusPanelActions: AnyObject {
    func toggleEnabled()
    func selectStyle(_ sender: NSSegmentedControl)
    func toggleClickSound()
    func toggleLaunchAtLogin()
    func grantPermission()
    func openSettings()
    func quit()
}

/// The panel that opens from the menu bar icon.
final class StatusPanelController: NSViewController {
    struct State {
        let enabled: Bool
        let detail: String
        let icon: String
        let tint: NSColor
        let needsPermission: Bool
        let isMouseStyle: Bool
        let clickSound: Bool
        let launchAtLogin: Bool
    }

    private let actions: StatusPanelActions
    private let statusIcon = NSImageView()
    private let statusTitle = NSTextField(labelWithString: "")
    private let statusDetail = NSTextField(labelWithString: "")
    private let enabledSwitch = NSSwitch()
    private let styleControl = NSSegmentedControl()
    private let soundSwitch = NSSwitch()
    private let loginSwitch = NSSwitch()
    private var permissionCard: NSView?
    private var content: NSView!

    init(actions: StatusPanelActions) {
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        let logo = NSImageView(image: NSApp.applicationIconImage)
        logo.imageScaling = .scaleProportionallyDown
        logo.heightAnchor.constraint(equalToConstant: 52).isActive = true

        let statusCard = Card(views: [statusRow()])
        let permission = TapCard(
            row: row("lock.shield", "Grant Accessibility Access…", trailing: chevron()),
            title: "Grant Accessibility Access", target: actions, action: #selector(StatusPanelActions.grantPermission)
        )
        permissionCard = permission

        configure(styleControl)
        let gesturesCard = Card(views: [
            styleControl,
            row("speaker.wave.2", "Click Sound", trailing: bind(soundSwitch, #selector(StatusPanelActions.toggleClickSound))),
        ])

        let settings = TapCard(
            row: row("gearshape", "Settings", trailing: chevron()),
            title: "Settings", key: ",", target: actions, action: #selector(StatusPanelActions.openSettings)
        )
        let login = Card(views: [
            row("person.crop.circle", "Launch at Login", trailing: bind(loginSwitch, #selector(StatusPanelActions.toggleLaunchAtLogin))),
        ])
        let shortcut = NSTextField(labelWithString: "⌘Q")
        shortcut.textColor = .tertiaryLabelColor
        let quit = TapCard(
            row: row("power", "Quit LazyClick", trailing: shortcut),
            title: "Quit LazyClick", key: "q", target: actions, action: #selector(StatusPanelActions.quit)
        )

        let root = NSStackView(views: [
            logo, sectionLabel("Status"), statusCard, permission,
            sectionLabel("Gestures"), gesturesCard,
            sectionLabel("General"), settings, login, quit,
        ])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        root.stretchRows()
        root.setCustomSpacing(12, after: logo)
        root.setCustomSpacing(14, after: statusCard) // the permission card is usually hidden
        root.setCustomSpacing(14, after: permission)
        root.setCustomSpacing(14, after: gesturesCard)
        root.setCustomSpacing(14, after: login)
        root.widthAnchor.constraint(equalToConstant: 340).isActive = true
        root.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(root)
        // No bottom constraint: tied to the popover's frame, fittingSize can never report a smaller height.
        root.topAnchor.constraint(equalTo: container.topAnchor).isActive = true
        root.leadingAnchor.constraint(equalTo: container.leadingAnchor).isActive = true
        content = root
        view = container
    }

    /// Controls report slightly different heights once they are in a window.
    override func viewDidAppear() {
        super.viewDidAppear()
        preferredContentSize = content.fittingSize
    }

    func update(_ s: State) {
        _ = view // loadView configures the controls set below
        let config = NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
            .applying(.init(paletteColors: [.white, s.tint]))
        statusIcon.image = NSImage(systemSymbolName: s.icon, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        statusTitle.stringValue = s.enabled ? "Enabled" : "Disabled"
        statusDetail.stringValue = s.detail
        enabledSwitch.state = s.enabled ? .on : .off
        styleControl.selectedSegment = s.isMouseStyle ? 1 : 0
        styleControl.isEnabled = s.enabled
        soundSwitch.state = s.clickSound ? .on : .off
        loginSwitch.state = s.launchAtLogin ? .on : .off
        permissionCard?.isHidden = !s.needsPermission
        preferredContentSize = content.fittingSize
    }

    private func statusRow() -> NSView {
        statusTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        statusDetail.font = .systemFont(ofSize: 12)
        statusDetail.textColor = .secondaryLabelColor
        statusDetail.lineBreakMode = .byTruncatingTail
        let text = NSStackView(views: [statusTitle, statusDetail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusIcon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        enabledSwitch.setAccessibilityLabel("Enabled")
        return hStack([statusIcon, text, bind(enabledSwitch, #selector(StatusPanelActions.toggleEnabled))])
    }

    private func configure(_ control: NSSegmentedControl) {
        control.segmentCount = 2
        control.segmentDistribution = .fillEqually
        control.controlSize = .large
        control.trackingMode = .selectOne
        control.selectedSegmentBezelColor = .controlAccentColor
        control.setLabel("Trackpad style", forSegment: 0)
        control.setLabel("Mouse style", forSegment: 1)
        control.setImage(symbol("hand.point.up.left"), forSegment: 0)
        control.setImage(symbol("computermouse"), forSegment: 1)
        control.target = actions
        control.action = #selector(StatusPanelActions.selectStyle(_:))
    }

    private func bind(_ control: NSSwitch, _ action: Selector) -> NSSwitch {
        control.target = actions
        control.action = action
        control.controlSize = .small
        return control
    }

    private func sectionLabel(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func row(_ icon: String, _ title: String, trailing: NSView) -> NSView {
        let image = NSImageView()
        image.image = symbol(icon)
        image.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        image.contentTintColor = .labelColor
        image.widthAnchor.constraint(equalToConstant: 24).isActive = true
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trailing.setAccessibilityLabel(title)
        return hStack([image, label, trailing])
    }

    private func hStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.spacing = 10
        stack.distribution = .fill
        return stack
    }

    private func chevron() -> NSView {
        let image = NSImageView()
        image.image = symbol("chevron.right")
        image.contentTintColor = .tertiaryLabelColor
        return image
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
}

private extension NSStackView {
    func stretchRows() {
        for row in arrangedSubviews {
            row.widthAnchor.constraint(equalTo: widthAnchor, constant: -(edgeInsets.left + edgeInsets.right)).isActive = true
        }
    }
}

/// Rounded group of rows. NSBox, because its colors follow light and dark mode without a layer.
private class Card: NSBox {
    static let fill = NSColor.labelColor.withAlphaComponent(0.06)

    init(views: [NSView]) {
        super.init(frame: .zero)
        boxType = .custom
        titlePosition = .noTitle
        fillColor = Self.fill
        borderColor = .separatorColor
        borderWidth = 0.5
        cornerRadius = 12
        contentViewMargins = .zero

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.stretchRows()
        addSubview(stack)
        pin(stack)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func pin(_ view: NSView) {
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }
}

/// A card that is one big button and lights up under the pointer.
private final class TapCard: Card {
    init(row: NSView, title: String, key: String = "", target: AnyObject, action: Selector) {
        super.init(views: [row])
        let hit = NSButton(title: title, target: target, action: action)
        hit.isTransparent = true
        hit.keyEquivalent = key
        hit.keyEquivalentModifierMask = key.isEmpty ? [] : .command
        hit.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hit)
        pin(hit)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { fillColor = .labelColor.withAlphaComponent(0.12) }
    override func mouseExited(with event: NSEvent) { fillColor = Card.fill }
}
