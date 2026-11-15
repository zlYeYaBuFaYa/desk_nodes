namespace DeskNodes.Core.Presentation;

public enum ToolbarIdleState { Expanded, Collapsing, Round, Expanding }
public enum ToolbarIdleAction { None, StartShrinkToHome, StartShrinkInPlace, StartExpand }
public sealed record IdleInput(bool PointerInside = false, bool Dragging = false, bool Pressed = false,
    bool Animating = false, bool SettingsVisible = false, bool MenuOpen = false,
    bool KeepExpanded = false, AutoShrink AutoShrink = AutoShrink.Seconds15,
    bool Operated = false, bool Clicked = false, bool AnimationCompleted = false,
    bool AtHome = false, long? AnimationGeneration = null);
public readonly record struct IdleOutput(ToolbarIdleAction Action, TimeSpan? NextWake, long Generation);

/// <summary>Caller supplies monotonic time. Echo output Generation in animation callbacks to ignore superseded transitions.</summary>
public sealed class ToolbarIdleMachine
{
    public ToolbarIdleState State { get; private set; } = ToolbarIdleState.Expanded;
    public long Generation { get; private set; }
    public bool PendingExpand { get; private set; }
    private TimeSpan? deadline;
    private TimeSpan? hoverDeadline;
    private TimeSpan lastTime;
    private bool hoverOnly;
    private bool previousInside;
    private bool returning;
    private bool grace;
    private AutoShrink previousAutoShrink = AutoShrink.Seconds15;

    public IdleOutput Update(TimeSpan now, IdleInput input)
    {
        if (now < lastTime) throw new ArgumentOutOfRangeException(nameof(now), "时间必须单调递增。");
        lastTime = now;
        if (!Enum.IsDefined(input.AutoShrink)) input = input with { AutoShrink = AutoShrink.Seconds15 };
        if (input.AutoShrink != previousAutoShrink) deadline = null;
        previousAutoShrink = input.AutoShrink;
        ToolbarIdleAction Expand(bool fromHover)
        {
            State = ToolbarIdleState.Expanding;
            Generation++;
            hoverOnly = fromHover;
            grace = false;
            deadline = hoverDeadline = null;
            PendingExpand = false;
            return ToolbarIdleAction.StartExpand;
        }
        ToolbarIdleAction action = ToolbarIdleAction.None;
        if (input.Operated || input.Clicked) { hoverOnly = grace = false; deadline = null; }
        if (hoverOnly && previousInside && !input.PointerInside && State == ToolbarIdleState.Expanding)
            grace = true;
        if (input.AnimationCompleted && (input.AnimationGeneration is null || input.AnimationGeneration == Generation))
        {
            if (State == ToolbarIdleState.Collapsing)
            {
                State = ToolbarIdleState.Round;
                if (PendingExpand && input.PointerInside && !input.Dragging && !input.Pressed) action = Expand(true);
                PendingExpand = false;
            }
            else if (State == ToolbarIdleState.Expanding) State = ToolbarIdleState.Expanded;
            deadline = null;
        }
        if (input.AutoShrink == AutoShrink.Off || input.KeepExpanded)
        {
            deadline = hoverDeadline = null;
            if (State is ToolbarIdleState.Round or ToolbarIdleState.Collapsing) action = Expand(false);
        }
        else if (State == ToolbarIdleState.Collapsing)
        {
            PendingExpand = input.PointerInside && !input.Dragging && !input.Pressed;
            if (input.Clicked || (PendingExpand && !returning)) action = Expand(!input.Clicked);
        }
        else if (State == ToolbarIdleState.Round)
        {
            bool hover = input.PointerInside && !input.Dragging && !input.Pressed;
            if (!hover) hoverDeadline = null;
            else hoverDeadline ??= now + TimeSpan.FromMilliseconds(140);
            if (input.Clicked || input.Operated || (hoverDeadline is { } h && now >= h)) action = Expand(!input.Clicked && !input.Operated);
        }
        if (State == ToolbarIdleState.Expanded)
        {
            bool eligible = !input.PointerInside && !input.Dragging && !input.Pressed && !input.Animating &&
                !input.SettingsVisible && !input.MenuOpen && !input.KeepExpanded && input.AutoShrink != AutoShrink.Off;
            if (hoverOnly && previousInside && !input.PointerInside) grace = true;
            if (!eligible) deadline = null;
            else
            {
                deadline ??= now + (grace ? TimeSpan.FromSeconds(1.5) : TimeSpan.FromSeconds((int)input.AutoShrink));
                if (now >= deadline)
                {
                    returning = !input.AtHome;
                    State = ToolbarIdleState.Collapsing;
                    Generation++;
                    action = returning ? ToolbarIdleAction.StartShrinkToHome : ToolbarIdleAction.StartShrinkInPlace;
                    deadline = null;
                    hoverOnly = grace = false;
                }
            }
        }
        previousInside = input.PointerInside;
        return new(action, State == ToolbarIdleState.Round ? hoverDeadline : deadline, Generation);
    }
}
