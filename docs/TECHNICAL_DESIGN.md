# DeskNodes 技术设计

只维护代码结构、数据契约和实现机制。产品规则见 [功能与交互](REQUIREMENTS.md)，数值见 [UI 规格](UI_SPEC.md)，构建命令见 [操作指南](native-build.md)。

<a id="architecture"></a>
## 工程与对象职责

工程为 Swift Package（tools 5.9、Swift 5 language mode、macOS 14+），无第三方运行时依赖。AppKit 管理应用、NSPanel 与 TextKit，SwiftUI 承载设置和历史，Carbon 注册全局热键，ServiceManagement 管理登录项，QuartzCore／显示刷新回调驱动动画。

依赖方向：`DeskNodesApp → DeskNodesActions → DeskNodesPersistence → DeskNodesCore + CSQLite`，App 同时直接使用 Persistence 与 Core。Core 和 Persistence 发布 library product，Actions 是内部 target；非 macOS 不创建 App 及其测试目标。

- [Application.swift](../Sources/DeskNodesApp/Application.swift)：组合根，共享一个 Store／NoteActions，协调启动、刷新、系统服务、跨天、导入重建与退出。
- [NoteSurfaces.swift](../Sources/DeskNodesApp/NoteSurfaces.swift)：NoteID 到窗口及渲染状态映射，普通选择、批量选择、差量刷新。
- [NotePanel.swift](../Sources/DeskNodesApp/NotePanel.swift)、[NoteTextView.swift](../Sources/DeskNodesApp/NoteTextView.swift)：卡片布局、输入所有权、菜单、原生文字撤销。
- [Desk.swift](../Sources/DeskNodesApp/Desk.swift)：整组展示、会话 peeking／picking、整理、分页与工具条占位；不编辑事项。
- [Toolbar.swift](../Sources/DeskNodesApp/Toolbar.swift)：外壳、命中、手势、计时与动画；不持有业务库。
- [SelectionOverlay.swift](../Sources/DeskNodesApp/SelectionOverlay.swift)：NotePicker、每屏覆盖层、矩形相交选择与底部 SelectionBar。
- [DockController.swift](../Sources/DeskNodesApp/DockController.swift)：停靠布局、标签、拖出与屏幕校正。
- [AuxiliaryWindows.swift](../Sources/DeskNodesApp/AuxiliaryWindows.swift)：按需创建并复用 SwiftUI 承载窗口。
- [SystemServices.swift](../Sources/DeskNodesApp/SystemServices.swift)：GlobalHotkey、LoginService；Carbon 热键 ID 使用类级计数，避免两个实例互认。

Bundle 信息以 [Info.plist](../Resources/Info.plist) 为准。主 UI 协调在主 actor，Store 为同步串行仓库，不是异步后台 actor。

<a id="models"></a>
## 数据模型

定义见 [Models.swift](../Sources/DeskNodesPersistence/Models.swift) 和 [Preferences.swift](../Sources/DeskNodesPersistence/Preferences.swift)。

- `StableID<Kind>`：UUID 类型包装，NoteID／ItemID 不能混用，不循环使用删除身份。
- `Note`：title、color、placement、level、order、freeRestore、automaticHeight、collapsed 及时间戳。
- `Placement`：dock(edge, displayID) 或 free(displayID, x, y, width, height)，屏幕坐标原点在左下；freeRestore 仅能是自由位置。
- `Item`：noteID、text、completed、struck、order、archivedDay 及时间戳；Store 拒绝 completed 与 struck 同时为真。
- `Settings`：单例 native-settings，跨天小时／分钟及 dockEdge、displayID、edgePreference。后三者保留持久化兼容，已删除整体停靠设置入口；displayID 仍参与旧位置的屏幕解析，不能删字段。
- `NativePreferences`：hotkey、peekHotkey、loginDecision，属于业务库，与本机 UserDefaults 分开。
- `DailySnapshot`：day、capturedAt、冻结的 SnapshotNote／SnapshotItem；包含删除、划掉与 carriedTo。
- `HistoryDay`：严格校验的 YYYY-MM-DD 公历日期，不含时区偏移；`RolloverCheckpoint` 保存 activeDay 与 highWater。

<a id="storage"></a>
## SQLite 与事务

