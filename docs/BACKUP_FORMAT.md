# DeskNodes Windows 备份协议 v1

此协议独立于 Mac。format 固定 `desknodes.windows.backup`，version=1，schema=1。
`exportedAt` 是 UTC 时间，格式 `yyyy-MM-ddTHH:mm:ss.fffZ`。其余字段使用 snake_case。
全部字段必须出现；可空字段显式写 null。未知字段拒绝。所有集合均为数组（包括单例设置），checkpoint 为零或一行。
ID 为非空、小写、带连字符 GUID；业务日为有效公历 YYYY-MM-DD。布尔使用 JSON boolean，sort_order 为有符号 64 位整数；notes/snapshot_notes 的 dock_order 为空或 0..2147483647 的整数。
时间字段 *_at 均为上述 UTC 毫秒字符串。坐标为有限数，宽高非负，均为显示器相对 DIP（屏幕像素除以该屏缩放）。

| 集合 | 字段（? 表示可空） |
|---|---|
| notes | id, title, color, sort_order, x, y, width, height, display_device_hint, dock_edge?, dock_order?, saved_level, free_x?, free_y?, free_width?, free_height?, automatic_height, collapsed, created_at, updated_at, deleted_at? |
| items | id, note_id, text, completed, struck, sort_order, archived_day?, created_at, updated_at, deleted_at? |
| snapshot_notes | day, note_id, title, color, sort_order, x, y, width, height, display_device_hint, dock_edge?, dock_order?, saved_level, free_x?, free_y?, free_width?, free_height?, automatic_height, collapsed, created_at, updated_at, deleted_at?, deleted |
| snapshot_items | day, item_id, note_id, text, completed, struck, sort_order, archived_day?, created_at, updated_at, deleted_at?, deleted, carried_to? |
| snapshots | day, sealed_at |
| pending_deleted_notes | note_id, deleted_at, day |
| pending_deleted_items | item_id, deleted_at, day |
| note_deletion_items | note_id, item_id |
| business_settings | rollover_minutes |
| business_preferences | hotkey_new, hotkey_float?, login_prompt_answered, login_intent |
| checkpoint | active_day, high_water |

颜色枚举：paper/lemon/apricot/cherry/lavender/mist/mint；层级：back/normal/topmost；停靠边：top/left/right 或 null。
停靠边和序号同时存在或同时为空；自由还原四坐标同时存在或同时为空。
notes/items 的 deleted_at 非空表示 tombstone；snapshot 的 deleted 与 deleted_at 保持一致。
完成与划掉互斥；归档事项须完成或划掉；carried_to 必须晚于快照日且事项、便签均未删除，事项未完成、未划掉、未归档。
历史 ID 可跨日复用，唯一键分别为 (day,note_id)、(day,item_id)，当前 notes/items ID 彼此不同。
快照事项引用同日快照便签。pending 删除时间须与 tombstone 相同；note_deletion_items 只能关联该已删除便签的已删除事项。
checkpoint.high_water >= active_day。business_settings.rollover_minutes 为 0–1439。
热键须经 HotkeyGesture 校验且两个组合不同；hotkey_float 可为空。登录意愿是业务数据，导入不触碰系统 Run 注册项。
不包含本机外观、工具条、字号、字体、分页、临时选择、撤销或实际系统启动状态。
输入限制：UTF-8 文件最多 64 MiB（67,108,864 字节，含 BOM 和空白）；单个字符串（含字段名）最多 1,048,576 个解码后的 UTF-16 代码单元；每个数组最多 100,000 条；JSON 最大容器嵌套深度 16（根对象计第 1 层）。边界值允许，超限抛出带分类的 BackupLimitException 并提示具体限制。流读取期间按实际字节及 token 校验，不依赖文件长度元数据；DTO 构造前完成限制检查。
导入文件读取、解析与 staging 校验在后台执行，只访问输入文件与临时库；回到 UI 后才确认及替换，整个期间禁止导入／导出重入。
导入只使用固定字段参数化插入，不执行输入 SQL；staging 通过业务校验和 foreign_key_check/integrity_check 后，还必须经 NoteRepository 完整读出所有当前便签（含 tombstone）及事项（含删除和归档），经 HistoryQueries 完整读出全部快照，并通过协议导出复核；任一步失败均拒绝且不替换活库。全部成功后用 SQLite online backup API 替换活库。
导出在只读事务中读取，目标同目录唯一临时文件 flush 并关闭后，Replace/Move 发布，失败不截断原文件。
