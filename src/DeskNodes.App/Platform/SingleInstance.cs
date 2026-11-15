using System.IO;
using System.IO.Pipes;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace DeskNodes.App.Platform;

internal sealed class SingleInstance : IDisposable
{
    private readonly Mutex mutex;
    private readonly string name;
    private readonly CancellationTokenSource cancellation = new();
    private readonly bool owner;
    public SingleInstance(string directory)
    {
        string identity = "DeskNodes-" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Path.GetFullPath(directory).ToUpperInvariant())));
        using var process = System.Diagnostics.Process.GetCurrentProcess();
        name = identity + "-" + process.SessionId;
        mutex = new Mutex(true, "Local\\" + identity, out owner);
    }
    public bool IsFirst => owner;
    public async Task SignalAsync()
    {
        using var pipe = new NamedPipeClientStream(".", name, PipeDirection.Out, PipeOptions.CurrentUserOnly | PipeOptions.Asynchronous);
        await pipe.ConnectAsync(5000);
        await pipe.WriteAsync(new byte[] { 1 });
    }
    public async Task ListenAsync(Action show, Action<Exception> failed)
    {
        var token = cancellation.Token;
        try
        {
            while (!token.IsCancellationRequested)
            {
                await using var pipe = new NamedPipeServerStream(name, PipeDirection.In, 1, PipeTransmissionMode.Byte,
                    PipeOptions.CurrentUserOnly | PipeOptions.Asynchronous);
                await pipe.WaitForConnectionAsync(token);
                try
                {
                    byte[] message = new byte[1];
                    if (await pipe.ReadAsync(message, token) == 1 && message[0] == 1) show();
                }
                catch (IOException ex) { failed(ex); }
            }
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { failed(ex); }
    }
    public void Dispose()
    {
        cancellation.Cancel();
        if (owner) mutex.ReleaseMutex();
        mutex.Dispose();
        cancellation.Dispose();
    }
}
