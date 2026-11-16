using System.Text;
using System.Text.Json;

namespace DeskNodes.Core.Backup;

public enum BackupLimit { FileBytes, StringLength, CollectionEntries, Depth }

public sealed class BackupLimitException(BackupLimit limit, string message) : IOException(message)
{
    public BackupLimit Limit { get; } = limit;
}

public static partial class WindowsBackupCodec
{
    public const int MaxFileBytes = 64 * 1024 * 1024;
    public const int MaxStringLength = 1024 * 1024;
    public const int MaxCollectionEntries = 100_000;
    public const int MaxDepth = 16;

    public static WindowsBackup Parse(string json)
    {
        ArgumentNullException.ThrowIfNull(json);
        if (Encoding.UTF8.GetByteCount(json) > MaxFileBytes)
            throw FileLimit();
        using var stream = new MemoryStream(Encoding.UTF8.GetBytes(json), writable: false);
        return Parse(stream);
    }

    /// <summary>Leaves the input open. Checks tokens as bytes arrive, before allocating DTO collections.</summary>
    public static WindowsBackup Parse(Stream stream)
    {
        ArgumentNullException.ThrowIfNull(stream);
        using var buffer = new MemoryStream();
        var chunk = new byte[64 * 1024];
        var state = new JsonReaderState(new JsonReaderOptions { MaxDepth = MaxDepth + 1 });
        var arrays = new bool[MaxDepth];
        var counts = new int[MaxDepth];
        int consumed = 0;
        int start = 0;
        while (true)
        {
            // Read one byte beyond the boundary to distinguish an exact-size input from an oversized stream.
            int read = stream.Read(chunk, 0, Math.Min(chunk.Length, MaxFileBytes - (int)buffer.Length + 1));
            if (buffer.Length + read > MaxFileBytes)
                throw FileLimit();
            buffer.Write(chunk, 0, read);
            if (buffer.Length < 3 && read != 0)
                continue;
            if (consumed == 0 && buffer.Length >= 3 && buffer.GetBuffer().AsSpan(0, 3).SequenceEqual("\uFEFF"u8))
                consumed = start = 3;
            var reader = new Utf8JsonReader(buffer.GetBuffer().AsSpan(consumed, (int)buffer.Length - consumed), read == 0, state);
            while (reader.Read())
            {
                int depth = reader.CurrentDepth;
                bool container = reader.TokenType is JsonTokenType.StartArray or JsonTokenType.StartObject;
                bool value = container || reader.TokenType is JsonTokenType.String or JsonTokenType.Number or
                    JsonTokenType.True or JsonTokenType.False or JsonTokenType.Null;
                if (container && depth >= MaxDepth)
                    throw new BackupLimitException(BackupLimit.Depth, $"备份嵌套层数不能超过 {MaxDepth} 层。");
                if (value && depth > 0 && arrays[depth - 1] && ++counts[depth - 1] > MaxCollectionEntries)
                    throw new BackupLimitException(BackupLimit.CollectionEntries, $"备份每个集合不能超过 {MaxCollectionEntries} 条。");
                if (container)
                {
                    arrays[depth] = reader.TokenType == JsonTokenType.StartArray;
                    counts[depth] = 0;
                }
                if (reader.TokenType is JsonTokenType.String or JsonTokenType.PropertyName &&
                    (reader.ValueSpan.Length > 6L * MaxStringLength || reader.GetString()!.Length > MaxStringLength))
                    throw new BackupLimitException(BackupLimit.StringLength, $"备份单个字符串不能超过 {MaxStringLength} 个 UTF-16 代码单元。");
            }
            consumed += (int)reader.BytesConsumed;
            state = reader.CurrentState;
            if (read == 0)
                break;
        }
        var backup = JsonSerializer.Deserialize<WindowsBackup>(buffer.GetBuffer().AsSpan(start, (int)buffer.Length - start), JsonOptions)
            ?? throw new InvalidDataException("备份内容为空。");
        ValidateHeader(backup);
        return backup;
    }

    private static BackupLimitException FileLimit() => new(BackupLimit.FileBytes, "备份文件不能超过 64 MiB。");
}
