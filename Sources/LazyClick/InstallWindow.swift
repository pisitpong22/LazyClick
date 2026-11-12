import AppKit

/// A downloaded copy opened straight from Downloads: offer to move itself to Applications, put the download
/// in the Trash and reopen from there. Run from Downloads it can't be deleted while open, can't update itself
/// (Gatekeeper runs it from a read-only copy) and Launch at Login is unreliable.
final class InstallWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let onSkip: () -> Void
    private var installing = false

    init(onSkip: @escaping () -> Void) {
        self.onSkip = onSkip
        super.init()
    }

    /// Only a downloaded copy (quarantined or translocated) outside Applications; never a local build or a Homebrew install.
    static var shouldOffer: Bool {
        let running = Bundle.main.bundlePath
        guard running.hasSuffix(".app") else { return false }
        let path = originalURL.path
        let inApplications = ["/Applications/", NSHomeDirectory() + "/Applications/"].contains { path.hasPrefix($0) }
        return !inApplications && (running.contains("/AppTranslocation/") || getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) >= 0)
    }

    /// Where the bundle really is: Gatekeeper runs a downloaded app from a randomized read-only mirror (App Translocation).
    static var originalURL: URL {
        let url = Bundle.main.bundleURL
        guard url.path.contains("/AppTranslocation/"),
              let security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let sym = dlsym(security, "SecTranslocateCreateOriginalPathForURL") else { return url }
        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        return unsafeBitCast(sym, to: Fn.self)(url as CFURL, nil)?.takeRetainedValue() as URL? ?? url
    }

    func present() {
        if window == nil { window = makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Install

    @objc private func moveClicked() {
        let dest = URL(fileURLWithPath: "/Applications/LazyClick.app")
        do {
            try Self.install(to: dest)
        } catch {
            let a = NSAlert()
            a.messageText = "Couldn't move LazyClick to Applications"
            a.informativeText = error.localizedDescription + "\n\nYou can drag LazyClick into the Applications folder yourself."
            a.runModal()
            NSWorkspace.shared.activateFileViewerSelecting([Self.originalURL])
            return
        }
        installing = true
        window?.close()
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: dest, configuration: config) { _, error in
            DispatchQueue.main.async {
                if error != nil { NSWorkspace.shared.activateFileViewerSelecting([dest]) }
                NSApp.terminate(nil)
            }
        }
    }

    private static func install(to dest: URL) throws {
        let fm = FileManager.default
        let source = originalURL
        // An older copy still running would post every click twice.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "") where app != .current {
            app.terminate()
        }
        if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) } // the Trash keeps it recoverable
        try fm.copyItem(at: Bundle.main.bundleURL, to: dest) // the running bundle is readable even when translocated
        // We moved it, not Finder, so clear the download flag or Gatekeeper would translocate it again.
        let xattr = try Process.run(URL(fileURLWithPath: "/usr/bin/xattr"), arguments: ["-dr", "com.apple.quarantine", dest.path])
        xattr.waitUntilExit()

        // The download is no longer needed: the old app and the zip it came in go to the Trash.
        let folder = source.deletingLastPathComponent()
        let zips = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "zip" && $0.lastPathComponent.hasPrefix("LazyClick") } ?? []
        for url in [source] + zips { try? fm.trashItem(at: url, resultingItemURL: nil) }
    }

    @objc private func notNowClicked() { window?.close() }

    func windowWillClose(_ notification: Notification) {
        window?.delegate = nil
        window = nil
        if !installing { onSkip() }
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let width: CGFloat = 400
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width + 64, height: 300),
                         styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = "Install LazyClick"
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

        // LazyClick → Applications folder: what the button is about to do, at a glance.
        let arrow = NSImageView(image: NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil) ?? NSImage())
        arrow.symbolConfiguration = .init(pointSize: 22, weight: .semibold)
        arrow.contentTintColor = .tertiaryLabelColor
        let flow = NSStackView(views: [icon(NSApp.applicationIconImage), arrow, icon(NSWorkspace.shared.icon(forFile: "/Applications"))])
        flow.spacing = 18
        flow.setAccessibilityElement(false)

        let title = NSTextField(labelWithString: "Move to Applications")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        let body = NSTextField(wrappingLabelWithString: "LazyClick will install itself in your Applications folder, put the download in the Trash, and open again. It keeps itself up to date from there.")
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor
        body.alignment = .center
        body.preferredMaxLayoutWidth = width

        let notNow = NSButton(title: "Not Now", target: self, action: #selector(notNowClicked))
        notNow.keyEquivalent = "\u{1b}"
        notNow.controlSize = .large
        let move = NSButton(title: "Move to Applications", target: self, action: #selector(moveClicked))
        move.keyEquivalent = "\r"
        move.controlSize = .large
        let buttons = NSStackView(views: [notNow, move])
        buttons.spacing = 10

        let stack = NSStackView(views: [flow, title, body, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(22, after: flow)
        stack.setCustomSpacing(26, after: body)
        stack.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 40),
            stack.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: 32),
            backdrop.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 32),
            backdrop.bottomAnchor.constraint(equalTo: stack.bottomAnchor, constant: 28),
        ])
        backdrop.layoutSubtreeIfNeeded()
        w.setContentSize(backdrop.fittingSize)
        w.center()
        return w
    }

    private func icon(_ image: NSImage) -> NSImageView {
        let v = NSImageView(image: image)
        v.imageScaling = .scaleProportionallyUpOrDown
        v.widthAnchor.constraint(equalToConstant: 88).isActive = true
        v.heightAnchor.constraint(equalToConstant: 88).isActive = true
        return v
    }
}
