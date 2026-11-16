using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using DeskNodes.Core.Backup;
using DeskNodes.Core.Storage;
using static DeskNodes.Core.Tests.TestData;

namespace DeskNodes.Core.Tests;

public sealed class BackupParsingTests
{
    private static string Golden => File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "backup-v1.json"));

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    public void ActualStreamByteLimitIncludesTrailingWhitespaceAndFailurePreservesLive(int extra)
    {
        using var directory = new TestDirectory();
        using var live = directory.Open();
        var original = Note();
        new NoteRepository(live).Insert(original);
        using var stream = new InputStream(Golden, WindowsBackupCodec.MaxFileBytes + extra);
        if (extra == 0)
        {
            var backup = WindowsBackupCodec.Parse(stream);
            using var stage = WindowsBackupCodec.Stage(backup, Path.Combine(directory.DirectoryPath, "stage.sqlite3"));
            Assert.Single(new NoteRepository(stage).GetNotes(true));
        }
        else
        {
            var error = Assert.Throws<BackupLimitException>(() =>
            {
                var backup = WindowsBackupCodec.Parse(stream);
                using var stage = WindowsBackupCodec.Stage(backup, Path.Combine(directory.DirectoryPath, "stage.sqlite3"));
                live.ReplaceFrom(stage);
            });
            Assert.Equal(BackupLimit.FileBytes, error.Limit);
        }
        Assert.Equal(WindowsBackupCodec.MaxFileBytes + extra, stream.BytesRead);
        Assert.True(stream.CanRead);
        Assert.Equal(original, Assert.Single(new NoteRepository(live).GetNotes()));
    }

    [Theory]
    [InlineData(0, false)]
    [InlineData(1, false)]
    [InlineData(0, true)]
    [InlineData(1, true)]
    public void DecodedStringLimitHandlesMultibyteAndEscapedTokensAcrossReads(int extra, bool escaped)
    {
        var root = JsonNode.Parse(Golden)!;
        string title = new(escaped ? '中' : 'x', WindowsBackupCodec.MaxStringLength + extra);
        root["notes"]![0]!["title"] = title;
        string json = root.ToJsonString();
        using var stream = new InputStream(json);
        if (extra == 0)
            Assert.Equal(title, Assert.Single(WindowsBackupCodec.Parse(stream).Notes).Title);
        else
            Assert.Equal(BackupLimit.StringLength, Assert.Throws<BackupLimitException>(() => WindowsBackupCodec.Parse(stream)).Limit);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    public void CollectionLimitIsPerArrayAndCheckedBeforeDtoAllocation(int extra)
    {
        var root = JsonNode.Parse(Golden)!;
        string rows = string.Join(',', Enumerable.Repeat("{\"rollover_minutes\":240}", WindowsBackupCodec.MaxCollectionEntries + extra));
        root.AsObject().Remove("business_settings");
        string json = root.ToJsonString();
        json = json[..^1] + ",\"business_settings\":[" + rows + "]}";
        using var stream = new InputStream(json);
        if (extra == 0)
            Assert.Equal(WindowsBackupCodec.MaxCollectionEntries, WindowsBackupCodec.Parse(stream).BusinessSettings.Count);
        else
            Assert.Equal(BackupLimit.CollectionEntries, Assert.Throws<BackupLimitException>(() => WindowsBackupCodec.Parse(stream)).Limit);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(1)]
    public void DepthLimitIsExplicitAndCheckedBeforeUnknownFieldDeserialization(int extra)
    {
        string json = "{\"unknown\":" + new string('[', WindowsBackupCodec.MaxDepth - 1 + extra) + "0" +
            new string(']', WindowsBackupCodec.MaxDepth - 1 + extra) + "}";
        using var stream = new InputStream(json, maxRead: 3);
        if (extra == 0)
            Assert.Throws<JsonException>(() => WindowsBackupCodec.Parse(stream));
        else
            Assert.Equal(BackupLimit.Depth, Assert.Throws<BackupLimitException>(() => WindowsBackupCodec.Parse(stream)).Limit);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void NonseekableShortReadsPreserveUtf8AndLeaveInputOpen(bool bom)
    {
        string json = (bom ? "\uFEFF" : "") + Golden;
        using var stream = new InputStream(json, maxRead: 1);
        var backup = WindowsBackupCodec.Parse(stream);
        Assert.Equal("备份便签", Assert.Single(backup.Notes).Title);
        Assert.True(stream.CanRead);
    }

    private sealed class InputStream(string json, int? totalBytes = null, int maxRead = int.MaxValue) : Stream
    {
        private readonly byte[] payload = Encoding.UTF8.GetBytes(json);
        private bool disposed;
        public int BytesRead { get; private set; }
        public override bool CanRead => !disposed;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override int Read(byte[] buffer, int offset, int count)
        {
            int length = totalBytes ?? payload.Length;
            int read = Math.Min(Math.Min(count, maxRead), length - BytesRead);
            int copied = Math.Min(read, Math.Max(0, payload.Length - BytesRead));
            if (copied > 0)
                payload.AsSpan(BytesRead, copied).CopyTo(buffer.AsSpan(offset));
            buffer.AsSpan(offset + copied, read - copied).Fill((byte)' ');
            BytesRead += read;
            return read;
        }
        protected override void Dispose(bool disposing) { disposed = true; base.Dispose(disposing); }
        public override void Flush() => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }
}
