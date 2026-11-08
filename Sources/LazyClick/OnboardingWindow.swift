import AppKit

/// First-run window: what LazyClick does, then a page where the user grants Accessibility access.
/// Built when opened, released when closed.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private static let contentWidth = GestureDemoView.size.width
    private static let margin: CGFloat = 32

    private var window: NSWindow?
    private let onClose: () -> Void
    private var onPermissionPage = false
    private var askedSystem = false
    private var wasTrusted = Permission.isTrusted

    private let demo = GestureDemoView(frame: NSRect(origin: .zero, size: GestureDemoView.size))
    private let welcomePage = NSStackView()
    private let permissionPage = NSStackView()
    private let statusBanner = NSStackView()
    private let statusIcon = NSImageView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private lazy var backButton = NSButton(title: "Back", target: self, action: #selector(backClicked))
    private lazy var notNowButton = NSButton(title: "Not Now", target: self, action: #selector(closeClicked))
    private lazy var primaryButton = NSButton(title: "Continue", target: self, action: #selector(primaryClicked))

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init()
    }

    func present() {
        if window == nil { window = makeWindow() }
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Used by `--show-onboarding --permission` to preview the second page.
    func showPermissionPage() {
        onPermissionPage = true
        reload()
    }

    /// Also called when the system reports an Accessibility change.
    func reload() {
        let trusted = Permission.isTrusted
        welcomePage.isHidden = onPermissionPage
        permissionPage.isHidden = !onPermissionPage
        backButton.isHidden = !onPermissionPage
        notNowButton.isHidden = !onPermissionPage || trusted
        primaryButton.title = !onPermissionPage ? "Continue" : trusted ? "Get Started" : "Allow Access…"

        let color: NSColor = trusted ? .systemGreen : .systemOrange
        statusIcon.image = NSImage(systemSymbolName: trusted ? "checkmark.circle.fill" : "hand.point.right.fill", accessibilityDescription: nil)
        statusIcon.contentTintColor = color
        statusLabel.stringValue = trusted
            ? "Access granted. You'll find LazyClick in the menu bar."
            : "Click Allow Access → Open System Settings → switch on LazyClick."
        statusBanner.layer?.backgroundColor = color.withAlphaComponent(0.18).cgColor

        // The user just came from System Settings: bring the last step back to the front.
        if trusted && !wasTrusted && onPermissionPage {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
        wasTrusted = trusted
    }

    // MARK: - Actions

    @objc private func primaryClicked() {
        if !onPermissionPage {
            onPermissionPage = true
            reload()
        } else if Permission.isTrusted {
            window?.close()
        } else if askedSystem {
            Permission.openSettings() // the system prompt may not appear twice; never leave this button dead
        } else {
            askedSystem = true
            Permission.request()
        }
    }

    @objc private func backClicked() {
        onPermissionPage = false
        reload()
    }

    @objc private func closeClicked() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        onClose()
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth + Self.margin * 2, height: 600),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Welcome to LazyClick"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        w.isReleasedWhenClosed = false
        w.delegate = self

        let backdrop = NSVisualEffectView()
        backdrop.material = .underWindowBackground
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        w.contentView = backdrop

        buildWelcomePage()
        buildPermissionPage()

        // Both pages share one slot, so the window keeps its size when switching.
        let slot = NSView()
        slot.translatesAutoresizingMaskIntoConstraints = false
        for page in [welcomePage, permissionPage] {
            page.orientation = .vertical
            page.alignment = .centerX
            page.spacing = 18
            page.translatesAutoresizingMaskIntoConstraints = false
            slot.addSubview(page)
            NSLayoutConstraint.activate([
                page.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
                page.topAnchor.constraint(greaterThanOrEqualTo: slot.topAnchor),
                page.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
            ])
        }

        let footer = makeFooter()
        backdrop.addSubview(slot)
        backdrop.addSubview(footer)
        NSLayoutConstraint.activate([
            slot.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 36),
            slot.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: Self.margin),
            slot.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            backdrop.trailingAnchor.constraint(equalTo: slot.trailingAnchor, constant: Self.margin),
            footer.topAnchor.constraint(equalTo: slot.bottomAnchor, constant: 22),
            footer.leadingAnchor.constraint(equalTo: slot.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: 22),
        ])
        backdrop.layoutSubtreeIfNeeded()
        w.setContentSize(backdrop.fittingSize)
        w.center()
        return w
    }

    private func buildWelcomePage() {
        demo.show(.sideLeft)
        demo.widthAnchor.constraint(equalToConstant: GestureDemoView.size.width).isActive = true
        demo.heightAnchor.constraint(equalToConstant: GestureDemoView.size.height).isActive = true

        let columnText: CGFloat = (Self.contentWidth - 24) / 2 - 40
        let cells = [
            [featureRow("hand.tap", "Tap to click", "Tap the left or right half of the mouse.", columnText, demo: .sideLeft),
             featureRow("hand.draw", "Tap and drag", "Tap, touch again and move. Lift to drop.", columnText, demo: .tapDrag)],
            [featureRow("hand.point.up.left", "Two styles", "Mouse style, or 1, 2 and 3-finger taps.", columnText, demo: .oneTap),
             featureRow("arrow.left.arrow.right", "Swipe to navigate", "Flick sideways to go back or forward.", columnText)],
            [featureRow("speaker.wave.2", "Click sounds", "Pick a sound and volume, or turn it off.", columnText),
             featureRow("battery.75", "Mouse battery", "See the charge in the menu bar.", columnText)],
        ]
        let grid = NSGridView(views: cells)
        grid.rowSpacing = 14
        grid.columnSpacing = 24

        welcomePage.setViews([
            makeHeader(image: NSApp.applicationIconImage, title: "Welcome to LazyClick", subtitle: "Tap to click on your Magic Mouse."),
            demo,
            grid,
        ], in: .top)
    }

    private func buildPermissionPage() {
        let shield = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 46, weight: .regular))
        let text = Self.contentWidth - 40

        let reasons = NSStackView(views: [
            featureRow("cursorarrow.click.2", "What it's for", "macOS requires Accessibility access before an app can turn your taps into clicks and drags.", text),
            featureRow("eye.slash", "What it doesn't do", "LazyClick doesn't read your screen or keystrokes, and it never connects to the internet.", text),
            featureRow("switch.2", "You stay in control", "Turn it off anytime in System Settings › Privacy & Security › Accessibility.", text),
        ])
        reasons.orientation = .vertical
        reasons.alignment = .leading
        reasons.spacing = 14

        statusIcon.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.preferredMaxLayoutWidth = Self.contentWidth - 60
        statusBanner.orientation = .horizontal
        statusBanner.alignment = .centerY
        statusBanner.spacing = 10
        statusBanner.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        statusBanner.wantsLayer = true
        statusBanner.layer?.cornerRadius = 10
        statusBanner.setViews([statusIcon, statusLabel], in: .leading)
        statusBanner.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true

        permissionPage.setViews([
            makeHeader(image: shield, title: "Allow Accessibility Access", subtitle: "One permission, and your taps become clicks."),
            reasons,
            statusBanner,
        ], in: .top)
    }

    private func makeHeader(image: NSImage?, title: String, subtitle: String) -> NSView {
        let icon = NSImageView()
        icon.image = image
        icon.contentTintColor = .controlAccentColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 24, weight: .bold)
        let s = NSTextField(labelWithString: subtitle)
        s.font = .systemFont(ofSize: 13)
        s.textColor = .secondaryLabelColor
        let header = NSStackView(views: [icon, t, s])
        header.orientation = .vertical
        header.alignment = .centerX
        header.spacing = 4
        header.setCustomSpacing(10, after: icon)
        return header
    }

    private func makeFooter() -> NSView {
        primaryButton.keyEquivalent = "\r"
        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.spacing = 8
        footer.setViews([backButton], in: .leading)
        footer.setViews([notNowButton, primaryButton], in: .trailing)
        footer.translatesAutoresizingMaskIntoConstraints = false
        return footer
    }

    /// Hovering a row that has a `demo` plays it in the preview above.
    private func featureRow(_ symbolName: String, _ title: String, _ detail: String, _ textWidth: CGFloat, demo kind: DemoKind? = nil) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        icon.contentTintColor = .controlAccentColor
        icon.imageAlignment = .alignCenter
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 13, weight: .semibold)
        let d = NSTextField(wrappingLabelWithString: detail)
        d.font = .systemFont(ofSize: 12)
        d.textColor = .secondaryLabelColor
        d.preferredMaxLayoutWidth = textWidth
        d.widthAnchor.constraint(equalToConstant: textWidth).isActive = true
        let labels = NSStackView(views: [t, d])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        let row = HoverRow(views: [icon, labels])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        if let kind {
            row.onHover = { [weak self] in
                if self?.demo.kind != kind { self?.demo.show(kind) }
            }
        }
        return row
    }
}
