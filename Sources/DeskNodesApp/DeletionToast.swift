import AppKit
import QuartzCore
import DeskNodesCore

/// Light, rounded, slightly translucent capsule shared by the deletion and error toasts.
final class ToastSurface: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .popover; blendingMode = .behindWindow; state = .active
        wantsLayer = true; layer?.cornerRadius = 14; layer?.masksToBounds = true; layer?.borderWidth = 0.5
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() { super.layout(); colors() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); colors() }
    private func colors() { effectiveAppearance.performAsCurrentDrawingAppearance { layer?.borderColor = NoteTheme.hairline.cgColor } }
}

/// Separate bottom toast survives deleting the last note. No editor undo manager is replaced.
final class DeletionToast: NSPanel {
    private static let size = NSSize(width: 296, height: 46)
    private let restore: () -> Void
    private let label = NSTextField(labelWithString: "已删除便签")
    private let icon = NSImageView()
    private let rule = NSView()
    init(restore: @escaping () -> Void) {
        self.restore = restore
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        super.init(contentRect: NSRect(x: visible.midX - Self.size.width / 2, y: visible.minY + 28, width: Self.size.width, height: Self.size.height),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        level = .floating
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear; hasShadow = true
        let view = ToastSurface(frame: NSRect(origin: .zero, size: Self.size))
        icon.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        icon.contentTintColor = NoteTheme.primary
        icon.frame = NSRect(x: 18, y: 13, width: 18, height: 20)
        label.textColor = NoteTheme.primary
        label.font = .systemFont(ofSize: 13); label.frame = NSRect(x: 46, y: 14, width: 160, height: 18)
        label.lineBreakMode = .byTruncatingTail
        rule.wantsLayer = true; rule.frame = NSRect(x: 214, y: 12, width: 1, height: 22)
        rule.layer?.backgroundColor = NSColor.separatorColor.cgColor
        let button = NSButton(title: "", target: self, action: #selector(undoDeletion))
        button.attributedTitle = NSAttributedString(string: "撤销", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NoteTheme.accent])
        button.setAccessibilityLabel("撤销删除")
        button.isBordered = false; button.frame = NSRect(x: 222, y: 9, width: 62, height: 28)
        [icon, label, rule, button].forEach { view.addSubview($0) }
        contentView = view
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let group = CAAnimationGroup()
            group.animations = [Motion.basic("transform.translation.y", from: -8, to: 0), Motion.basic("opacity", from: 0, to: 1)]
            group.duration = MotionPolicy.insertion; group.timingFunction = Motion.easeOut
            view.layer?.add(group, forKey: "toastInsertion")
        }
    }
    /// Several deletions inside the window are undone newest first, one per click / ⌘Z.
    /// `notes`: notes in the newest deletion, 0 for an item. A batch is one entry.
    func update(count: Int, notes: Int) {
        label.stringValue = count > 1 ? "已删除 \(count) 项 · 可逐项撤销"
            : notes > 1 ? "已删除 \(notes) 张便签" : (notes == 1 ? "已删除便签" : "已删除事项")
    }
    func dismiss() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = contentView?.layer else { close(); return }
        ignoresMouseEvents = true
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0; fade.duration = MotionPolicy.deletion
        fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: "toastDismissal")
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionPolicy.deletion) { self.close() }
    }
    @objc private func undoDeletion() { restore() }
}

/// Non-activating, non-modal error notice above the deletion toast. Repeated failures
/// replace the text and extend the lifetime instead of stacking dialogs.
final class NoticeToast: NSPanel {
    private let label = NSTextField(wrappingLabelWithString: "")
    private let closed: () -> Void
    private var generation = 0
    init(closed: @escaping () -> Void) {
        self.closed = closed
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenNone] // only the toolbar and topmost notes cover fullscreen apps
        level = .floating
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear; hasShadow = true
        let view = ToastSurface(frame: .zero)
        label.textColor = NoteTheme.primary; label.font = .systemFont(ofSize: 12)
        label.maximumNumberOfLines = 3; label.lineBreakMode = .byTruncatingTail
        view.addSubview(label); contentView = view
    }
    func show(_ message: String, seconds: TimeInterval = 5) {
        label.stringValue = message; label.toolTip = message
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let width: CGFloat = 360
        let height = min(72, max(44, label.sizeThatFits(NSSize(width: width - 32, height: 72)).height + 24))
        setFrame(NSRect(x: visible.midX - width / 2, y: visible.minY + 80, width: width, height: height), display: false)
        contentView?.frame = NSRect(x: 0, y: 0, width: width, height: height)
        label.frame = NSRect(x: 16, y: 12, width: width - 32, height: height - 24)
        orderFrontRegardless()
        generation += 1; let token = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.generation == token else { return }
            self.close(); self.closed()
        }
    }
}