生产库为 `~/Library/Application Support/local.desknodes.native/DeskNodes.sqlite3`，目录创建权限 0700。非空 `DESKNODES_DATA_DIR` 重定向库目录；运行与隔离方式只在 [操作指南](native-build.md#isolation) 维护。

连接采用 SQLITE_OPEN_FULLMUTEX、busy timeout 5000ms、WAL、synchronous=FULL 和外键约束。Store 用 NSRecursiveLock 串行化；外层事务为 BEGIN IMMEDIATE，嵌套使用 savepoint，异常回滚当前作用域。事务闭包内不可 suspend 或切线程。

### 当前 schema

[Schema.swift](../Sources/DeskNodesPersistence/Schema.swift) 当前版本为 8，application_id 为 `0x44534B4E`；拒绝无关库与未来版本。主要表：

- notes、items：实时与保留的删除记录，items 按 note_id／position／id 建索引。
- settings、native_preferences：业务设置单例及原生偏好 JSON。
- days、snapshot_notes、snapshot_items：封存日期与冻结成员。
- rollover_state、item_archives：业务日检查点与事项归档映射。
- pending_deleted_notes、pending_deleted_items：下一次快照仍需记录的删除身份。

迁移在 BEGIN EXCLUSIVE 中进行：v1 实时行 → v2 历史 → v3 自动高度 → v4 自由恢复位置 → v5 跨天／归档／待记录删除 → v6 边缘偏好 → v7 native_preferences → v8 items／snapshot_items 增加 struck。打开旧库时 graphite 映射为 paper，不单独升 schema；历史读取与备份解码也兼容旧颜色。

快照先写成员、最后写日期 header，依靠延迟外键提交。触发器拒绝封存行 UPDATE／DELETE 与日期封存后的成员插入；归档映射同样不能原地修改／删除。恢复只改实时 tombstone，不改封存内容。

<a id="editing"></a>
## 编辑、刷新与撤销实现

每个 NoteTextView 拥有自己的 NSTextStorage、选区、输入上下文和 UndoManager；标题 NoteTitleField 持有独立 field editor，避免跨便签撤销串线。

NoteCardView 用 pendingItems／pendingTitle 与 debounce 提交实际编辑器内容，marked text 跳过并重试。EditorSynchronization 判定活跃／被动编辑所有权，跨天或导出仅接纳正确所有者的已提交文字。完成样式使用 layout manager 临时属性，不替换正文或污染原生 undo。

NoteSurfaces.refresh 两次查询取得 notes 与分组实时事项，与 Rendered(note, items) 比较，仅触及改变的窗口。RefreshScope 的 changes 更新差量，layout 另排停靠，all 强制重做展示。suppressed 阻止收起／非当前页窗口被刷新重新显示。

文字撤销归编辑器；结构删除由 NoteActions 的 Deleted 内存栈处理。单张／事项保留原记录，批次保存多个 Note 与子记录，在同一事务删除和恢复；恢复失败回滚整批。从最近删除恢复批次中的一张时，过滤掉该成员，保留其余批次。时限和用户优先级只见 [FR-04](REQUIREMENTS.md#fr-04)。

<a id="presentation"></a>
## 展示状态、几何与本机偏好

### 状态与窗口

整组 DeskPresentation 为 expanded／collapsing／collapsed／expanding；generation 使过期动画完成回调失效，resting frame 按 NoteID 关联。工具条独立维护 expanded／collapsing／round／expanding，不逐帧写库。

多选集合 `picked: Set<NoteID>?` 与普通 selection 分开，nil 表示不在模式中。可选窗口过滤 suppressed 与 isVisible；窗口先拦截多选按下，再处理编辑。覆盖层位于 floating−1，框选与操作条位于 floating+1；键盘使用应用内 monitor，没有全局监听。

WindowModes 的有效 peek 为 `peeking || picking`，再按每张保存 level 解析。桌面层为 desktopIconWindow+1，普通为 normal，置顶为 floating；设置、历史与提示的 collectionBehavior 单独处理。旧 desk.topmost 由 retireGlobalTopmost 读取一次后移除。

### 几何

- [WindowState.swift](../Sources/DeskNodesActions/WindowState.swift)：frame 校验、尺寸约束、折叠投影。
- [Arrangement.swift](../Sources/DeskNodesActions/Arrangement.swift)：最大避让区、列顶部数组、分页与新建级联。
- [Docking.swift](../Sources/DeskNodesActions/Docking.swift)：各边停靠、溢出标签、保留带、离线屏幕解析。
- [ToolbarGeometry.swift](../Sources/DeskNodesActions/ToolbarGeometry.swift)：外边筛选、磁吸优先级、方向与锚点求解。

自动布局避让完整 target，命中与动画使用当前 visibleFrame。形变中的窗口可临时取两外框并集，结束后缩回；文字按最终几何布局。

### UserDefaults 字段

[PresentationDefaults.swift](../Sources/DeskNodesApp/PresentationDefaults.swift) 保存：

- desk.collapsed。
- toolbar.place（旧位置）、toolbar.anchor、toolbar.orientation、toolbar.autoShrink。
- note.newWidth、note.newHeight、note.textSize。
- arrange.pages、arrange.page。

旧 toolbar.place 迁为自由锚点，不按距离推断吸边；自由锚点存中心，吸边锚点存边及沿边比例。note.newHeight 缺失时使用默认高度，显式 0 表示随内容。note.textSize 使用枚举原值。

上述键不属于业务库和 JSON。验证域为 local.desknodes.native.verification，不同验证目录共用此域。临时焦点、选择、peeking／picking、动画与撤销也不序列化。

<a id="rollover"></a>
## 业务日实现

BusinessCalendar 注入当前时区、公历和跨天设置；DST 缺失时段取下一个有效时间，重复时段取第一次。activeDay 与 highWater 联合阻止回拨。

Store.rollover 在一个事务中调用安全提交、封存、归档、清理待记录删除并推进检查点。Application 安装计时器与时钟／时区／唤醒通知，deferred 状态在编辑变更后重试；历史窗口只读 snapshot，不调用 capture。产品日期及统计口径统一见 [FR-10](REQUIREMENTS.md#fr-10) 和 [FR-11](REQUIREMENTS.md#fr-11)。

<a id="automatic-backup"></a>
## 自动 SQLite 副本

[AutomaticBackup.swift](../Sources/DeskNodesPersistence/AutomaticBackup.swift) 使用 VACUUM INTO 写入 `.partial-UUID.sqlite3`，成功后移动为数据库目录下 `Backups/DeskNodes-YYYY-MM-DD.sqlite3`。同日文件不覆盖，按文件名保留最新 7 份。失败只日志记录，恢复步骤见 [操作指南](native-build.md#recovery)。

<a id="backup"></a>
## 原生 JSON 协议与替库

[Backup.swift](../Sources/DeskNodesPersistence/Backup.swift) 的 NativeBackup：format 为 local.desknodes.native.backup，version 为 1，导出 schema 为当前数据库版本；导入接受 schema 7 与 8。

必需集合为 notes、items、history、pendingNotes、pendingItems，即使为空也必须存在；另有 settings、preferences、可选 checkpoint。notes／items 含删除及归档保留行，历史含冻结成员，业务布局随 Note 一起序列化；本机展示字段的归属见 [UserDefaults](#presentation)。

旧 schema 7 缺少 struck 时为 false；缺少 peekHotkey 时默认值由 NativePreferences 解码，若与新建快捷键冲突则设为空串。旧 Tauri 格式不接受。

数据库日期为 Unix 秒 Double，Swift JSONEncoder 的 Date 默认为距 2001-01-01 秒数；StableID 编码为含 rawValue 的对象，Placement 使用 Swift enum 合成 Codable，不能手写猜测载荷。

校验流程：模型约束、ID 唯一性、引用、顺序、时间、顺延及归档一致性 → 内存 staging Store 写入 → foreign_key_check／integrity_check → 经生产导出路径复核。先插快照子行再写 header，不导入 SQL 或触发器。

确认替换后先释放浮起快捷键，尝试候选新建快捷键，持久化闭包中用 SQLite backup API 原子替库；失败时 backup_finish 回滚、保留旧句柄并重绑旧浮起快捷键。成功后按导入偏好绑定浮起键，失效旧编辑器、保存任务和撤销，再重建停靠与窗口。用户流程与部分失败语义统一见 [FR-13](REQUIREMENTS.md#fr-13)。

## 维护边界

不得从被动编辑器强制提交、用数组下标恢复身份、在动画帧写库或清空用户数据来修复展示。输入法、导入重建、屏幕拓扑、多个展示状态叠加时优先确认所有权和过期回调；已知验证缺口集中见 [验收](ACCEPTANCE.md)。
