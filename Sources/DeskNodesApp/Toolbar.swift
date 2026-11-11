import AppKit
import DeskNodesCore
import DeskNodesActions
import DeskNodesPersistence

/// The resident toolbar never becomes key or activates the app: arranging or collapsing
/// leaves keyboard focus where it was. Actions that need typing activate explicitly.
final class ToolbarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: ToolbarMetrics.width, height: ToolbarMetrics.height(paged: false)),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear; hasShadow = true
        hidesOnDeactivate = false; isFloatingPanel = true; level = .floating; isMovable = false
        // Above ordinary windows on every desktop, but never over another app's fullscreen space.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .ignoresCycle]
        title = "DeskNodes 工具条"
    }
}

@MainActor
final class Toolbar {
    enum Action: Int { case create, delete, arrange, collapse, settings }
    let panel = ToolbarPanel()
    private let root = ToolbarView()
    var perform: (Action) -> Void = { _ in }
    var turnPage: (Int) -> Void = { _ in }
    /// Called once when a drag of the grip ends, with the final frame.
    var moved: (NSRect) -> Void = { _ in }
    private(set) var paged = false

    init() {
        panel.contentView = root
        root.grip.moved = { [weak self] frame in self?.moved(frame) }
        for (index, button) in root.buttons.enumerated() {
            button.target = self; button.action = #selector(clicked(_:)); button.tag = index
        }
        root.pager.turn = { [weak self] delta in self?.turnPage(delta) }
    }
    @objc private func clicked(_ sender: ToolbarButton) {
        guard let action = Action(rawValue: sender.tag) else { return }
        perform(action)
    }
    struct State: Equatable {
        var count = 0
        var canDelete = false
        var collapsed = false
        /// (current, total) while an arrangement overflows.
        var page: (Int, Int)? = nil
        static func == (a: Self, b: Self) -> Bool {
            a.count == b.count && a.canDelete == b.canDelete && a.collapsed == b.collapsed && a.page?.0 == b.page?.0 && a.page?.1 == b.page?.1
        }
    }
    private var state: State?
    func update(_ new: State) {
        guard new != state else { return }
        state = new
        let empty = new.count == 0
        root.buttons[Action.delete.rawValue].isEnabled = new.canDelete
        root.buttons[Action.arrange.rawValue].isEnabled = !empty
        let collapse = root.buttons[Action.collapse.rawValue]
        collapse.isEnabled = !empty
        collapse.symbol = new.collapsed ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
        collapse.label = new.collapsed ? "展开" : "收起"
        collapse.help = new.collapsed ? "展开全部便签，恢复到收起前的位置" : "把全部便签收拢到工具条旁"
        root.count.stringValue = "\(new.count) 张便签"
        root.count.setAccessibilityLabel("当前共 \(new.count) 张便签")
        root.pager.isHidden = new.page == nil
        if let page = new.page { root.pager.show(current: page.0, total: page.1) }
        if paged != (new.page != nil) {
            paged = new.page != nil
            // Grow downwards: the grip stays under the pointer's last position.
            var frame = panel.frame
            let height = CGFloat(ToolbarMetrics.height(paged: paged))
            frame.origin.y += frame.height - height; frame.size.height = height
            panel.setFrame(frame, display: true)
        }
        root.needsLayout = true
    }
}

