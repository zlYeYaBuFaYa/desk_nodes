using DeskNodes.Core.Services;

namespace DeskNodes.Core.Storage;

public sealed record BusinessPreferences(string HotkeyNew = HotkeyGesture.DefaultNew,
    string? HotkeyFloat = HotkeyGesture.DefaultFloat, bool LoginPromptAnswered = false, bool LoginIntent = false)
{
    public BusinessPreferences Validate()
    {
        var create = HotkeyGesture.Parse(HotkeyNew);
        var raise = HotkeyFloat is null ? null : HotkeyGesture.Parse(HotkeyFloat);
        if (create == raise)
            throw new ArgumentException("新建与浮起快捷键不能相同。");
        return this with { HotkeyNew = create.ToString(), HotkeyFloat = raise?.ToString() };
    }
}

public sealed class BusinessPreferencesStore(DeskNodesDatabase database)
{
    public BusinessPreferences Load() => database.Read(connection =>
    {
        using var command = connection.CreateCommand();
        command.CommandText = "SELECT hotkey_new,hotkey_float,login_prompt_answered,login_intent FROM business_preferences WHERE singleton=1";
        using var reader = command.ExecuteReader();
        if (!reader.Read())
            throw new InvalidDataException("缺少业务偏好。");
        return new BusinessPreferences(reader.GetString(0), reader.IsDBNull(1) ? null : reader.GetString(1),
            reader.GetBoolean(2), reader.GetBoolean(3)).Validate();
    });
    public void Save(BusinessPreferences value)
    {
        value = value.Validate();
        database.Transaction(connection =>
        {
            using var command = connection.CreateCommand();
            command.CommandText = "UPDATE business_preferences SET hotkey_new=$new,hotkey_float=$float,login_prompt_answered=$answered,login_intent=$intent";
            command.Parameters.AddWithValue("$new", value.HotkeyNew);
            command.Parameters.AddWithValue("$float", (object?)value.HotkeyFloat ?? DBNull.Value);
            command.Parameters.AddWithValue("$answered", value.LoginPromptAnswered);
            command.Parameters.AddWithValue("$intent", value.LoginIntent);
            command.ExecuteNonQuery();
        });
    }
}
