import AppKit

/// First-run window: the pitch, the features, then a page where the user grants Accessibility access.
/// Built when opened, released when closed.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private static let contentWidth = GestureDemoView.size.width
    private static let margin: CGFloat = 32

    private var window: NSWindow?
    private let onClose: () -> Void
    private var page = 0
    private var onPermissionPage: Bool { page == pages.count - 1 }
    private var askedSystem = false
    private var wasTrusted = Permission.isTrusted

    private let demo = GestureDemoView(frame: NSRect(origin: .zero, size: GestureDemoView.size))
    private let introPage = NSStackView()
    private let featuresPage = NSStackView()
    private let permissionPage = NSStackView()
    private var pages: [NSStackView] { [introPage, featuresPage, permissionPage] }
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

    /// Used by `--show-onboarding --page <n>` to preview one page.
    func showPage(_ n: Int) {
        page = max(0, min(n, pages.count - 1))
        reload()
    }

    /// Also called when the system reports an Accessibility change.
    func reload() {
        let trusted = Permission.isTrusted
        for (i, p) in pages.enumerated() { p.isHidden = i != page }
        backButton.isHidden = page == 0
        notNowButton.isHidden = !onPermissionPage || trusted
        primaryButton.title = !onPermissionPage ? "Continue" : trusted ? "Get Started" : askedSystem ? "Open System Settings…" : "Continue…"

        let color: NSColor = trusted ? .systemGreen : .systemOrange
        statusIcon.image = NSImage(systemSymbolName: trusted ? "checkmark.circle.fill" : "info.circle.fill", accessibilityDescription: nil)
        statusIcon.contentTintColor = color
        statusLabel.stringValue = trusted
            ? "Access granted. You'll find LazyClick in the menu bar."
            : askedSystem ? "Click Open System Settings → switch on LazyClick."
            : "Click Continue → Open System Settings → switch on LazyClick."
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
            page += 1
            reload()
        } else if Permission.isTrusted {
            window?.close()
        } else if askedSystem {
            Permission.openSettings() // the system prompt may not appear twice; never leave this button dead
        } else {
            askedSystem = true
            Permission.request()
            reload()
        }
    }

    @objc private func backClicked() {
        page -= 1
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

        buildIntroPage()
        buildFeaturesPage()
        buildPermissionPage()

        // All pages share one slot, so the window keeps its size when switching.
        let slot = NSView()
        slot.translatesAutoresizingMaskIntoConstraints = false
        for page in pages {
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

    private func buildIntroPage() {
        let icon = NSImageView()
        icon.image = NSApp.applicationIconImage
        icon.setAccessibilityElement(false) // the name right below already says it
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 112).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 112).isActive = true
        let name = NSTextField(labelWithString: "LazyClick")
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        name.textColor = .secondaryLabelColor
        let headline = NSTextField(wrappingLabelWithString: "Why press…\nwhen you can tap?")
        headline.font = .systemFont(ofSize: 40, weight: .bold)
        headline.alignment = .center
        headline.preferredMaxLayoutWidth = Self.contentWidth
        let line = NSTextField(labelWithString: "Tap your Magic Mouse to click.")
        line.font = .systemFont(ofSize: 17)
        line.textColor = .secondaryLabelColor

        introPage.setViews([icon, name, headline, line], in: .top)
        introPage.setCustomSpacing(6, after: icon)
        introPage.setCustomSpacing(26, after: name)
        introPage.setCustomSpacing(12, after: headline)
    }

    private func buildFeaturesPage() {
        demo.show(.sideLeft)
        demo.widthAnchor.constraint(equalToConstant: GestureDemoView.size.width).isActive = true
        demo.heightAnchor.constraint(equalToConstant: GestureDemoView.size.height).isActive = true

        let columnText: CGFloat = (Self.contentWidth - 24) / 2 - 40
        let cells = [
            [featureRow("computermouse", "Mouse Style", "Tap the left or right half to click. Tap, touch again and move to drag.", columnText, demo: .tapDrag),
             featureRow("hand.point.up.left", "Trackpad Style", "Tap with 1, 2 or 3 fingers to click. Rest three fingers and move to drag.", columnText, demo: .twoTap)],
            [featureRow("speaker.wave.2", "Click Sound", "Hear a click with every tap. Change the sound or volume in Settings.", columnText, demo: .clickSound),
             featureRow("arrow.left.arrow.right", "Swipe to Navigate", "Flick sideways to go back or forward.", columnText, demo: .swipe)],
        ]
        let grid = NSGridView(views: cells)
        grid.rowSpacing = 14
        grid.columnSpacing = 24

        let hint = NSTextField(labelWithString: "Hover over a feature to preview it.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor

        featuresPage.setViews([
            makeHeader(image: nil, title: "Mouse Style or Trackpad Style", subtitle: "Starts in Mouse Style. Switch anytime in Settings."),
            demo,
            hint,
            grid,
        ], in: .top)
        featuresPage.setCustomSpacing(6, after: demo)
    }

    private func buildPermissionPage() {
        let shield = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 46, weight: .regular))
        let text = Self.contentWidth - 40

        let reasons = NSStackView(views: [
            featureRow("cursorarrow.click.2", "What it's for", "macOS requires Accessibility access before an app can turn your taps into clicks and drags.", text, detailColor: .labelColor),
            featureRow("eye.slash", "What it doesn't do", "LazyClick doesn't read your screen or keystrokes. It only goes online to check for updates.", text, detailColor: .labelColor),
            featureRow("switch.2", "You stay in control", "Turn it off anytime in System Settings › Privacy & Security › Accessibility.", text, detailColor: .labelColor),
        ])
        reasons.orientation = .vertical
        reasons.alignment = .leading
        reasons.spacing = 14

        statusIcon.setAccessibilityElement(false) // the label beside it states the status
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
        icon.setAccessibilityElement(false)
        icon.isHidden = image == nil
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
    private func featureRow(_ symbolName: String, _ title: String, _ detail: String, _ textWidth: CGFloat,
                            detailColor: NSColor = .secondaryLabelColor, demo kind: DemoKind? = nil) -> NSView {
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        icon.setAccessibilityElement(false)
        icon.contentTintColor = .controlAccentColor
        icon.imageAlignment = .alignCenter
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true

        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 13, weight: .semibold)
        let d = NSTextField(wrappingLabelWithString: detail)
        d.font = .systemFont(ofSize: 12)
        d.textColor = detailColor
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
                guard let self else { return }
                if kind == .clickSound {
                    demo.show(kind) // restart, so the tap lines up with the sound
                    if window?.isKeyWindow == true { ClickSound.play() } // tracking is active even behind other windows
                } else if demo.kind != kind {
                    demo.show(kind)
                }
            }
        }
        return row
    }
}