final class ToolbarView: NSView {
    private let material = NSVisualEffectView()
    let grip = ToolbarGrip()
    let buttons: [ToolbarButton] = [
        ToolbarButton(symbol: "plus", label: "新建", help: "新建便签"),
        ToolbarButton(symbol: "trash", label: "删除", help: "删除选中的便签", destructive: true),
        ToolbarButton(symbol: "square.grid.2x2", label: "整理", help: "把便签按屏幕从左到右排整齐"),
        ToolbarButton(symbol: "arrow.down.right.and.arrow.up.left", label: "收起", help: "把全部便签收拢到工具条旁"),
        ToolbarButton(symbol: "gearshape", label: "设置", help: "打开设置")
    ]
    let pager = ToolbarPager()
    let count = NSTextField(labelWithString: "")
    private let rule = NSView()
    override var isFlipped: Bool { true }
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = ToolbarMetrics.cornerRadius; layer?.masksToBounds = true; layer?.borderWidth = 0.5
        material.material = .popover; material.blendingMode = .behindWindow; material.state = .active
        count.font = .systemFont(ofSize: 11); count.textColor = NoteTheme.tertiary; count.alignment = .center
        rule.wantsLayer = true
        [material, grip, rule, count, pager].forEach { addSubview($0) }
        buttons.forEach { addSubview($0) }
        pager.isHidden = true
        setAccessibilityElement(true); setAccessibilityRole(.toolbar); setAccessibilityLabel("DeskNodes 工具条")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        material.frame = bounds
        let inset = CGFloat(ToolbarMetrics.inset), width = bounds.width - inset * 2
        grip.frame = NSRect(x: inset, y: inset, width: width, height: CGFloat(ToolbarMetrics.gripHeight))
        var y = grip.frame.maxY
        for button in buttons {
            button.frame = NSRect(x: inset, y: y, width: width, height: CGFloat(ToolbarMetrics.buttonHeight)); y += button.frame.height
        }
        if !pager.isHidden { pager.frame = NSRect(x: inset, y: y, width: width, height: CGFloat(ToolbarMetrics.pagerHeight)); y += pager.frame.height }
        rule.frame = NSRect(x: inset + 6, y: y + 2, width: width - 12, height: 1)
        count.frame = NSRect(x: 2, y: y + 10, width: bounds.width - 4, height: 15)
        colors()
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colors() }
    private func colors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NoteTheme.hairline.cgColor
            rule.layer?.backgroundColor = NoteTheme.hairline.cgColor
        }
    }
}

/// Dot grip at the top. The window moves live with the pointer, without easing.
final class ToolbarGrip: NSView {
    var moved: (NSRect) -> Void = { _ in }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.handle); setAccessibilityLabel("拖动工具条")
    }
    required init?(coder: NSCoder) { fatalError() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        NoteTheme.tertiary.setFill()
        for row in 0..<2 {
            for column in 0..<3 {
                let x = bounds.midX - 7 + CGFloat(column) * 5.5, y = bounds.midY - 4 + CGFloat(row) * 5
                NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 3, height: 3)).fill()
            }
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = NSEvent.mouseLocation, origin = window.frame.origin
        NSCursor.closedHand.push(); defer { NSCursor.pop() }
        var moved = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = NSEvent.mouseLocation
            var frame = window.frame
            frame.origin = NSPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y)
            // Clamp to the display under the pointer, so the grip can never leave the screen.
            let screens = DockController.screens()
            if let screen = screens.first(where: { DockGeometry.contains($0.visible, x: point.x, y: point.y) }) ?? screens.first {
                let clamped = Arrangement.clampToolbar(NoteFrame(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height), to: screen)
                frame.origin = NSPoint(x: clamped.x, y: clamped.y)
            }
            if frame.origin != window.frame.origin { window.setFrameOrigin(frame.origin); moved = true }
            if next.type == .leftMouseUp { break }
        }
        if moved { self.moved(window.frame) }
    }
}

/// Icon plus a short label; hover and press are quiet tints, disabled is dimmed.
final class ToolbarButton: NSControl {
    var symbol: String { didSet { needsDisplay = true } }
    var label: String { didSet { needsDisplay = true; setAccessibilityLabel(label) } }
    var help: String { didSet { toolTip = help; setAccessibilityHelp(help) } }
    private let destructive: Bool
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressing = false { didSet { needsDisplay = true } }
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var isEnabled: Bool { didSet { needsDisplay = true; setAccessibilityEnabled(isEnabled) } }
    init(symbol: String, label: String, help: String, destructive: Bool = false) {
        self.symbol = symbol; self.label = label; self.help = help; self.destructive = destructive
        super.init(frame: .zero)
        toolTip = help
        setAccessibilityElement(true); setAccessibilityRole(.button)
        setAccessibilityLabel(label); setAccessibilityHelp(help)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        return sendAction(action, to: target)
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window else { return }
        pressing = true
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let inside = bounds.contains(convert(next.locationInWindow, from: nil))
            pressing = inside
            if next.type == .leftMouseUp { break }
        }
        let fire = pressing
        pressing = false
        if fire { sendAction(action, to: target) }
    }
    override func draw(_ dirtyRect: NSRect) {
        let plate = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 10, yRadius: 10)
        if isEnabled && (pressing || hovering) {
            NoteTheme.primary.withAlphaComponent(pressing ? 0.12 : 0.06).setFill(); plate.fill()
        }
        let ink: NSColor = !isEnabled ? NoteTheme.primary.withAlphaComponent(0.28)
            : destructive && hovering ? NSColor.systemRed.withAlphaComponent(0.85) : NoteTheme.primary.withAlphaComponent(0.82)
        let configuration = NSImage.SymbolConfiguration(pointSize: 17, weight: .regular).applying(.init(paletteColors: [ink]))
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) {
            let size = image.size
            image.draw(in: NSRect(x: bounds.midX - size.width / 2, y: 18 - size.height / 2, width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (label as NSString).draw(in: NSRect(x: 0, y: 32, width: bounds.width, height: 15), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: ink, .paragraphStyle: paragraph])
    }
}

