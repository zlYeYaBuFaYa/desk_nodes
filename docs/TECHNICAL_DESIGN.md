# DeskNodes 技术文档

日期：2026-11-12；代码基线见 [总览](README.md)。本文描述实际代码，不提出框架迁移。

## 1. 技术栈与工程边界

- Swift Package Manager，manifest 为 Swift tools 5.9，最低平台 macOS 14。
- AppKit 管理应用、菜单、NSPanel、文字输入和窗口层级；SwiftUI 提供低频历史、最近删除和设置界面。
- QuartzCore 提供图层动效，AppKit 动画上下文移动真实窗口；工具条使用显示刷新回调驱动形变。
- Carbon `RegisterEventHotKey` 负责全局快捷键；ServiceManagement `SMAppService.mainApp` 负责登录项。
- SQLite 通过系统库 `CSQLite` 的 module map 接入。无第三方 Swift 运行时依赖、无 WebView 主界面。
- Bundle ID `local.desknodes.native`，版本 0.1.0 / 1，`LSUIElement=true`，入口设置 `.accessory`。构建脚本不加沙盒 entitlement。

## 2. 模块和依赖

```text
DeskNodes（可执行产品，仅 macOS）
└─ DeskNodesApp
   ├─ DeskNodesActions ── DeskNodesPersistence
   ├─ DeskNodesPersistence ── DeskNodesCore + CSQLite
   └─ DeskNodesCore

DeskNodesCore         独立设计常量与颜色算法
DeskNodesPersistence  Foundation、模型、事务、SQLite、历史、备份
DeskNodesActions      编辑命令、删除队列、布局与窗口状态的纯逻辑
DeskNodesApp          AppKit / SwiftUI / Carbon / ServiceManagement 适配
```

`Package.swift` 在非 macOS 下不创建 App 及原生测试目标，因此便携测试通过不证明 AppKit 编译或交互正确。Core 和 Persistence 对外发布 library product；Actions 是内部 target。

## 3. 应用对象职责

### 3.1 入口与协调

`Sources/DeskNodesApp/Application.swift` 的 `AppDelegate` 是组合根，持有一个共享 `Store` 和 `NoteActions`，组装以下对象：

- `NoteSurfaces`：以 NoteID 管理桌面便签窗口，记录最后渲染值、当前选择；差量刷新。
- `DesktopController`（`Desk.swift`）：管理全局收起、置顶、整理、分页、工具条占位与叠放提示，不编辑事项内容。
- `Toolbar`：胶囊／圆形形态、手势、命中、计时和动画；不持有业务库。
- `DockController`：兼容旧停靠条、标签、分页、拖出和显示器校正。
- `EdgeRevealController`：独立侧边窗口，重用同一 Store 和 Actions，呈现另一组 NoteCardView。
- `AuxiliaryWindows`：按需创建并复用设置和历史 NSWindowController；用 NSHostingController 承载 SwiftUI。
- `GlobalHotkey`、`LoginService`：系统适配；`DeletionToast`、`NoticeToast`：非激活反馈。

App UI 协调主要在主 actor；Store 是同步串行仓库，不是后台 actor。不能把“有锁”理解成应用已经异步写盘。

### 3.2 启动与退出顺序

启动：安装编辑菜单和菜单栏 → 打开 SQLite／迁移 → 创建桌面协调器 → 应用置顶覆盖 → 注册屏幕监听 → 创建边缘控制器 → 安装跨天监听并补检查 → 校正屏幕 → 全量刷新 → 显示完整工具条 → 注册新建快捷键 → 首次登录启动询问。

退出：检查全局 marked text → 提交桌面与边缘编辑 → 允许退出 → 停止热键和计时器、清理观察者、关闭 Store、移除菜单栏图标。组词未结束或提交失败会取消退出。

## 4. 数据模型

模型定义于 `Sources/DeskNodesPersistence/Models.swift`。

