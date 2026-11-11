import AppKit
import QuartzCore
import DeskNodesCore
import DeskNodesActions
import DeskNodesPersistence

/// Short, linear-path, ease-out motion. Reduce Motion drops movement entirely.
@MainActor
enum Motion {
    static let easeOut = CAMediaTimingFunction(controlPoints: 0.2, 0.0, 0.2, 1.0)
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    static func basic(_ keyPath: String, from: Any, to: Any) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from; animation.toValue = to
        return animation
    }
    /// Moves real windows (not snapshots) between frames, optionally fading. Frames are
    /// committed by AppKit as the animation runs, so hit testing always matches the pixels.
    static func windows(_ moves: [(NSWindow, NSRect, CGFloat)], duration: Double, completion: @escaping () -> Void) {
        guard !moves.isEmpty else { completion(); return }
        let reduce = reduced
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = reduce ? MotionPolicy.reducedFade : duration
            context.timingFunction = easeOut
            context.allowsImplicitAnimation = false
            for (window, frame, alpha) in moves {
                if reduce { window.setFrame(frame, display: true) } else { window.animator().setFrame(frame, display: true) }
                window.animator().alphaValue = alpha
            }
        }, completionHandler: completion)
    }
}

extension NSWindow {
    /// Only a topmost note follows into another app's fullscreen space, where it floats
    /// above that app; lower notes would sit hidden behind it, so they stay out.
    func applyNoteLevel(_ effective: WindowLevel) {
        switch effective {
        case .desktop: level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        case .ordinary: level = .normal
        case .topmost: level = .floating
        }
        collectionBehavior = [.canJoinAllSpaces, effective == .topmost ? .fullScreenAuxiliary : .fullScreenNone]
    }
}

extension NotePanel {
    func applyLevel() { applyNoteLevel(modes.effective(choice, temporarilyRaised: temporarilyRaised)) }
    func present(_ expanded: NoteFrame, collapsed: Bool, animate: Bool) {
        expandedFrame = expanded
        let target = expanded.presenting(collapsed: collapsed)
        let oldHeight = frame.height
        setFrame(NSRect(x: target.x, y: target.y, width: target.width, height: target.height), display: true)
        restingFrame = frame
        guard animate, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              oldHeight != frame.height, let layer = contentView?.layer else { return }
        let resize = Motion.basic("bounds.size.height", from: oldHeight, to: frame.height)
        resize.duration = MotionPolicy.arrangement; resize.timingFunction = Motion.easeOut
        layer.add(resize, forKey: "noteSize")
    }
}

/// Header background and lower corner own gestures; editors keep native input handling.
final class NoteGestureView: NSView {
    var resize = false
    /// A compact 2x3 dot grip centred in the top row signals where to drag.
    var showsGrip = false { didSet { if showsGrip != oldValue { needsDisplay = true } } }
    var finish: ((NoteFrame, Bool) -> Void)?
    override func mouseDown(with event: NSEvent) {
        guard let panel = window as? NotePanel, let original = panel.expandedFrame,
              (panel.contentView as? NoteCardView)?.canMutate() != false else { return }
        if resize && (panel.frame.height == 32 || panel.docked) { return }
        let start = NSEvent.mouseLocation
        var result = original
        var moved = false
        var released = false
        let collapsed = panel.frame.height == 32
        while let next = panel.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = NSEvent.mouseLocation
            let dx = point.x - start.x, dy = point.y - start.y
            if resize {
                result = (try? NoteFrame(x: original.x, y: original.y + dy,
                    width: original.width + dx, height: original.height - dy).bounded()) ?? original
                result.y = original.y + original.height - result.height
            } else { result.x = original.x + dx; result.y = original.y + dy }
            if !moved && hypot(dx, dy) >= 4 { moved = true; if !resize { panel.dragBegin?() } }
            if moved {
                panel.present(result, collapsed: collapsed, animate: false)
                if !resize { panel.dragUpdate?(result, point) }
            }
            if next.type == .leftMouseUp { released = true; break }
        }
        guard moved else { return }
        guard released else { panel.dragCancel?(); return }
        if !resize, let end = panel.dragEnd { end(result, NSEvent.mouseLocation) }
        else { finish?(result, resize) }
    }
    override func draw(_ dirtyRect: NSRect) {
        if !resize {
            guard showsGrip else { return }
            NoteTheme.tertiary.setFill()
            for row in 0..<2 {
                for column in 0..<3 {
                    let x = bounds.midX - 7 + CGFloat(column) * 5.5, y = bounds.maxY - 9 - CGFloat(row) * 5
                    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 3, height: 3)).fill()
                }
            }
            return
        }
        NoteTheme.secondary.withAlphaComponent(0.35).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.width - 9, y: 3))
        path.line(to: NSPoint(x: bounds.width - 3, y: 9)); path.lineWidth = 1; path.stroke()
    }
}
