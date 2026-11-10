import AppKit
import QuartzCore

/// Which gesture the preview animates.
enum DemoKind: CaseIterable {
    case oneTap, twoTap, threeTap, threeDrag      // Trackpad style
    case sideLeft, sideRight, tapDrag, swapSides  // Mouse style
    case swipe, clickSound                        // both styles

    static let trackpad: [DemoKind] = [.oneTap, .twoTap, .threeTap, .threeDrag]
    static let mouse: [DemoKind] = [.sideLeft, .sideRight, .tapDrag, .swapSides]

    /// Fraction of the loop that best explains the gesture (used for Reduce Motion and screenshots).
    var stillFrame: Double {
        switch self {
        case .oneTap, .threeTap, .sideLeft: return 0.16
        case .twoTap, .sideRight, .swapSides: return 0.18
        case .threeDrag: return 0.5
        case .tapDrag: return 0.57
        case .swipe: return 0.27
        case .clickSound: return 0.06
        }
    }

    var caption: (title: String, detail: String) {
        switch self {
        case .oneTap: return ("Left click", "Tap once with one finger.")
        case .twoTap: return ("Right click", "Tap with two fingers.")
        case .threeTap: return ("Middle click", "Tap with three fingers.")
        case .threeDrag: return ("Drag and drop", "Rest three fingers on the mouse and move it. Lift your fingers to drop.")
        case .sideLeft: return ("Left click", "Tap the left half. Tap twice quickly to double-click.")
        case .sideRight: return ("Right click", "Tap the right half of the mouse.")
        case .tapDrag: return ("Drag and drop", "Tap, then touch again and move the mouse. Lift your finger to drop.")
        case .swapSides: return ("Swap left and right", "The halves are mirrored: tapping the left half now right-clicks.")
        case .swipe: return ("Swipe to navigate", "Flick left to right to go back, right to left to go forward.")
        case .clickSound: return ("Click sound", "Plays with every tap. Change the sound or volume in Settings.")
        }
    }
}

/// A looping Core Animation illustration shown as two cards, like System Settings > Mouse:
/// a top-down Magic Mouse with the touch points on the left, a tiny desktop with the result on the right.
/// Everything is drawn with layers, so it follows light/dark mode and costs nothing when the window is closed.
final class GestureDemoView: NSView {
    static let size = CGSize(width: 492, height: 190)
    private let loop: Double = 3.6

    private(set) var kind: DemoKind?
    private var stage = CALayer()
    /// When set, the scene is drawn frozen at this fraction of the loop instead of playing.
    private var frozenAt: Double?

    // Geometry (y axis points up)
    private let mouseSize = CGSize(width: 56, height: 114)
    private let mouseScale: CGFloat = 1.4
    private let mouseCard = CGRect(x: 0, y: 0, width: 200, height: 190)
    private let mouseHome = CGPoint(x: 100, y: 95)
    private let screenRect = CGRect(x: 212, y: 0, width: 280, height: 190)
    private let screenCenter = CGPoint(x: 352, y: 95)