- `StableID<Kind>`：UUID 的类型包装，NoteID 与 ItemID 不能混用；删除后不循环使用身份。
- `Note`：id、可选 title、七色 color、placement、level、order、freeRestore、automaticHeight、collapsed、createdAt、updatedAt、deletedAt。
- `Placement`：`dock(edge, displayID)` 或 `free(displayID, x, y, width, height)`；位置是 AppKit 屏幕坐标 pt，原点在左下。
- `freeRestore`：停靠前自由位置，只能是 free，可跨重启和撤销保存。
- `Item`：id、noteID、text、completed、order、archivedDay、createdAt、updatedAt、deletedAt。
- `Settings`：固定身份 `native-settings`，跨天小时／分钟、停靠边、目标屏幕、边缘偏好。
- `NativePreferences`：hotkey 与 loginDecision；在业务库中，区别于 UserDefaults 展示偏好。
- `DailySnapshot`：day、capturedAt、SnapshotNote 列表；SnapshotItem 冻结文字、完成、排序、删除、carriedTo。
- `HistoryDay`：严格 `YYYY-MM-DD` 公历日期，校验真实存在，不保存时区偏移。
- `RolloverCheckpoint`：activeDay + highWater；后者为防时钟回拨的最高已见时间。

## 5. SQLite 结构与事务

### 5.1 存储与连接

生产路径：`~/Library/Application Support/local.desknodes.native/DeskNodes.sqlite3`。目录创建权限 0700；不提供数据库加密功能。`DESKNODES_DATA_DIR` 非空时改用该目录，供隔离验收。

连接使用 `SQLITE_OPEN_FULLMUTEX`，设置 busy timeout 5000ms、WAL、`synchronous=FULL` 和外键约束。Store 使用 `NSRecursiveLock` 串行化；`transaction` 外层为 `BEGIN IMMEDIATE`，嵌套为 savepoint，异常回滚相应作用域。事务闭包内不可 suspend 或切到其他线程。

### 5.2 当前 schema 7 的表

- `notes`：id 主键、title、color、placement JSON、level、position、collapsed、created、updated、deleted、automatic_height、free_restore JSON。
- `items`：id 主键、note_id 外键、text、completed、position、created、updated、deleted；有 `(note_id, position, id)` 索引。
- `settings`：单例 id、hour、minute、dock_edge、display_id、edge_preference。
- `days`：day 主键、captured，代表已封存的日期。
- `snapshot_notes`：联合主键 `(day, note_id)`，冻结便签标题、颜色、顺序、删除时间。
- `snapshot_items`：联合主键 `(day, item_id)`，关联 `(day, note_id)`，保存文字、完成、顺序、删除与 carried_to。
- `rollover_state`：固定 `id=1`，active_day、high_water。
- `item_archives`：item_id 主键、day，关联事项及对应快照成员；区分归档与用户删除。
- `pending_deleted_notes`、`pending_deleted_items`：尚需进入下一次日快照的删除身份。
- `native_preferences`：固定 `id=1`，JSON payload 保存快捷键与登录意愿。

数据库时间列是 Unix 秒 Double；Swift JSONEncoder 默认日期是自 2001-01-01 起的秒数，不能把备份 JSON 日期当成 Unix 时间或 ISO 文本。稳定 ID 的 Codable 输出是包含 `rawValue` 的对象，不是所有位置都直接编码 UUID 字符串。

### 5.3 迁移与封存

`Schema.swift` 使用 `PRAGMA application_id = 0x44534B4E` 识别本应用数据库；拒绝无关库及超前版本。迁移在 `BEGIN EXCLUSIVE` 内进行：v1 live 行 → v2 历史 → v3 自动高度 → v4 自由恢复位置 → v5 跨天／归档／待记录删除 → v6 边缘偏好 → v7 native_preferences。

打开时将 notes 的旧 graphite 改为 paper，不升版本。历史触发器拒绝 UPDATE／DELETE；日期 header 写入后，拒绝该日再插 snapshot 子项。capture 先写子项、最后写 day header，依靠延迟外键检查提交。归档映射也禁止原地修改／删除。

恢复删除只清 live tombstone，不改历史；这是“昨天显示已删除、今天可恢复”的一致性依据。当前没有 tombstone 定期物理删除。

## 6. 编辑、刷新与撤销

### 6.1 输入所有权

每个事项由 `NoteTextView` 管理 NSTextStorage、选区、输入上下文和自己的 UndoManager；标题 `NoteTitleField` 持有独立 field editor，避免跨便签撤销串线。

