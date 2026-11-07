import AppKit
import QuartzCore
import DeskNodesActions
import DeskNodesPersistence

extension NotePanel {
    func applyLevel() {
        switch modes.effective(choice, temporarilyRaised: temporarilyRaised) {
        case .desktop: level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .ordinary: level = .normal
        case .topmost: level = .floating
        }
    }
    func present(_ expanded: NoteFrame, collapsed: Bool, animate: Bool) {
        expandedFrame = expanded
        let target = expanded.presenting(collapsed: collapsed)
        let oldHeight = frame.height
        setFrame(NSRect(x: target.x, y: target.y, width: target.width, height: target.height), display: true)
        guard animate, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              oldHeight != frame.height, let layer = contentView?.layer else { return }
        let spring = CASpringAnimation(keyPath: "bounds.size.height")
        spring.fromValue = oldHeight; spring.toValue = frame.height
        spring.mass = 1; spring.stiffness = 300; spring.damping = 27; spring.duration = 0.30
        layer.add(spring, forKey: "noteSize")
    }
}

/// Header background and lower corner own gestures; editors keep native input handling.
final class NoteGestureView: NSView {
    var resize = false
    var finish: ((NoteFrame, Bool) -> Void)?
    override func mouseDown(with event: NSEvent) {
        guard let panel = window as? NotePanel, let original = panel.expandedFrame else { return }
        if resize && panel.frame.height == 32 { return }
        let start = NSEvent.mouseLocation
        var result = original
        while let next = panel.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = NSEvent.mouseLocation
            let dx = point.x - start.x, dy = point.y - start.y
            if resize {
                result = (try? NoteFrame(x: original.x, y: original.y + dy,
                    width: original.width + dx, height: original.height - dy).bounded()) ?? original
                result.y = original.y + original.height - result.height
            } else { result.x = original.x + dx; result.y = original.y + dy }
            panel.present(result, collapsed: panel.frame.height == 32, animate: false)
            if next.type == .leftMouseUp { break }
        }
        finish?(result, resize)
    }
    override func draw(_ dirtyRect: NSRect) {
        guard resize else { return }
        NoteTheme.secondary.withAlphaComponent(0.35).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.width - 9, y: 3))
        path.line(to: NSPoint(x: bounds.width - 3, y: 9)); path.lineWidth = 1; path.stroke()
    }
}