    override var intrinsicContentSize: NSSize { Self.size }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.frame = CGRect(x: (bounds.width - Self.size.width) / 2, y: (bounds.height - Self.size.height) / 2,
                             width: Self.size.width, height: Self.size.height)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let kind { show(kind) } // colors are resolved at build time
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, let kind { show(kind) }
    }

    func show(_ kind: DemoKind) {
        self.kind = kind
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("\(kind.caption.title). \(kind.caption.detail)")
        if let f = ProcessInfo.processInfo.environment["LAZYCLICK_DEMO_FREEZE"], let frac = Double(f) {
            frozenAt = frac // developer hook for deterministic screenshots
        } else if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            frozenAt = kind.stillFrame // Reduce Motion: one still frame instead of a loop
        } else {
            frozenAt = nil
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        stage.removeFromSuperlayer()
        stage = CALayer()
        stage.bounds = CGRect(origin: .zero, size: Self.size)
        if frozenAt != nil { stage.speed = 0 }
        layer?.addSublayer(stage)
        stage.frame = CGRect(x: (bounds.width - Self.size.width) / 2, y: (bounds.height - Self.size.height) / 2,
                             width: Self.size.width, height: Self.size.height)
        build(kind)
        CATransaction.commit()
    }

    // MARK: - Colors

    private func color(_ c: NSColor, _ alpha: CGFloat = 1) -> CGColor {
        var out = c.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { out = c.withAlphaComponent(alpha).cgColor }
        return out
    }
    private var ink: NSColor { .labelColor }
    private var accent: NSColor { .controlAccentColor }

    // MARK: - Animation helpers

    private func track(_ l: CALayer, _ keyPath: String, _ points: [(Double, Any)]) {
        var p = points
        if let f = p.first, f.0 > 0 { p.insert((0, f.1), at: 0) }
        if let e = p.last, e.0 < 1 { p.append((1, e.1)) }
        let a = CAKeyframeAnimation(keyPath: keyPath)
        a.values = p.map { $0.1 }
        a.keyTimes = p.map { NSNumber(value: min(1, max(0, $0.0))) }
        a.duration = loop
        a.repeatCount = .infinity
        a.calculationMode = .linear
        a.isRemovedOnCompletion = false
        if let f = frozenAt { a.timeOffset = loop * f }
        l.add(a, forKey: keyPath)
    }

    private func num(_ v: Double) -> NSNumber { NSNumber(value: v) }
    private func pt(_ x: CGFloat, _ y: CGFloat) -> NSValue { NSValue(point: CGPoint(x: x, y: y)) }

    /// Fades/pops a layer in and out over the given windows (fractions of the loop).
    private func appear(_ l: CALayer, _ windows: [(Double, Double)]) {
        var op: [(Double, Any)] = [(0, num(0))]
        var sc: [(Double, Any)] = [(0, num(0.6))]
        for (a, b) in windows {
            op += [(a, num(0)), (a + 0.025, num(1)), (b, num(1)), (b + 0.025, num(0))]
            sc += [(a, num(0.6)), (a + 0.025, num(1)), (b, num(1)), (b + 0.025, num(0.6))]
        }
        l.opacity = 0
        track(l, "opacity", op)
        track(l, "transform.scale", sc)
    }

    private func ripple(at p: CGPoint, start t: Double, tint: NSColor? = nil) {
        let r = CAShapeLayer()
        r.bounds = CGRect(x: 0, y: 0, width: 34, height: 34)
        r.position = p
        r.path = CGPath(ellipseIn: r.bounds.insetBy(dx: 2, dy: 2), transform: nil)
        r.fillColor = nil
        r.strokeColor = tint.map { color($0) } ?? CGColor(gray: 1, alpha: 0.95)
        r.lineWidth = 2
        r.opacity = 0
        stage.addSublayer(r)
        track(r, "opacity", [(0, num(0)), (t, num(0)), (t + 0.01, num(1)), (t + 0.11, num(0))])
        track(r, "transform.scale", [(0, num(0.3)), (t, num(0.3)), (t + 0.11, num(1.6))])
    }

    // MARK: - Pieces

    private enum Half { case left, right }

    private func makeMouse(tint: Half? = nil, seam: Bool = false) -> CALayer {
        let m = CALayer()
        m.bounds = CGRect(origin: .zero, size: mouseSize)
        m.position = mouseHome
        m.transform = CATransform3DMakeScale(mouseScale, mouseScale, 1)
        let bodyPath = Self.mouseBodyPath(in: m.bounds.insetBy(dx: 1, dy: 1))

        let body = CAShapeLayer()
        body.path = bodyPath
        body.fillColor = color(ink, 0.03)
        body.strokeColor = color(ink, 0.92)
        body.lineWidth = 1.9
        m.addSublayer(body)

        if let tint {
            let t = CAShapeLayer()
            t.path = bodyPath
            t.fillColor = color(accent, 0.22)
            let mask = CALayer()
            mask.backgroundColor = NSColor.black.cgColor
            mask.frame = tint == .left
                ? CGRect(x: 0, y: 0, width: mouseSize.width / 2, height: mouseSize.height)
                : CGRect(x: mouseSize.width / 2, y: 0, width: mouseSize.width / 2, height: mouseSize.height)
            t.mask = mask
            m.addSublayer(t)
        }
        if seam {
            let s = CAShapeLayer()
            let p = CGMutablePath()
            p.move(to: CGPoint(x: mouseSize.width / 2, y: mouseSize.height - 6))
            p.addLine(to: CGPoint(x: mouseSize.width / 2, y: mouseSize.height * 0.42))
            s.path = p
            s.strokeColor = color(ink, 0.3)
            s.lineWidth = 1
            s.lineDashPattern = [3, 3]
            m.addSublayer(s)
        }
        stage.addSublayer(m)
        return m
    }

    /// Magic Mouse silhouette: long and slim (about 1:2.2), a fully round nose and a slightly flatter tail.
    private static func mouseBodyPath(in r: CGRect) -> CGPath {
        let rt = r.width / 2          // nose: full semicircle
        let rb = r.width * 0.42       // tail: a little flatter
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX, y: r.minY + rb))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + rb, y: r.minY), radius: rb)
        p.addLine(to: CGPoint(x: r.maxX - rb, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + rb), radius: rb)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rt))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - rt, y: r.maxY), radius: rt)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - rt), radius: rt)
        p.closeSubpath()
        return p
    }

    @discardableResult
    private func addFingers(to mouse: CALayer, at points: [CGPoint], windows: [(Double, Double)]) -> [CAShapeLayer] {
        points.map { p in
            let f = CAShapeLayer()
            f.bounds = CGRect(x: 0, y: 0, width: 16, height: 16)
            f.position = p
            f.path = CGPath(ellipseIn: f.bounds.insetBy(dx: 1, dy: 1), transform: nil)
            f.fillColor = color(accent, 0.5)
            f.strokeColor = color(accent)
            f.lineWidth = 1.5
            mouse.addSublayer(f)
            appear(f, windows)
            return f
        }
    }

    private func fixed(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }

    @discardableResult
    private func pill(_ rect: CGRect, _ radius: CGFloat, fill: CGColor, stroke: CGColor? = nil) -> CAShapeLayer {
        let l = CAShapeLayer()
        l.path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        l.fillColor = fill
        l.strokeColor = stroke
        l.lineWidth = stroke == nil ? 0 : 1
        stage.addSublayer(l)
        return l
    }

    private func makeScreen() {
        // left card: the mouse sits on it
        pill(mouseCard, 16, fill: color(ink, 0.07))

        // right card: a colourful little desktop, like the preview in System Settings
        let ox = screenRect.minX
        let wall = CAGradientLayer()
        wall.frame = screenRect
        wall.cornerRadius = 16
        wall.colors = [fixed(0.22, 0.29, 0.68), fixed(0.34, 0.21, 0.60)]
        wall.startPoint = CGPoint(x: 0, y: 1)
        wall.endPoint = CGPoint(x: 1, y: 0)
        stage.addSublayer(wall)

        let bar = fixed(1, 1, 1, 0.7)
        for (i, w) in [14.0, 22, 22, 22, 14].enumerated() { // menu bar, left
            pill(CGRect(x: ox + 12 + CGFloat(i) * 28, y: 178, width: w, height: 5), 2.5, fill: bar)
        }
        for i in 0..<4 { // menu bar, right
            pill(CGRect(x: screenRect.maxX - 18 - CGFloat(i) * 12, y: 178, width: 7, height: 5), 2.5, fill: bar)
        }

        // browser-like window
        let win = CGRect(x: ox + 14, y: 34, width: 252, height: 132)
        pill(win, 9, fill: fixed(0.15, 0.20, 0.46, 0.95), stroke: fixed(1, 1, 1, 0.12))
        pill(CGRect(x: win.minX + 8, y: win.maxY - 18, width: win.width - 16, height: 11), 5.5, fill: fixed(1, 1, 1, 0.14))
        pill(CGRect(x: win.minX + 13, y: win.maxY - 15.5, width: 6, height: 6), 3, fill: fixed(0.72, 0.78, 1, 0.9))
        let ink2 = fixed(0.70, 0.75, 1, 0.8)
        pill(CGRect(x: win.minX + 12, y: 140, width: 84, height: 4), 2, fill: fixed(0.85, 0.89, 1, 0.95))
        for (k, w) in [96.0, 80, 88].enumerated() {
            pill(CGRect(x: win.minX + 12, y: 130 - CGFloat(k) * 8, width: w, height: 3), 1.5, fill: ink2)
            pill(CGRect(x: win.minX + 126, y: 130 - CGFloat(k) * 8, width: w + 4, height: 3), 1.5, fill: ink2)
        }

        // three tiles: circle, square, triangle
        let tileFill = fixed(0.09, 0.12, 0.30, 0.95)
        for k in 0..<3 {
            let r = CGRect(x: win.minX + 12 + CGFloat(k) * 80, y: 42, width: 68, height: 36)
            pill(r, 6, fill: tileFill)
            let c = CGPoint(x: r.midX, y: r.midY)
            let shape = CAShapeLayer()
            switch k {
            case 0:
                shape.path = CGPath(ellipseIn: CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22), transform: nil)
                shape.fillColor = fixed(0.55, 0.50, 0.96)
            case 1:
                shape.path = CGPath(roundedRect: CGRect(x: c.x - 10, y: c.y - 10, width: 20, height: 20), cornerWidth: 3, cornerHeight: 3, transform: nil)
                shape.fillColor = fixed(0.52, 0.80, 1.0)
            default:
                let t = CGMutablePath()
                t.move(to: CGPoint(x: c.x, y: c.y + 12))
                t.addLine(to: CGPoint(x: c.x + 12, y: c.y - 10))
                t.addLine(to: CGPoint(x: c.x - 12, y: c.y - 10))
                t.closeSubpath()
                shape.path = t
                shape.fillColor = fixed(0.95, 0.42, 0.30)
            }
            stage.addSublayer(shape)
        }

        // dock
        pill(CGRect(x: ox + 62, y: 6, width: 156, height: 21), 8, fill: fixed(1, 1, 1, 0.2))
        let dock: [CGColor] = [fixed(0.25, 0.55, 1), fixed(1, 0.72, 0.2), fixed(0.95, 0.35, 0.4), fixed(0.4, 0.8, 0.4),
                               fixed(1, 0.85, 0.3), fixed(0.95, 0.95, 0.95), fixed(0.45, 0.78, 0.95), fixed(0.55, 0.45, 0.95)]
        for (i, c) in dock.enumerated() {
            pill(CGRect(x: ox + 70 + CGFloat(i) * 18.5, y: 10, width: 13, height: 13), 3.5, fill: c)
        }
    }

    private func makeCursor(tip: CGPoint) -> CAShapeLayer {
        let c = CAShapeLayer()
        c.bounds = CGRect(x: 0, y: 0, width: 13, height: 21)
        c.anchorPoint = CGPoint(x: 0, y: 1)
        c.position = tip
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: 20))
        p.addLine(to: CGPoint(x: 0, y: 3))
        p.addLine(to: CGPoint(x: 4.5, y: 7))
        p.addLine(to: CGPoint(x: 7.5, y: 0.5))
        p.addLine(to: CGPoint(x: 10, y: 1.8))
        p.addLine(to: CGPoint(x: 7, y: 8.5))
        p.addLine(to: CGPoint(x: 12, y: 9))
        p.closeSubpath()
        c.path = p
        c.fillColor = CGColor(gray: 0, alpha: 1)
        c.strokeColor = CGColor(gray: 1, alpha: 1)
        c.lineWidth = 1.2
        stage.addSublayer(c)
        return c
    }

    /// A button on the little desktop that flashes when it is clicked.
    private func makeButton(flashAt t: Double, tint: NSColor? = nil) {
        let b = CAShapeLayer()
        b.bounds = CGRect(x: 0, y: 0, width: 76, height: 26)
        b.position = screenCenter
        b.path = CGPath(roundedRect: b.bounds, cornerWidth: 7, cornerHeight: 7, transform: nil)
        b.fillColor = CGColor(gray: 1, alpha: 0.14)
        b.strokeColor = CGColor(gray: 1, alpha: 0.6)
        b.lineWidth = 1
        stage.addSublayer(b)
        let line = CAShapeLayer()
        line.path = CGPath(roundedRect: CGRect(x: 20, y: 11, width: 36, height: 4), cornerWidth: 2, cornerHeight: 2, transform: nil)
        line.fillColor = CGColor(gray: 1, alpha: 0.6)
        b.addSublayer(line)
        let rest = CGColor(gray: 1, alpha: 0.14)
        let hit = tint.map { color($0, 0.8) } ?? CGColor(gray: 1, alpha: 0.75)
        track(b, "fillColor", [(0, rest), (t, rest), (t + 0.02, hit), (t + 0.17, rest)])
    }

    private func makeContextMenu(origin tip: CGPoint, windows: [(Double, Double)]) {
        let m = CAShapeLayer()
        m.bounds = CGRect(x: 0, y: 0, width: 62, height: 46)
        m.anchorPoint = CGPoint(x: 0, y: 1)
        m.position = CGPoint(x: tip.x + 3, y: tip.y - 3)
        m.path = CGPath(roundedRect: m.bounds, cornerWidth: 8, cornerHeight: 8, transform: nil)
        m.fillColor = CGColor(gray: 0.97, alpha: 0.97)
        m.strokeColor = CGColor(gray: 0, alpha: 0.25)
        m.lineWidth = 1
        for (i, w) in [40.0, 30.0, 36.0].enumerated() {
            let row = CAShapeLayer()
            let y = 33 - CGFloat(i) * 13
            row.path = CGPath(roundedRect: CGRect(x: 10, y: y, width: w, height: 5), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
            row.fillColor = i == 0 ? color(accent, 0.8) : CGColor(gray: 0, alpha: 0.3)
            m.addSublayer(row)
        }
        stage.addSublayer(m)
        appear(m, windows)
    }

    // MARK: - Scenes

    private func build(_ kind: DemoKind) {
        makeScreen()
        switch kind {
        case .oneTap, .sideLeft: buildLeftClick(halves: kind == .sideLeft)
        case .twoTap: buildContextClick(fingers: [CGPoint(x: 14, y: 84), CGPoint(x: 38, y: 84)], tint: nil)
        case .sideRight: buildContextClick(fingers: [CGPoint(x: 39, y: 84)], tint: .right)
        case .swapSides: buildContextClick(fingers: [CGPoint(x: 13, y: 84)], tint: .left)
        case .threeTap: buildMiddleClick()
        case .threeDrag:
            buildDrag(fingerSets: [[CGPoint(x: 9, y: 84), CGPoint(x: 26, y: 92), CGPoint(x: 43, y: 84)]],
                      windows: [[(0.08, 0.88)]], moveFrom: 0.28, moveTo: 0.62)
        case .tapDrag:
            // Second touch lands quickly after the tap and the drag starts as soon as the pointer moves:
            // a short settle (0.1 s).
            let down = 0.20, a = down + 0.1 / loop
            buildDrag(fingerSets: [[CGPoint(x: 13, y: 84)], [CGPoint(x: 13, y: 84)]],
                      windows: [[(0.07, 0.12)], [(down, 0.88)]], moveFrom: a, moveTo: a + 0.3, firstTapRipple: 0.08)
        case .swipe: buildSwipe()
        case .clickSound: buildClickSound()
        }
    }

    /// The previous page slides in on the back flick and away again on the forward flick.
    private func buildSwipe() {
        let mouse = makeMouse()
        let left = pt(12, 84), right = pt(44, 84)
        let finger = addFingers(to: mouse, at: [CGPoint(x: 12, y: 84)], windows: [(0.12, 0.28), (0.56, 0.72)])[0]
        track(finger, "position", [(0, left), (0.13, left), (0.28, right), (0.57, right), (0.72, left)])

        // clipped to the little browser window, below its address bar
        let viewport = CALayer()
        viewport.frame = CGRect(x: screenRect.minX + 14, y: 34, width: 252, height: 112)
        viewport.cornerRadius = 9
        viewport.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        viewport.masksToBounds = true
        stage.addSublayer(viewport)

        let page = CALayer()
        page.bounds = viewport.bounds
        page.backgroundColor = fixed(0.16, 0.42, 0.50)
        viewport.addSublayer(page)
        for (r, alpha) in [(CGRect(x: 14, y: 42, width: 224, height: 58), 0.22),
                           (CGRect(x: 14, y: 28, width: 150, height: 5), 0.8),
                           (CGRect(x: 14, y: 16, width: 196, height: 4), 0.5)] {
            let bar = CALayer()
            bar.frame = r
            bar.cornerRadius = min(r.height / 2, 6)
            bar.backgroundColor = fixed(1, 1, 1, alpha)
            page.addSublayer(bar)
        }
        let y = viewport.bounds.midY, on = pt(viewport.bounds.midX, y), off = pt(-viewport.bounds.midX, y)
        track(page, "position", [(0, off), (0.18, off), (0.34, on), (0.62, on), (0.78, off)])

        for (back, window) in [(true, (0.18, 0.34)), (false, (0.62, 0.78))] {
            let badge = CAShapeLayer()
            badge.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
            badge.position = screenCenter
            badge.path = CGPath(ellipseIn: badge.bounds, transform: nil)
            badge.fillColor = CGColor(gray: 0, alpha: 0.5)
            let chevron = CAShapeLayer()
            let (tip, tail): (CGFloat, CGFloat) = back ? (16, 26) : (28, 18)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: tail, y: 32))
            p.addLine(to: CGPoint(x: tip, y: 22))
            p.addLine(to: CGPoint(x: tail, y: 12))
            chevron.path = p
            chevron.fillColor = nil
            chevron.strokeColor = CGColor(gray: 1, alpha: 1)
            chevron.lineWidth = 3.5
            chevron.lineCap = .round
            chevron.lineJoin = .round
            badge.addSublayer(chevron)
            stage.addSublayer(badge)
            appear(badge, [window])
        }
    }

    /// The tap comes first in the loop so it lines up with the sound played on hover.
    private func buildClickSound() {
        let mouse = makeMouse()
        addFingers(to: mouse, at: [CGPoint(x: 13, y: 84)], windows: [(0.02, 0.09)])

        let badgeRect = CGRect(x: screenCenter.x - 24, y: screenCenter.y - 24, width: 48, height: 48)
        pill(badgeRect, 24, fill: CGColor(gray: 0, alpha: 0.5))
        let icon = CALayer()
        icon.bounds = CGRect(x: 0, y: 0, width: 30, height: 30)
        icon.position = screenCenter
        icon.contentsGravity = .resizeAspect
        icon.contents = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white])))
        stage.addSublayer(icon)
        track(icon, "transform.scale", [(0, num(1)), (0.03, num(1)), (0.06, num(1.2)), (0.16, num(1))])
        ripple(at: screenCenter, start: 0.04)
        ripple(at: screenCenter, start: 0.1)
    }

    private func buildLeftClick(halves: Bool) {
        let mouse = makeMouse(tint: halves ? .left : nil, seam: halves)
        addFingers(to: mouse, at: [CGPoint(x: 13, y: 84)], windows: [(0.12, 0.2)])
        makeButton(flashAt: 0.13)
        let tip = CGPoint(x: screenCenter.x - 6, y: screenCenter.y + 6)
        _ = makeCursor(tip: tip)
        ripple(at: tip, start: 0.14)
    }

    private func buildMiddleClick() {
        let mouse = makeMouse()
        addFingers(to: mouse, at: [CGPoint(x: 9, y: 84), CGPoint(x: 26, y: 92), CGPoint(x: 43, y: 84)], windows: [(0.12, 0.2)])
        makeButton(flashAt: 0.13, tint: .systemOrange)
        let tip = CGPoint(x: screenCenter.x - 6, y: screenCenter.y + 6)
        _ = makeCursor(tip: tip)
        ripple(at: tip, start: 0.14, tint: .systemOrange)
    }

    private func buildContextClick(fingers: [CGPoint], tint: Half?) {
        let mouse = makeMouse(tint: tint, seam: tint != nil)
        addFingers(to: mouse, at: fingers, windows: [(0.12, 0.2)])
        let tip = CGPoint(x: screenCenter.x - 24, y: screenCenter.y + 22)
        makeContextMenu(origin: tip, windows: [(0.16, 0.82)])
        _ = makeCursor(tip: tip) // above the menu
        ripple(at: tip, start: 0.14)
    }

    private func buildDrag(fingerSets: [[CGPoint]], windows: [[(Double, Double)]],
                           moveFrom a: Double, moveTo b: Double, firstTapRipple: Double? = nil) {
        let mouse = makeMouse()
        for (set, w) in zip(fingerSets, windows) { addFingers(to: mouse, at: set, windows: w) }

        let start = CGPoint(x: 256, y: 95), end = CGPoint(x: 448, y: 95)

        // drop zone
        let zone = CAShapeLayer()
        zone.bounds = CGRect(x: 0, y: 0, width: 46, height: 46)
        zone.position = end
        zone.path = CGPath(roundedRect: zone.bounds.insetBy(dx: 1, dy: 1), cornerWidth: 9, cornerHeight: 9, transform: nil)
        let white = CGColor(gray: 1, alpha: 1)
        zone.strokeColor = CGColor(gray: 1, alpha: 0.75)
        zone.lineDashPattern = [4, 3]
        zone.lineWidth = 1.2
        zone.fillColor = CGColor(gray: 1, alpha: 0)
        stage.addSublayer(zone)
        let clear = CGColor(gray: 1, alpha: 0), lit = white.copy(alpha: 0.3)!
        track(zone, "fillColor", [(0, clear), (b, clear), (b + 0.04, lit), (0.94, lit), (0.97, clear)])

        // file being dragged
        let file = CAShapeLayer()
        file.bounds = CGRect(x: 0, y: 0, width: 24, height: 30)
        file.position = start
        file.path = CGPath(roundedRect: file.bounds.insetBy(dx: 1, dy: 1), cornerWidth: 4, cornerHeight: 4, transform: nil)
        file.fillColor = CGColor(gray: 1, alpha: 0.95)
        file.strokeColor = color(.systemOrange)
        file.lineWidth = 2
        stage.addSublayer(file)
        track(file, "position", [(0, pt(start.x, start.y)), (a, pt(start.x, start.y)), (b, pt(end.x, end.y)),
                                 (0.95, pt(end.x, end.y)), (0.951, pt(start.x, start.y))])
        track(file, "opacity", [(0, num(0)), (0.03, num(1)), (0.93, num(1)), (0.97, num(0))])

        // cursor rides on the file
        let cursor = makeCursor(tip: start)
        track(cursor, "position", [(0, pt(start.x, start.y)), (a, pt(start.x, start.y)), (b, pt(end.x, end.y)),
                                   (0.95, pt(end.x, end.y)), (0.951, pt(start.x, start.y))])
        if let t = firstTapRipple { ripple(at: start, start: t) }

        // the mouse slides to the right with the drag, then comes back
        track(mouse, "position", [(0, pt(mouseHome.x, mouseHome.y)), (a, pt(mouseHome.x, mouseHome.y)),
                                  (b, pt(mouseHome.x + 30, mouseHome.y)), (0.88, pt(mouseHome.x + 30, mouseHome.y)),
                                  (0.96, pt(mouseHome.x, mouseHome.y))])
    }
}
