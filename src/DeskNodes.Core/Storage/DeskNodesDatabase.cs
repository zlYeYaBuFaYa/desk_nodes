using Microsoft.Data.Sqlite;

namespace DeskNodes.Core.Storage;

/// <summary>Owns one connection. Callbacks are synchronous and serialized; nested writes use savepoints.</summary>
public sealed class DeskNodesDatabase : IDisposable
{
    // SQLite application_id: ASCII "DSKN", identifying the independent Windows file format.
    public const int ApplicationId = 0x44534B4E;
    public const int SchemaVersion = 1;
    private readonly SqliteConnection connection;
    private readonly object gate = new();
    private int transactionDepth;
    private long nextSavepoint;
    private bool disposed;
    private readonly List<(Action Callback, bool? Commit)> completions = [];

    private DeskNodesDatabase(SqliteConnection connection) => this.connection = connection;

    public static DeskNodesDatabase Open(string databasePath)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(databasePath);
        string fullPath = Path.GetFullPath(databasePath);
        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
        var connection = new SqliteConnection(new SqliteConnectionStringBuilder
        {
            DataSource = fullPath,
            Mode = SqliteOpenMode.ReadWriteCreate,
            Pooling = false,
            DefaultTimeout = 5
        }.ToString());
        try
        {
            connection.Open();
            Execute(connection, "PRAGMA busy_timeout=5000; PRAGMA foreign_keys=ON;");
            ValidateIdentity(connection);
            Execute(connection, "PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;");
            Execute(connection, "BEGIN EXCLUSIVE;");
            try
            {
                bool empty = ValidateIdentity(connection);
                if (empty)
                {
                    Execute(connection, Schema.Version1);
                    Execute(connection, $"PRAGMA application_id={ApplicationId}; PRAGMA user_version={SchemaVersion};");
                }
                Execute(connection, "COMMIT;");
            }
            catch
            {
                Execute(connection, "ROLLBACK;");
                throw;
            }
            return new DeskNodesDatabase(connection);
        }
        catch
        {
            connection.Dispose();
            throw;
        }
    }

    private static bool ValidateIdentity(SqliteConnection connection)
    {
        long applicationId = Scalar(connection, "PRAGMA application_id;");
        long version = Scalar(connection, "PRAGMA user_version;");
        long objects = Scalar(connection, "SELECT count(*) FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%';");
        bool empty = objects == 0 && version == 0 && (applicationId == 0 || applicationId == ApplicationId);
        if (empty)
            return true;
        if (applicationId != ApplicationId)
            throw new DatabaseCompatibilityException(DatabaseCompatibilityFailure.ForeignDatabase,
                $"数据库不是 DeskNodes Windows 数据库（application_id={applicationId}）。原文件未被替换。");
        if (version > SchemaVersion)
            throw new DatabaseCompatibilityException(DatabaseCompatibilityFailure.FutureVersion,
                $"数据库版本 {version} 高于此应用支持的版本 {SchemaVersion}，请使用更新的 DeskNodes。");
        if (version != SchemaVersion || objects == 0)
            throw new DatabaseCompatibilityException(DatabaseCompatibilityFailure.UnsupportedSchema,
                $"不支持的 DeskNodes 数据库结构（版本 {version}）。请保留原文件进行恢复。");
        return false;
    }

    /// <summary>The connection must not escape the callback; do not await or manage transactions in it.</summary>
    public T Read<T>(Func<SqliteConnection, T> read)
    {
        ArgumentNullException.ThrowIfNull(read);
        lock (gate)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            return read(connection);
        }
    }

    public void Transaction(Action<SqliteConnection> action)
    {
        ArgumentNullException.ThrowIfNull(action);
        Transaction(connection => { action(connection); return 0; });
    }

    public T Transaction<T>(Func<SqliteConnection, T> action)
    {
        ArgumentNullException.ThrowIfNull(action);
        List<Action> callbacks = [];
        Exception? transactionFailure = null;
        try
        {
            lock (gate)
            {
                ObjectDisposedException.ThrowIf(disposed, this);
                bool outer = transactionDepth == 0;
                int start = completions.Count;
                bool committed = false;
                string savepoint = $"desknodes_{++nextSavepoint}";
                Execute(connection, outer ? "BEGIN IMMEDIATE;" : $"SAVEPOINT {savepoint};");
                transactionDepth++;
                try
                {
                    T result = action(connection);
                    Execute(connection, outer ? "COMMIT;" : $"RELEASE SAVEPOINT {savepoint};");
                    committed = true;
                    return result;
                }
                catch (Exception original)
                {
                    try
                    {
                        Execute(connection, outer ? "ROLLBACK;" :
                            $"ROLLBACK TO SAVEPOINT {savepoint}; RELEASE SAVEPOINT {savepoint};");
                    }
                    catch (SqliteException rollback)
                    {
                        throw new AggregateException("事务执行及回滚均失败，请关闭数据库后重试。", original, rollback);
                    }
                    throw;
                }
                finally
                {
                    transactionDepth--;
                    if (outer)
                    {
                        callbacks = completions.Where(c => c.Commit is null || c.Commit == committed).Select(c => c.Callback).ToList();
                        completions.Clear();
                    }
                    else if (!committed)
                    {
                        // A caught savepoint failure must never acknowledge its writes at outer commit.
                        for (int i = completions.Count - 1; i >= start; i--)
                        {
                            var entry = completions[i];
                            if (entry.Commit == true)
                                completions.RemoveAt(i);
                            else
                                completions[i] = (entry.Callback, null);
                        }
                    }
                }
            }
        }
        catch (Exception exception)
        {
            transactionFailure = exception;
            throw;
        }
        finally
        {
            List<Exception> failures = [];
            foreach (var callback in callbacks)
            {
                try { callback(); }
                catch (Exception exception) { failures.Add(exception); }
            }
            if (failures.Count != 0)
            {
                if (transactionFailure is not null)
                    failures.Insert(0, transactionFailure);
                throw new AggregateException("事务完成回调失败。", failures);
            }
        }
    }

    public void OnOuterCommitted(Action callback) => OnCompletion(callback, commit: true);
    public void OnOuterRolledBack(Action callback) => OnCompletion(callback, commit: false);

    private void OnCompletion(Action callback, bool commit)
    {
        ArgumentNullException.ThrowIfNull(callback);
        lock (gate)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (transactionDepth != 0)
            {
                completions.Add((callback, commit));
                return;
            }
        }
        if (commit)
            callback();
    }

    /// <summary>Replaces the live database using SQLite's atomic online backup transaction.</summary>
    public void ReplaceFrom(DeskNodesDatabase staging)
    {
        ArgumentNullException.ThrowIfNull(staging);
        if (ReferenceEquals(this, staging))
            throw new ArgumentException("不能从同一个数据库导入。", nameof(staging));
        lock (gate)
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (transactionDepth != 0)
                throw new InvalidOperationException("导入不能在外层事务中执行。");
            staging.Read(source =>
            {
                source.BackupDatabase(connection);
                return 0;
            });
        }
    }

    internal static void Execute(SqliteConnection connection, string sql)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        command.ExecuteNonQuery();
    }

    private static long Scalar(SqliteConnection connection, string sql)
    {
        using var command = connection.CreateCommand();
        command.CommandText = sql;
        return Convert.ToInt64(command.ExecuteScalar(), System.Globalization.CultureInfo.InvariantCulture);
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (disposed)
                return;
            if (transactionDepth != 0)
                throw new InvalidOperationException("不能在事务内关闭数据库。");
            connection.Dispose();
            disposed = true;
        }
    }
}
