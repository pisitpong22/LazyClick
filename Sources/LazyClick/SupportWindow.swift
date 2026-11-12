import AppKit

/// "Help LazyClick keep going": opened from the menu, Settings, or the click milestone. Never pops up by itself.
final class SupportWindowController: NSObject, NSWindowDelegate {
    /// Clicks after which the menu bar icon turns blue once, inviting the user to look.
    static let milestone = 1_000
    private static var shared: SupportWindowController?

    private var window: NSWindow?

    static func show() {
        Preferences.set(true, for: Preferences.Key.supportSeen)
        if shared == nil { shared = SupportWindowController() }
        shared?.present()
    }

    private func present() {
        if window == nil { window = makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        Self.shared = nil
    }

    @objc private func coffee() { open("https://buymeacoffee.com/pisitpong") }
    @objc private func star() { open("https://github.com/pisitpong22/LazyClick") }
    @objc private func done() { window?.close() }
    private func open(_ s: String) { if let url = URL(string: s) { NSWorkspace.shared.open(url) } }

    private func makeWindow() -> NSWindow {
        let width: CGFloat = 440
        let heart = NSImageView(image: NSImage(systemSymbolName: "heart.fill", accessibilityDescription: nil) ?? NSImage())
        heart.symbolConfiguration = .init(pointSize: 30, weight: .regular)
        heart.contentTintColor = .systemPink

        let title = NSTextField(labelWithString: "Help LazyClick keep going")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let header = NSStackView(views: [heart, title])
        header.spacing = 12

        let clicks = Preferences.int(Preferences.Key.clickCount)
        var text = "LazyClick is free and open source, with no ads or tracking. If it saves you clicks, buying me a coffee helps fund its development."
        if clicks >= Self.milestone {
            text = "LazyClick has clicked \(clicks.formatted()) times for you so far. 🎉\n\n" + text
        }
        let body = NSTextField(wrappingLabelWithString: text)
        body.textColor = .secondaryLabelColor
        body.preferredMaxLayoutWidth = width

        let coffee = NSButton(title: "Buy Me a Coffee", target: self, action: #selector(coffee))
        coffee.image = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil)
        coffee.imagePosition = .imageLeading
        coffee.bezelStyle = .rounded
        coffee.controlSize = .large
        coffee.keyEquivalent = "\r"

        let star = NSButton(title: "A star on GitHub also helps more people find LazyClick", target: self, action: #selector(star))
        star.image = NSImage(systemSymbolName: "star", accessibilityDescription: nil)
        star.imagePosition = .imageLeading
        star.isBordered = false
        star.contentTintColor = .secondaryLabelColor
        star.font = .systemFont(ofSize: 12)

        let thanks = NSTextField(labelWithString: "Thank you for being here. 🤍")
        thanks.font = .systemFont(ofSize: 12)
        thanks.textColor = .tertiaryLabelColor

        let doneButton = NSButton(title: "Done", target: self, action: #selector(done))
        doneButton.keyEquivalent = "\u{1b}"
        let footer = NSStackView(views: [thanks, NSView(), doneButton])
        footer.widthAnchor.constraint(equalToConstant: width).isActive = true

        let stack = NSStackView(views: [header, body, coffee, star, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.setCustomSpacing(10, after: coffee)
        stack.edgeInsets = NSEdgeInsets(top: 28, left: 32, bottom: 24, right: 32)
        stack.widthAnchor.constraint(equalToConstant: width + 64).isActive = true

        let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Support LazyClick"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = stack
        w.center()
        return w
    }
}
