using DeskNodes.App.Interop;
using DeskNodes.Core.Services;

namespace DeskNodes.App.Platform;

/// <summary>Candidate leases keep the old registration alive until persistence succeeds.</summary>
internal sealed class HotkeyService(nint window) : IHotkeyRegistrationService, IDisposable
{
    internal sealed record Binding(int Id, HotkeyGesture Gesture);
    private readonly Dictionary<HotkeyAction, Binding> bindings = [];
    private readonly nint handle = window;
    private const int MaximumHotkeyId = 0xBFFF;
    private int nextId;
    private readonly Dictionary<HotkeyAction, HotkeyRegistration> registrations = [];
    private static HotkeyAction Other(HotkeyAction action) => action == HotkeyAction.NewNote ? HotkeyAction.Raise : HotkeyAction.NewNote;
    public HotkeyRegistration GetRegistration(HotkeyAction action) => registrations.GetValueOrDefault(action, new(null, HotkeyRegistrationStatus.Cleared));
    public void MarkConflict(HotkeyAction action, string text)
    {
        if (bindings.Remove(action, out var old))
            NativeMethods.UnregisterHotKey(handle, old.Id);
        registrations[action] = new(text, HotkeyRegistrationStatus.Conflict);
    }
    public bool Recording { get; set; }
    public event Action<HotkeyAction>? Invoked;
    public event Action<string>? Recorded;
    public void Dispatch(int id)
    {
        var match = bindings.FirstOrDefault(pair => pair.Value.Id == id);
        if (match.Value is null)
            return;
        if (Recording)
            Recorded?.Invoke(match.Value.Gesture.ToString());
        else
            Invoked?.Invoke(match.Key);
    }
    public bool IsRegistered(HotkeyGesture gesture) => bindings.Values.Any(binding => binding.Gesture == gesture);
    IHotkeyCandidate IHotkeyRegistrationService.Prepare(HotkeyAction action, string? text) => Prepare(action, text);
    public Candidate Prepare(HotkeyAction action, string? text)
    {
        var gesture = text is null ? null : HotkeyGesture.Parse(text);
        bindings.TryGetValue(action, out var old);
        if (gesture == old?.Gesture)
            return new(this, action, old, false);
        Binding? candidate = null;
        if (gesture is not null)
        {
            if (bindings.TryGetValue(Other(action), out var other) && other.Gesture == gesture)
                return new(this, action, other, true, borrowed: true);
            do
            {
                nextId = nextId % MaximumHotkeyId + 1;
            }
            while (bindings.Values.Any(binding => binding.Id == nextId));
            int id = nextId;
            if (!NativeMethods.RegisterHotKey(handle, id, (uint)gesture.Modifiers | NativeMethods.MOD_NOREPEAT, gesture.VirtualKey))
                throw new InvalidOperationException("此快捷键已被系统或其他应用占用，原快捷键已保留。");
            candidate = new(id, gesture);
        }
        return new(this, action, candidate, true);
    }
    internal sealed class Candidate : IHotkeyCandidate
    {
        private readonly HotkeyService owner;
        private readonly HotkeyAction action;
        private readonly Binding? binding;
        private bool pending;
        private readonly bool borrowed;
        internal Candidate(HotkeyService owner, HotkeyAction action, Binding? binding, bool pending, bool borrowed = false)
            => (this.owner, this.action, this.binding, this.pending, this.borrowed) = (owner, action, binding, pending, borrowed);
        public void Commit()
        {
            if (!pending)
            {
                owner.registrations[action] = new(binding?.Gesture.ToString(), binding is null ? HotkeyRegistrationStatus.Cleared : HotkeyRegistrationStatus.Active);
                return;
            }
            // Import may exchange the two gestures. Transfer an already-owned registration only after backup succeeds.
            if (borrowed)
            {
                owner.bindings.Remove(Other(action));
                owner.registrations[Other(action)] = new(null, HotkeyRegistrationStatus.Cleared);
            }
            if (owner.bindings.Remove(action, out var old))
                NativeMethods.UnregisterHotKey(owner.handle, old.Id);
            if (binding is not null)
                owner.bindings[action] = binding;
            owner.registrations[action] = new(binding?.Gesture.ToString(), binding is null ? HotkeyRegistrationStatus.Cleared : HotkeyRegistrationStatus.Active);
            pending = false;
        }
        public void Dispose()
        {
            if (pending && !borrowed && binding is not null)
                NativeMethods.UnregisterHotKey(owner.handle, binding.Id);
            pending = false;
        }
    }
    public void Dispose()
    {
        foreach (var binding in bindings.Values)
            NativeMethods.UnregisterHotKey(handle, binding.Id);
        bindings.Clear();
    }
}
