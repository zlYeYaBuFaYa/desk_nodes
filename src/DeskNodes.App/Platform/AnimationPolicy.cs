using DeskNodes.App.Interop;

namespace DeskNodes.App.Platform;

internal sealed class AnimationPolicy(Func<bool> userReduceMotion)
{
    private bool systemReduced = true;
    public bool ReducedMotion => userReduceMotion() || systemReduced;
    public void Refresh() => systemReduced = !NativeMethods.SystemParametersInfo(
        NativeMethods.SPI_GETCLIENTAREAANIMATION, 0, out int enabled, 0) || enabled == 0;
}
