import AppKit
import QuartzCore

/// Which gesture the preview animates.
enum DemoKind: CaseIterable {
    case oneTap, twoTap, threeTap, threeDrag      // Trackpad style
    case sideLeft, sideRight, tapDrag, swapSides  // Mouse style
    case mission                                  // both

    static let trackpad: [DemoKind] = [.oneTap, .twoTap, .threeTap, .threeDrag, .mission]
    static let mouse: [DemoKind] = [.sideLeft, .sideRight, .tapDrag, .swapSides, .mission]

    /// Fraction of the loop that best explains the gesture (used for Reduce Motion and screenshots).
    var stillFrame: Double {
        switch self {
        case .oneTap, .threeTap, .sideLeft: return 0.16
        case .twoTap, .sideRight, .swapSides: return 0.18
        case .threeDrag: return 0.5
        case .tapDrag: return 0.57
        case .mission: return 0.65
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
        case .mission: return ("Mission Control", "Rest four fingers on the mouse and push it forward.")
        }
    }
}

/// A looping Core Animation illustration: a top-down Magic Mouse on the left, a tiny desktop on the right.
/// Everything is drawn with layers, so it follows light/dark mode and costs nothing when the window is closed.
final class GestureDemoView: NSView {
    static let size = CGSize(width: 392, height: 150)
    private let loop: Double = 3.6

    private(set) var kind: DemoKind?
    private var stage = CALayer()
    /// When set, the scene is drawn frozen at this fraction of the loop instead of playing.
    private var frozenAt: Double?

    // Geometry (y axis points up)
    private let mouseSize = CGSize(width: 80, height: 112)
    private let mouseHome = CGPoint(x: 66, y: 75)
    private let screenRect = CGRect(x: 142, y: 14, width: 236, height: 122)
    private let screenCenter = CGPoint(x: 260, y: 75)

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
        r.strokeColor = color(tint ?? accent)
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
        let bodyPath = CGPath(roundedRect: m.bounds.insetBy(dx: 1, dy: 1), cornerWidth: 38, cornerHeight: 38, transform: nil)

        let body = CAShapeLayer()
        body.path = bodyPath
        body.fillColor = color(ink, 0.06)
        body.strokeColor = color(ink, 0.4)
        body.lineWidth = 1.5
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

    private func addFingers(to mouse: CALayer, at points: [CGPoint], windows: [(Double, Double)]) {
        for p in points {
            let f = CAShapeLayer()
            f.bounds = CGRect(x: 0, y: 0, width: 18, height: 18)
            f.position = p
            f.path = CGPath(ellipseIn: f.bounds.insetBy(dx: 1, dy: 1), transform: nil)
            f.fillColor = color(accent, 0.5)
            f.strokeColor = color(accent)
            f.lineWidth = 1.5
            mouse.addSublayer(f)
            appear(f, windows)
        }
    }