`NoteCardView` 记录 pendingItems／pendingTitle，0.4 秒 debounce 后读取该卡片实际编辑器内容并写 Store。输入法 marked text 跳过提交并稍后重试。`EditorSynchronization` 防止被动副本刷新覆盖活跃／组词文字，跨天和导出只提交正确所有者的已提交内容。

事项行由真实 TextKit 布局计算高度；固定行高 22pt 加上下各 5pt，一行总 32pt，圆圈对齐第一行。完成样式使用 layout manager 临时属性，不替换正文或污染原生文字 undo。

### 6.2 差量刷新

`NoteSurfaces.refresh` 一次读取 notes，一次批量读取 live items 分组，再与 `Rendered(note, items)` 比较。仅创建、更新或移除变化的窗口，选择跟随 NoteID，不依赖数组下标。

RefreshScope：`changes` 触及变化内容；`layout` 还重排停靠；`all` 重做所有展示。边缘卡片共用这些数据，具备独立编辑视图。全局收起／非当前页通过 `suppressed` 阻止窗口被普通刷新重新显示。

### 6.3 两种撤销

文字撤销属于原生编辑器。结构删除撤销属于 `NoteActions` 的内存栈，保存原记录和删除时间，五秒内从新到旧恢复。开始输入会清除删除撤销优先标记；导入明确清空结构与原生旧上下文。最近删除是数据库范围查询，不依赖该内存栈。

## 7. 窗口、几何与展示偏好

### 7.1 层级

`WindowModes` 计算有效层级。桌面层为 `desktopIconWindow + 1`，普通为 `.normal`，置顶为 `.floating`。全部便签加入所有 Space；仅有效置顶使用 `.fullScreenAuxiliary`，其余 `.fullScreenNone`。

ToolbarPanel 是不获取 key 的 nonactivating 浮动 NSPanel；工具条和 StackHint 允许全屏辅助显示。RevealPanel 为可输入的独立全屏辅助面板；设置、历史为普通窗口，禁止辅助全屏行为。状态栏／系统高优先级窗口不在“全部置顶”保证范围。

### 7.2 几何职责

- `WindowState.swift`：自由 frame 的有限数值、尺寸范围和折叠投影。
- `Arrangement.swift`：每屏稳定布局、避让最大可用区、分页、新建级联、叠放提示。
- `Docking.swift`：系统可用区、停靠条布局、标签与保留／脱离带。
- `ToolbarGeometry.swift`：方向、外边筛选、磁吸优先级、圆形锚点和完整目标。
- AppKit 层负责把这些纯几何结果应用到真实窗口。

必须区分 toolbar 当前 visibleFrame 与完整 target；新建、整理和停靠避让 target，鼠标命中、叠放提示按当前可见轮廓。动画中窗口可临时为两外框并集，结束立即收回，不能留下永久热区。

### 7.3 UserDefaults

`PresentationDefaults.swift` 保存：`desk.collapsed`、`desk.topmost`、`toolbar.place`（旧位置）、`toolbar.anchor`、`toolbar.orientation`、`toolbar.autoShrink`、`arrange.pages`、`arrange.page`。

旧 toolbar.place 迁为自由锚点，不按距离自动认定吸边。自由锚点保存中心，吸边锚点保存边和圆心沿边合法范围内的比例；目标 frame 每次求解，不存动画进度。隔离验证使用 `local.desknodes.native.verification` 偏好域；不同验证目录仍共用该验证域。

这些键不进入 JSON 导入导出。业务便签的 placement 则在数据库、会被导入替换；不能笼统写成“导入不改变布局”。

## 8. 跨天与历史统计

`BusinessCalendar` 注入时区，Gregorian 日历按墙上时间划分业务日。DST 缺失时段取下一个有效时间，重复时段取第一次。高水位和 activeDay 同时阻止回拨破坏。

`Store.rollover` 在同一事务内：计算当前日 → 初始化或比较检查点 → 请求安全提交 → 封存 activeDay、顺延到当前日 → 写已完成事项归档映射 → 清理待记录删除成员 → 推进检查点。跨多天不补空白中间日。已归档事项不会再作为 live 行读取。

