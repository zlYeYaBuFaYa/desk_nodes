using System.IO.Pipes;

namespace DeskNodes.Core.Services;

/// <summary>Pipe communication must complete without dispatching to the caller's synchronization context.</summary>
public static class InstanceSignal
{
    public static async Task SendAsync(string name, int timeoutMilliseconds = 5000)
    {
        using var pipe = new NamedPipeClientStream(".", name, PipeDirection.Out,
            PipeOptions.CurrentUserOnly | PipeOptions.Asynchronous);
        await pipe.ConnectAsync(timeoutMilliseconds).ConfigureAwait(false);
        await pipe.WriteAsync(new byte[] { 1 }).ConfigureAwait(false);
    }
}
