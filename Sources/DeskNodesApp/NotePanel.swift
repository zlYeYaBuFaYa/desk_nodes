import AppKit
import QuartzCore
import DeskNodesCore

final class NotePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(origin: NSPoint) {
        // Prototype 03 default: 14 + 16 title + 8 gap + 3×26 + 14 = 130pt.
        super.init(contentRect: NSRect(origin: origin, size: NSSize(width: NoteMetrics.width, height: 130)),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        title = "今天 · 临时预览"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // N4 owns desktop/transient levels and Spaces. No fullscreen behavior in N1.
        level = .normal
        contentView = NoteCardView(frame: .zero)
    }

    func showPreview() {
        orderFrontRegardless()
        guard let layer = contentView?.layer else { return }
        layer.removeAnimation(forKey: "noteInsertion")
        let duration = MotionPolicy.insertionDuration(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        guard duration > 0 else { return }
        let spring = CASpringAnimation(keyPath: "transform.translation.y")
        spring.fromValue = -8
        spring.toValue = 0
        spring.mass = 1
        spring.stiffness = 300
        spring.damping = 27
        spring.duration = duration
        layer.add(spring, forKey: "noteInsertion")
    }
}

private final class NoteCardView: NSView {
    private let palette: NotePalette = .paper
    private let titleLabel = NSTextField(labelWithString: "今天")
    private let countLabel = NSTextField(labelWithString: "1 / 3")
    private let completed = NSTextField(labelWithString: "回复评审邮件")
    private let editors = [NoteTextView(text: "确认周会议程"), NoteTextView(text: "取快递")]
    private var marks: [CompletionMark] = []

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = NoteMetrics.cornerRadius
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        titleLabel.font = .systemFont(ofSize: NoteMetrics.titleSize, weight: .semibold)
        titleLabel.textColor = NoteTheme.primary
        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = NoteTheme.secondary
        countLabel.alignment = .right
        completed.font = .systemFont(ofSize: NoteMetrics.itemSize)
        completed.attributedStringValue = NSAttributedString(string: completed.stringValue, attributes: [
            .font: NSFont.systemFont(ofSize: NoteMetrics.itemSize),
            .foregroundColor: NoteTheme.completed, .strikethroughStyle: NSUnderlineStyle.single.rawValue
        ])
        [titleLabel, countLabel, completed].forEach { addSubview($0) }
        for index in 0..<3 {
            let mark = CompletionMark(done: index == 0)
            marks.append(mark)
            addSubview(mark)
        }
        for editor in editors {
            let scroll = NSScrollView()
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = false
            scroll.hasHorizontalScroller = false
            scroll.documentView = editor
            addSubview(scroll)
        }
        toolTip = "N1 临时预览：文字可编辑，退出后不保存；尚未实现事项操作。"
        setAccessibilityLabel("今天，临时便签预览，完成 1 项，共 3 项")
        updateColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layout() {
        super.layout()
        let p = NoteMetrics.padding
        titleLabel.frame = NSRect(x: p - 2, y: p - 2, width: 130, height: 20)
        countLabel.frame = NSRect(x: bounds.width - p - 50, y: p - 1, width: 50, height: 18)
        for index in 0..<3 {
            marks[index].frame = NSRect(x: p, y: 38 + Double(index) * 26 + 5, width: 16, height: 16)
        }
        completed.frame = NSRect(x: p + 25 - 2, y: 41, width: bounds.width - 2 * p - 23, height: 20)
        for (index, editor) in editors.enumerated() {
            let scroll = editor.enclosingScrollView!
            scroll.frame = NSRect(x: p + 25, y: 64 + Double(index) * 26,
                                  width: bounds.width - 2 * p - 25, height: 26)
            editor.frame = NSRect(origin: .zero, size: scroll.contentSize)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.backgroundColor = NoteTheme.background(palette).cgColor
            layer?.borderColor = NoteTheme.border.cgColor
            CATransaction.commit()
        }
        marks.forEach { $0.needsDisplay = true }
        // Do not rewrite editor storage/attributes: composition and selection must survive.
    }
}

private final class CompletionMark: NSView {
    private let done: Bool
    init(done: Bool) {
        self.done = done
        super.init(frame: .zero)
        toolTip = "完成状态示意；勾选功能尚未实现"
        setAccessibilityElement(true)
        setAccessibilityLabel(done ? "已完成（示意）" : "未完成（示意）")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func draw(_ dirtyRect: NSRect) {
        let circle = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75))
        if done {
            NoteTheme.primary.withAlphaComponent(0.72).setFill()
            circle.fill()
            NoteTheme.background(.paper).setStroke()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: 4, y: 8))
            check.line(to: NSPoint(x: 7, y: 5))
            check.line(to: NSPoint(x: 12, y: 11))
            check.lineWidth = 1.6
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
        } else {
            NoteTheme.primary.withAlphaComponent(0.42).setStroke()
            circle.lineWidth = 1.5
            circle.stroke()
        }
    }
}