    private func makeScreen() {
        let s = CAShapeLayer()
        s.path = CGPath(roundedRect: screenRect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        s.fillColor = color(ink, 0.035)
        s.strokeColor = color(ink, 0.25)
        s.lineWidth = 1
        stage.addSublayer(s)
        for i in 0..<3 {
            let d = CAShapeLayer()
            d.path = CGPath(ellipseIn: CGRect(x: screenRect.minX + 9 + CGFloat(i) * 9, y: screenRect.maxY - 12, width: 5, height: 5), transform: nil)
            d.fillColor = color(ink, 0.25)
            stage.addSublayer(d)
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
        c.fillColor = color(ink, 0.9)
        c.strokeColor = color(.windowBackgroundColor)
        c.lineWidth = 1
        stage.addSublayer(c)
        return c
    }

    /// A button on the little desktop that flashes when it is clicked.
    private func makeButton(flashAt t: Double, tint: NSColor? = nil) {
        let b = CAShapeLayer()
        b.bounds = CGRect(x: 0, y: 0, width: 76, height: 26)
        b.position = screenCenter
        b.path = CGPath(roundedRect: b.bounds, cornerWidth: 7, cornerHeight: 7, transform: nil)
        b.fillColor = color(ink, 0.06)
        b.strokeColor = color(ink, 0.3)
        b.lineWidth = 1
        stage.addSublayer(b)
        let line = CAShapeLayer()
        line.path = CGPath(roundedRect: CGRect(x: 20, y: 11, width: 36, height: 4), cornerWidth: 2, cornerHeight: 2, transform: nil)
        line.fillColor = color(ink, 0.35)
        b.addSublayer(line)
        track(b, "fillColor", [(0, color(ink, 0.06)), (t, color(ink, 0.06)), (t + 0.02, color(tint ?? accent, 0.6)),
                               (t + 0.17, color(ink, 0.06))])
    }

    private func makeContextMenu(origin tip: CGPoint, windows: [(Double, Double)]) {
        let m = CAShapeLayer()
        m.bounds = CGRect(x: 0, y: 0, width: 62, height: 46)
        m.anchorPoint = CGPoint(x: 0, y: 1)
        m.position = CGPoint(x: tip.x + 3, y: tip.y - 3)
        m.path = CGPath(roundedRect: m.bounds, cornerWidth: 8, cornerHeight: 8, transform: nil)
        m.fillColor = color(.windowBackgroundColor)
        m.strokeColor = color(ink, 0.35)
        m.lineWidth = 1
        for (i, w) in [40.0, 30.0, 36.0].enumerated() {
            let row = CAShapeLayer()
            let y = 33 - CGFloat(i) * 13
            row.path = CGPath(roundedRect: CGRect(x: 10, y: y, width: w, height: 5), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil)
            row.fillColor = color(i == 0 ? accent : ink, i == 0 ? 0.7 : 0.3)
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
        case .twoTap: buildContextClick(fingers: [CGPoint(x: 24, y: 80), CGPoint(x: 56, y: 80)], tint: nil)
        case .sideRight: buildContextClick(fingers: [CGPoint(x: 58, y: 78)], tint: .right)
        case .swapSides: buildContextClick(fingers: [CGPoint(x: 22, y: 78)], tint: .left)
        case .threeTap: buildMiddleClick()
        case .threeDrag:
            buildDrag(fingerSets: [[CGPoint(x: 16, y: 78), CGPoint(x: 40, y: 86), CGPoint(x: 64, y: 78)]],
                      windows: [[(0.08, 0.88)]], moveFrom: 0.28, moveTo: 0.62)
        case .tapDrag:
            buildDrag(fingerSets: [[CGPoint(x: 22, y: 78)], [CGPoint(x: 22, y: 78)]],
                      windows: [[(0.07, 0.14)], [(0.27, 0.88)]], moveFrom: 0.42, moveTo: 0.72, firstTapRipple: 0.08)
        case .mission: buildMission()
        }
    }

    private func buildLeftClick(halves: Bool) {
        let mouse = makeMouse(tint: halves ? .left : nil, seam: halves)
        addFingers(to: mouse, at: [CGPoint(x: 22, y: 78)], windows: [(0.12, 0.2)])
        makeButton(flashAt: 0.13)
        let tip = CGPoint(x: screenCenter.x - 6, y: screenCenter.y + 6)
        _ = makeCursor(tip: tip)
        ripple(at: tip, start: 0.14)
    }

    private func buildMiddleClick() {
        let mouse = makeMouse()
        addFingers(to: mouse, at: [CGPoint(x: 16, y: 78), CGPoint(x: 40, y: 86), CGPoint(x: 64, y: 78)], windows: [(0.12, 0.2)])
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

        let start = CGPoint(x: 196, y: 75), end = CGPoint(x: 336, y: 75)

        // drop zone
        let zone = CAShapeLayer()
        zone.bounds = CGRect(x: 0, y: 0, width: 46, height: 46)
        zone.position = end
        zone.path = CGPath(roundedRect: zone.bounds.insetBy(dx: 1, dy: 1), cornerWidth: 9, cornerHeight: 9, transform: nil)
        zone.strokeColor = color(ink, 0.4)
        zone.lineDashPattern = [4, 3]
        zone.lineWidth = 1.2
        zone.fillColor = color(accent, 0)
        stage.addSublayer(zone)
        track(zone, "fillColor", [(0, color(accent, 0)), (b, color(accent, 0)), (b + 0.04, color(accent, 0.3)),
                                  (0.94, color(accent, 0.3)), (0.97, color(accent, 0))])

        // file being dragged
        let file = CAShapeLayer()
        file.bounds = CGRect(x: 0, y: 0, width: 24, height: 30)
        file.position = start
        file.path = CGPath(roundedRect: file.bounds.insetBy(dx: 1, dy: 1), cornerWidth: 4, cornerHeight: 4, transform: nil)
        file.fillColor = color(accent, 0.3)
        file.strokeColor = color(accent)
        file.lineWidth = 1.5
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

    private func buildMission() {
        let mouse = makeMouse()
        addFingers(to: mouse, at: [CGPoint(x: 12, y: 74), CGPoint(x: 30, y: 86), CGPoint(x: 50, y: 86), CGPoint(x: 68, y: 74)],
                   windows: [(0.08, 0.86)])
        track(mouse, "position", [(0, pt(mouseHome.x, mouseHome.y)), (0.2, pt(mouseHome.x, mouseHome.y)),
                                  (0.42, pt(mouseHome.x, mouseHome.y + 10)), (0.88, pt(mouseHome.x, mouseHome.y + 10)),
                                  (0.96, pt(mouseHome.x, mouseHome.y))])

        // three overlapping windows that fan out into thumbnails
        let big = CGSize(width: 112, height: 72)
        let from = [CGPoint(x: 236, y: 64), CGPoint(x: 262, y: 74), CGPoint(x: 288, y: 84)]
        let to = [CGPoint(x: 194, y: 94), CGPoint(x: 260, y: 94), CGPoint(x: 326, y: 94)]
        for i in 0..<3 {
            let w = CAShapeLayer()
            w.bounds = CGRect(origin: .zero, size: big)
            w.path = CGPath(roundedRect: w.bounds.insetBy(dx: 1, dy: 1), cornerWidth: 7, cornerHeight: 7, transform: nil)
            w.fillColor = color(.windowBackgroundColor)
            w.strokeColor = color(i == 2 ? accent : ink, i == 2 ? 0.8 : 0.35)
            w.lineWidth = 1.2
            w.position = from[i]
            let bar = CAShapeLayer()
            bar.path = CGPath(roundedRect: CGRect(x: 8, y: big.height - 14, width: 40, height: 4), cornerWidth: 2, cornerHeight: 2, transform: nil)
            bar.fillColor = color(ink, 0.25)
            w.addSublayer(bar)
            stage.addSublayer(w)
            track(w, "position", [(0, pt(from[i].x, from[i].y)), (0.42, pt(from[i].x, from[i].y)),
                                  (0.56, pt(to[i].x, to[i].y)), (0.86, pt(to[i].x, to[i].y)), (0.96, pt(from[i].x, from[i].y))])
            track(w, "transform.scale", [(0, num(1)), (0.42, num(1)), (0.56, num(0.5)), (0.86, num(0.5)), (0.96, num(1))])
        }
    }
}
