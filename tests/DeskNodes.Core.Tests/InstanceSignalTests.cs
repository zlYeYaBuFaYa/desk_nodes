using System.IO.Pipes;
using DeskNodes.Core.Services;

namespace DeskNodes.Core.Tests;

public sealed class InstanceSignalTests
{
    private sealed class UnpumpedContext : SynchronizationContext
    {
        public override void Post(SendOrPostCallback callback, object? state) { }
    }

    [Fact]
    public async Task BlockingCallerWithUnpumpedContextCompletesWithinBound()
    {
        string name = "DeskNodes-test-" + Guid.NewGuid().ToString("N");
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var caller = Task.Run(() =>
        {
            SynchronizationContext.SetSynchronizationContext(new UnpumpedContext());
            try
            {
                var signal = InstanceSignal.SendAsync(name, 1000);
                started.SetResult();
                signal.GetAwaiter().GetResult();
                return true;
            }
            catch (TimeoutException)
            {
                return false;
            }
            finally
            {
                SynchronizationContext.SetSynchronizationContext(null);
            }
        });
        await started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await Task.Delay(50);
        using var server = new NamedPipeServerStream(name, PipeDirection.In, 1,
            PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        await server.WaitForConnectionAsync().WaitAsync(TimeSpan.FromSeconds(3));
        var bytes = new byte[1];
        Assert.Equal(1, await server.ReadAsync(bytes).AsTask().WaitAsync(TimeSpan.FromSeconds(3)));
        Assert.Equal(1, bytes[0]);
        Assert.True(await caller.WaitAsync(TimeSpan.FromSeconds(3)));
    }

    [Fact]
    public async Task MissingServerTimesOutWithoutContextPump()
    {
        var caller = Task.Run(() =>
        {
            SynchronizationContext.SetSynchronizationContext(new UnpumpedContext());
            try
            {
                Assert.Throws<TimeoutException>(() => InstanceSignal.SendAsync(Guid.NewGuid().ToString("N"), 100).GetAwaiter().GetResult());
            }
            finally
            {
                SynchronizationContext.SetSynchronizationContext(null);
            }
        });
        await caller.WaitAsync(TimeSpan.FromSeconds(3));
    }
}
