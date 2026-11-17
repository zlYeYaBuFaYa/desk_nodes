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
- [SettingsWindow.swift](../Sources/DeskNodesApp/SettingsWindow.swift)、[HistoryWindow.swift](../Sources/DeskNodesApp/HistoryWindow.swift)：设置与只读历史的 presentation model／SwiftUI 视图；最近删除通过注入动作恢复。
- [Theme.swift](../Sources/DeskNodesApp/Theme.swift)：动态颜色、NoteType 排版度量和 NoteFonts 字体选择、中文 fallback 与系统下载。

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

Toolbar 的 Transition 以可见 shell、icon／controls 透明度为连续状态，CADisplayLink 逐帧呈现；回到固定位置使用先收缩后 glide 的两段转换，pendingExpand 记录移动中的唤起请求，到达时再次检查指针。动画窗口在形变阶段使用外框并集，滑动阶段随入口移动，避免整段路径截获事件。应用启动通过 show() 总是进入 expanded；收缩形态不持久化。

不创建 NSStatusItem。DesktopController 每次构建工具条右键菜单，Application 为历史子菜单提供 NSMenuDelegate，menuNeedsUpdate 按需查询快照与最近删除数量；应用主菜单保留原生编辑与快捷键响应链。

多选集合 `picked: Set<NoteID>?` 与普通 selection 分开，nil 表示不在模式中。可选窗口过滤 suppressed 与 isVisible；窗口先拦截多选按下，再处理编辑。覆盖层位于 floating−1，框选与操作条位于 floating+1；键盘使用应用内 monitor，没有全局监听。

WindowModes 的有效 peek 为 `peeking || picking`，再按每张保存 level 解析。桌面层为 desktopIconWindow+1，普通为 normal，置顶为 floating；设置、历史与提示的 collectionBehavior 单独处理。旧 desk.topmost 由 retireGlobalTopmost 读取一次后移除。

### 几何

- [WindowState.swift](../Sources/DeskNodesActions/WindowState.swift)：frame 校验、尺寸约束、折叠投影。
- [Arrangement.swift](../Sources/DeskNodesActions/Arrangement.swift)：最大避让区、列顶部数组、分页与新建级联。
- [Docking.swift](../Sources/DeskNodesActions/Docking.swift)：各边停靠、溢出标签、保留带、离线屏幕解析。
- [ToolbarGeometry.swift](../Sources/DeskNodesActions/ToolbarGeometry.swift)：外边筛选、磁吸优先级、方向与锚点求解。

新建与整理避让工具条完整 target；停靠条只避让 toolbarReservation 返回的固定 homeZone。ToolbarAnchor 保存完整工具条的自由中心或吸边锚点；ToolbarHome 另存边与比例，由 ToolbarGeometry.home 解析为当前屏幕的外边，再转换为 snapped anchor。homeSpan 约束角落距离，homeZone／hitZone 计算入口向边缘扩展的命中与预留区；改变区域才触发停靠重排。

命中与动画使用当前 visibleFrame，文字按最终几何布局。吸边跨度与固定位置跨度不同，转换由几何函数完成，不能直接混用两种 ratio。

### UserDefaults 字段

[PresentationDefaults.swift](../Sources/DeskNodesApp/PresentationDefaults.swift) 保存：

- desk.collapsed。
- toolbar.place（旧位置）、toolbar.anchor、toolbar.orientation、toolbar.autoShrink。
- toolbar.home（边与比例，不绑定显示器）。
- app.appearance。
- note.newWidth、note.newHeight、note.textSize、note.font。
- arrange.pages、arrange.page。
- screens.displaced（因显示器离线迁到主屏的便签：原位置与迁移后位置）。

旧 toolbar.place 迁为自由锚点，不按距离推断吸边；自由锚点存中心，吸边锚点存边及沿边比例。toolbar.home 无效时恢复 ToolbarHome.standard。note.newHeight 缺失时使用默认高度，显式 0 表示随内容。字号、字体与外观使用枚举原值，未知值分别回退到标准、默认字体与跟随系统。screens.displaced 由 `NoteActions.reconcileScreens(_:displaced:)` 读写：原显示器返回且便签位置仍等于迁移后位置时写回原位置，否则丢弃记录；数据库始终保存实际显示位置。无法解码时视为空，导入备份时清空。

上述键不属于业务库和 JSON。验证域为 local.desknodes.native.verification，不同验证目录共用此域。临时焦点、选择、peeking／picking、动画与撤销也不序列化。

<a id="fonts"></a>
## 字体资源与应用外观

NoteType 的 size／face 从本机偏好初始化；Application 的 setTextSize／setNoteFont 在组词期间拒绝更新，否则对所有卡片调用 applyTextSize 并重排。NoteFonts 为系统西文设计添加中文 cascadeList；文楷按 PostScript 名 LXGWWenKai-Regular／LXGWWenKai-Medium 取字重，缺少 Medium 时退 Regular，再退系统字体。

圆体可用性通过 NSFontManager 检查。SettingsPresentation 仅在用户选择未安装圆体时调用 CTFontDescriptorMatchFontDescriptorsWithProgressHandler，回调切回主线程，仅成功后请求切换；下载期间不改持久化选择。启动不发起下载，缺失字体由字体回退处理。

[fetch-fonts.sh](../scripts/fetch-fonts.sh) 固定获取霞鹜文楷 v1.530 的两个原始 TTF 与 OFL.txt，并校验 SHA-256；Resources/Fonts 不入库。[构建脚本](../scripts/build-macos.sh) 打包到 Contents/Resources/Fonts，[Info.plist](../Resources/Info.plist) 的 ATSApplicationFontsPath 仅为应用注册字体。Swift Package 本身不声明字体资源，直接 swift run 不包含这些文件。授权为 SIL Open Font License 1.1；设置优先打开打包的 OFL，缺失时打开项目在线授权页。

AppAppearance 通过 NSApp.appearance 设置跟随系统／aqua／darkAqua，并写本机偏好。便签和停靠标签显式固定 aqua；工具条根据有效外观选择 NSVisualEffectView 的 popover／hudWindow 材质及动态描边，其他窗口采用动态颜色。具体外观值见 [UI 规格](UI_SPEC.md#palette)。

<a id="history"></a>
## 历史展示与导航

Store.recentHistory(limit:) 按封存日期倒序读取；HistoryMenuRow 使用 BusinessCalendar 的当前业务日生成相对标签，并复用 HistoryCompletion 绘制菜单统计。recentlyDeletedCount 通过 SQL 聚合计数，不加载完整恢复列表。

AuxiliaryWindows 复用 HistoryPresentation 和窗口，指定 day 时同步月份与选中日期；本地键盘 monitor 只接管该窗口的日历模式，并保留 NSTextView 与完整键盘控制的方向键。HistoryPresentation.step 按天约束不越过 today，navigate 按月定位月首、没有相同上限；today 在 reload 时更新，不安装独立计时器。HistoryHeat 复用冻结完成率映射日格色阶，读取失败与空快照分别呈现。业务统计与导航边界见 [FR-11](REQUIREMENTS.md#fr-11)。

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
