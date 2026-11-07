/// Shared native presentation policy: passive copies may receive committed text,
/// but only the owning first responder may flush an unnotified local edit.
public enum EditorSynchronization {
    public static func receive(local: String, committed: String, active: Bool, marked: Bool) -> Bool {
        local != committed && !active && !marked
    }
    public static func flush(local: String, committed: String, active: Bool, marked: Bool) -> Bool {
        local != committed && active && !marked
    }
}