/// Shown only while the last arrangement overflowed a display.
final class ToolbarPager: NSView {
    var turn: (Int) -> Void = { _ in }
    private let previous = PagerArrow(symbol: "chevron.up", label: "上一页")
    private let next = PagerArrow(symbol: "chevron.down", label: "下一页")
    private let label = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium); label.alignment = .center
        label.textColor = NoteTheme.secondary
        previous.target = self; previous.action = #selector(back)
        next.target = self; next.action = #selector(forward)
        [previous, label, next].forEach { addSubview($0) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        previous.frame = NSRect(x: 0, y: (bounds.height - 22) / 2, width: 16, height: 22)
        next.frame = NSRect(x: bounds.width - 16, y: (bounds.height - 22) / 2, width: 16, height: 22)
        label.frame = NSRect(x: 14, y: (bounds.height - 14) / 2, width: bounds.width - 28, height: 14)
    }
    func show(current: Int, total: Int) {
        label.stringValue = "\(current + 1)/\(total)"
        label.setAccessibilityLabel("第 \(current + 1) 页，共 \(total) 页")
        previous.isEnabled = current > 0; next.isEnabled = current < total - 1
    }
    @objc private func back() { turn(-1) }
    @objc private func forward() { turn(1) }
}

private final class PagerArrow: NSButton {
    init(symbol: String, label: String) {
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        isBordered = false; contentTintColor = NoteTheme.secondary; toolTip = label; setAccessibilityLabel(label)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The small stack beside the toolbar while notes are collapsed: up to three colour
/// cards and a count, never note content. Clicking it expands.
final class StackHint: NSPanel {
    static let size = NSSize(width: 136, height: 118)
    private let view = StackHintView(frame: NSRect(origin: .zero, size: StackHint.size))
    var expand: () -> Void = {}
    override var canBecomeKey: Bool { false }
    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear; hasShadow = false
        hidesOnDeactivate = false; level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenNone, .ignoresCycle]
        contentView = view
        view.clicked = { [weak self] in self?.expand() }
    }
    func show(colors: [NotePalette], count: Int) { view.colors = Array(colors.prefix(3)); view.count = count }
}

private final class StackHintView: NSView {
    var colors: [NotePalette] = [] { didSet { needsDisplay = true } }
    var count = 0 { didSet { needsDisplay = true; setAccessibilityLabel("展开 \(count) 张便签") } }
    var clicked: () -> Void = {}
    private var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.button)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        toolTip = "展开便签"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { clicked(); return true }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseUp(with event: NSEvent) { if bounds.contains(convert(event.locationInWindow, from: nil)) { clicked() } }
    override func draw(_ dirtyRect: NSRect) {
        let card = NSSize(width: 100, height: 70)
        let lift: CGFloat = hovering ? 2 : 0
        // Back to front: the first note is the front card, bottom-left.
        let behind = CGFloat(max(0, colors.count - 1))
        for (index, palette) in colors.enumerated().reversed() {
            let depth = CGFloat(index)
            let rect = NSRect(x: 8 + depth * 11, y: 8 + (behind - depth) * 8 - lift, width: card.width, height: card.height)
            let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow(); shadow.shadowBlurRadius = 6; shadow.shadowOffset = NSSize(width: 0, height: -2)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.16); shadow.set()
            NoteTheme.background(palette).setFill(); path.fill()
            NSGraphicsContext.restoreGraphicsState()
            NoteTheme.border.setStroke(); path.lineWidth = 1; path.stroke()
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        let text = NSAttributedString(string: "\(count) 张便签", attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white, .paragraphStyle: paragraph,
            .shadow: { let s = NSShadow(); s.shadowBlurRadius = 3; s.shadowColor = NSColor.black.withAlphaComponent(0.55); return s }()])
        text.draw(in: NSRect(x: 0, y: bounds.height - 22, width: bounds.width, height: 18))
    }
}