App 用 30 秒 timer（tolerance 2 秒）及启动、唤醒、时区／时钟通知触发。输入延迟依赖编辑变更后重试。成功推进后 `AutomaticBackup` 用 `VACUUM INTO` 写 `.partial-UUID.sqlite3` 再移动成 `Backups/DeskNodes-YYYY-MM-DD.sqlite3`，同日不覆盖，按文件名保留最近 7 份。备份失败只日志记录。

历史读取只读 snapshot。月历按 Monday-first 排列；完成率是 frozen completed 的计数除以所有记录次数，含删除成员。历史日期不按当前时区重新解释。

## 9. JSON 协议与导入一致性

协议定义见 `Backup.swift`：

```text
NativeBackup
  format: "local.desknodes.native.backup"
  version: 1
  schema: 7
  notes: [Note]                    含删除记录
  items: [Item]                    含删除与归档记录
  history: [DailySnapshot]
  settings: BackupSettings
  preferences: NativePreferences   快捷键、登录意愿
  checkpoint: BackupCheckpoint?    可无值
  pendingNotes: [NoteID]
  pendingItems: [ItemID]
```

以上是结构说明，不是可直接导入的 JSON 示例。非可选集合即使为空也必须存在；Placement 使用 Swift enum 的合成 Codable 编码，不应手写猜测其结构。

导出：开启事务 → 检查组词并提交 → 读取全量保留行 → 校验模型 → prettyPrinted、sortedKeys 编码 → 保存面板 → 原子写文件。

导入：文件选择 → JSON 解码 → 校验版本、唯一 ID、引用、顺序、时间、顺延与归档一致性 → 在内存 staging Store 写入全部结构并检查外键／完整性 → 重新经生产读路径导出验证 → 用户确认 → 先尝试注册候选快捷键 → 使用 SQLite backup API 原子替换目标库 → 清理旧编辑器、撤销、边缘／停靠控制器 → 全量刷新。

候选快捷键失败或 persist 抛错时保留旧句柄；替换未完成时 SQLite backup_finish 回滚。导入不注册登录项、不即时跨天，不导入 SQL／触发器。旧石墨解码为 paper，当前仅接受 schema 7 的原生备份，不声称所有旧 schema JSON 可导入。

## 10. 构建、测试与恢复

在已有兼容 Xcode 的 Mac：

```sh
xcrun swift --version
xcrun --sdk macosx --show-sdk-path
xcrun swift test
./scripts/build-macos.sh
/usr/bin/codesign --verify --strict --verbose=2 build/DeskNodes.app
open build/DeskNodes.app
```

构建脚本生成当前架构 release，打包可执行文件、Info.plist、ICNS，默认 ad-hoc 签名，验证后替换仓库 `build/DeskNodes.app`。可通过 `DESKNODES_SIGNING_IDENTITY` 指定已有身份；不安装证书、不公证、不承诺 universal 包。

本次测试实际结果和缓存目录调整见 [验收文档](ACCEPTANCE.md)，不使用旧文档里的测试数作为证据。测试不等于签名应用真实运行、外接屏、中文输入或登录项通过。

验收时用 `DESKNODES_DATA_DIR` 隔离数据库；登录项仍是系统集成，应在明确范围内测试。正常备份恢复优先使用应用 JSON。自动 SQLite 副本恢复前先退出应用、保留当前数据目录，然后替换主库并移除与旧库不匹配的 WAL／SHM；运行中的主库不能单独复制作为可靠离线备份。完整离线目录恢复方法见 [原构建与恢复说明](native-build.md)。

## 11. 维护约束与风险入口

不在动画帧写库；不以数组下标关联恢复位置；不对被动编辑副本执行强制提交；不清空已有数据来解决展示问题；不把登录意愿当系统注册状态；不以图层截图替代可点击窗口。

本次发现双视图同步测试失败，详见验收记录。工具条与便签三个状态机、屏幕变化、组词和导入重建是维护时最需要联合验证的边界。当前 edge reveal 动画仍是约 0.30 秒 spring＋fade，不能把新工具条的无过冲规则泛化为全应用均已去除 spring。
