namespace DeskNodes.Core.Services;

/// <summary>Storage and services must be ready before invoking these ordered startup phases.</summary>
public static class StartupSequence
{
    public static void Run<T>(Func<T> advanceBusinessDay, Action createWindows, Action<T> present)
    {
        T result = advanceBusinessDay();
        createWindows();
        present(result);
    }
}
