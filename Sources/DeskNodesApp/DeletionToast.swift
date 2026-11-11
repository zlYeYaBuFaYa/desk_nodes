import AppKit
import QuartzCore

private final class ToastSurface: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(sRGBHex: "2A2A2D").setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 22, yRadius: 22).fill()
    }
}

/// Separate bottom toast survives deleting the last note. No editor undo manager is replaced.
final class DeletionToast: NSPanel {
    private let restore: () -> Void
    private let label = NSTextField(labelWithString: "已删除 · 5 秒内可撤销")
    init(restore: @escaping () -> Void) {
        self.restore = restore
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        super.init(contentRect: NSRect(x: visible.midX - 130, y: visible.minY + 24, width: 260, height: 44),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenNone]
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear; hasShadow = true
        let view = ToastSurface(frame: NSRect(x: 0, y: 0, width: 260, height: 44))
        view.wantsLayer = true
        label.textColor = NSColor(sRGBHex: "EDEBE6")
        label.font = .systemFont(ofSize: 12); label.frame = NSRect(x: 14, y: 13, width: 165, height: 18)
        let button = NSButton(title: "撤销", target: self, action: #selector(undoDeletion))
        button.setAccessibilityLabel("撤销删除")
        button.contentTintColor = .white
        button.isBordered = false; button.frame = NSRect(x: 190, y: 8, width: 56, height: 28)
        view.addSubview(label); view.addSubview(button); contentView = view
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let spring = CASpringAnimation(keyPath: "transform.translation.y")
            spring.fromValue = -8; spring.toValue = 0
            spring.mass = 1; spring.stiffness = 300; spring.damping = 27; spring.duration = 0.30
            view.layer?.add(spring, forKey: "toastInsertion")
        }
    }
    /// Several deletions inside the window are undone newest first, one per click / ⌘Z.
    func update(count: Int) {
        label.stringValue = count > 1 ? "已删除 \(count) 项 · 可逐项撤销" : "已删除 · 5 秒内可撤销"
    }
    func dismiss() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let layer = contentView?.layer else { close(); return }
        ignoresMouseEvents = true
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1; fade.toValue = 0; fade.duration = 0.30
        fade.fillMode = .forwards; fade.isRemovedOnCompletion = false
        layer.add(fade, forKey: "toastDismissal")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { self.close() }
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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenNone] // only the reveal panel may cover fullscreen apps
        level = .floating
        isReleasedWhenClosed = false; isOpaque = false; backgroundColor = .clear; hasShadow = true
        let view = ToastSurface(frame: .zero)
        label.textColor = NSColor(sRGBHex: "EDEBE6"); label.font = .systemFont(ofSize: 12)
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
