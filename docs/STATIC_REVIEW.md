# feat-win 静态审查

核对日期：2026-11-21。对象是分支 `feat-win` 提交 `fbec819`，对照 `origin/main` `4cedf910173cf40d927f1d7db9fc12dfd5f469ab` 上的整份 Windows 实现。产品行为以本目录的需求、技术设计、交互、UI 规格、决策 D1–D39 和备份格式为准。

这次只做静态阅读，没有在 Windows 上编译或运行。Linux 上的测试通过不记为 Windows 验收。下文只收录当前代码已经能确定的问题。真机才能判断的平台行为单独列在末节，不记成缺陷。

严重程度：

- **高**：会损坏唯一的活数据库、使编辑无法再提交，或使撤销恢复出错误数据。
- **中**：可见行为与需求或设计不一致，或存在明确的错误路径。
- **低**：窄边界、文案或辅助名称。主路径仍可用。

共 4 项高、26 项中、8 项低。

## 高

### H1 导入失败可以把活库写到一半

**复核：不成立，不改代码。** 进度见 [任务清单](STATIC_REVIEW_TASKS.md)。SQLite 在目标库上持有写事务；`sqlite3_backup_step` 尚未返回 `SQLITE_DONE` 时，`sqlite3_backup_finish` 会回滚该事务。`Microsoft.Data.Sqlite` 的 `BackupDatabase` 用 `using` 持有备份句柄，`step` 抛错时仍会 `finish`。测试 `DestinationWriteLockCausesBackupFailureAndPreservesLiveData` 已覆盖失败后活库保持原数据。进程在未完成的写事务中退出时，由 SQLite 日志在下次打开时恢复。

原先的判断是：[FR-13](REQUIREMENTS.md) 要求无效或冲突时保留旧库，替换本身是原子的。[`DeskNodesDatabase.ReplaceFrom`](../src/DeskNodes.Core/Storage/DeskNodesDatabase.cs) 的注释写成 “atomic online backup transaction”，实现是对已经打开的活连接调用 `SqliteConnection.BackupDatabase`。这是 `sqlite3_backup_step` 逐页拷贝，不包在事务里。拷贝开始之后若磁盘满或 I/O 失败，目标库不会回到拷贝前的内容。取消只在拷贝开始前检查。

导入顺序是：先为新库准备新建热键候选，再 `ReplaceFrom`，成功后才 `Commit` 热键。`ReplaceFrom` 抛出时候选会被释放，旧热键还在；活库可能已经残缺。浮起热键在替换成功之后注册失败，只记冲突、不回滚数据，这与文档一致，不记在本项。

### H2 取消组词后编辑一直处于组词中

[`EditorCoordinator`](../src/DeskNodes.App/Editing/EditorCoordinator.cs) 在 `PreviewTextInputStart` 和 `PreviewTextInputUpdate` 里把 `Composing` 设为 true，只在 `TextInput` 里设回 false。WPF 里用 Esc 取消候选通常不产生 `TextInput`。`Composing` 保持为 true 之后，400 ms 防抖不再排程，跨天保持 `Deferred`，`AppCoordinator.Run` 在 `TryCommitPending` 不是 `Committed` 时直接返回。结构操作会静默不发生。

技术设计要求候选窗口的焦点不能当成一次结构提交。缺的是取消组词这条路径。完整输入法行为仍要真机确认，见末节。

### H3 多行粘贴把小数当成列表标记

[`PasteParser`](../src/DeskNodes.Core/Services/PasteParser.cs) 的前缀是 `\d+[.)]\s*`。项目符号要求后面有空白，数字标记不要求。`3.14` 会被收成 `14`，`10.5` 会被收成 `5`。[FR-03](REQUIREMENTS.md) 只要求去掉常见列表前缀。测试只覆盖了 `1. one` 和 `2) two`。

### H4 删掉唯一一行再撤销，会留下替补空白行

[`NoteWindow.DeleteRow`](../src/DeskNodes.App/Views/NoteWindow.Editing.cs) 在删除前的快照只剩一项时，`DeleteItem` 之后调用 `CleanupBlankItems`。软删除后活事项为 0，[`CleanupBlankItems`](../src/DeskNodes.Core/Services/NoteActions.cs) 会插入 `sort_order` 为 0 的新空白行。[`DeletionUndoQueue.Undo`](../src/DeskNodes.Core/Services/DeletionUndoQueue.cs) 只 `Update` 被软删除的旧行。`Ctrl+Z` 把旧行恢复回来，替补行还在。占位空行上的 Backspace 走同一条路径。

失焦时的空白清理不进撤销队列，那条路径与本项无关。

## 中

### 编辑与撤销

**M1 多行粘贴在提交前就取消了原生粘贴。** [`NoteWindow.Paste`](../src/DeskNodes.App/Views/NoteWindow.Editing.cs) 对非单行结果先 `CancelCommand()`，再 `TryCommitPending`。尾随换行也会被判成非原生粘贴。组词中或提交失败时，这次粘贴被丢掉。`Trim` 同时去掉用户有意保留的首尾空格。首行用一次 `BeginChange` 写入；后续行按 [FR-03](REQUIREMENTS.md) 各自成新事项。

**M2 编辑菜单的「撤销」不是 `Ctrl+Z` 的那一次撤销。** [`CreateEditorMenu`](../src/DeskNodes.App/Views/NoteWindow.Menus.cs) 把「撤销」绑到文本框的 `ApplicationCommands.Undo`。刚删除过、文本撤销栈为空时，菜单项禁用，快捷键提示仍是 `Ctrl+Z`。窗口按键仍会按 [FR-04](REQUIREMENTS.md) 恢复删除。[D7](DECISIONS.md) 要保留的是文字撤销入口。

**M3 `Ctrl+Shift+Z` 会走结构撤销，提交失败时两种撤销都没有。** [`WindowKeys`](../src/DeskNodes.App/Views/NoteWindow.Editing.cs) 用「修饰键里有 Control」判断，因此 `Ctrl+Shift+Z`、`Ctrl+Alt+Z` 都进入 `Key.Z`。判定为结构撤销后，`Run` 即使因未提交而立刻返回，按键仍被标成已处理。非结构撤销会在设置 `Handled` 之前返回，那条是对的。

### 历史

**M4 从未来日期按方向键会跳到今天。** [`CalendarNavigator`](../src/DeskNodes.Core/Presentation/CalendarNavigator.cs) 把 `SelectedDay + direction * days` 钳到 `CurrentBusinessDay`。从未来格按左，不是后退一天，而是直接落到今天。[FR-11](REQUIREMENTS.md) 要求逐日或逐周移动，并且不能越过今天；月导航和点格可以进入未来。`HistoryActionsTests` 把「2026-12-01 向左落到 2026-11-15」锁成了期望。

**M5 历史窗口里任意焦点控件都会吃掉普通方向键。** [`HistoryRules.HandlesNavigation`](../src/DeskNodes.Core/Presentation/HistoryRules.cs) 在「有控件焦点且没有修饰键」时返回 false。[`HistoryWindow.Navigate`](../src/DeskNodes.App/Views/HistoryWindow.xaml.cs) 把「焦点元素是窗口以外的 Control」始终传进去。[FR-11](REQUIREMENTS.md) 和[快捷键表](INTERACTION.md#keys) 写的是：详情文字始终让出方向键；只有启用完整键盘导航时，普通方向键才留给焦点控件。日格 `Focusable` 为 false，点日格后焦点回到窗口。「今天」和翻月按钮可以获得焦点，之后普通方向键不再移动日期。`Ctrl+左`、`Ctrl+右`、`Ctrl+T` 仍然有效。`HistoryRulesTests` 锁的是现在的调用方式。

### 存储与备份

**M6 恢复一张并未删除的便签时，子项恢复仍会提交。** [`NoteRepository.Restore(NoteId)`](../src/DeskNodes.Core/Storage/NoteRepository.cs) 在更新便签行之前，就按 `note_deletion_items` 把成员事项的 `deleted_at` 清掉。`pending_deleted_items` 的删除还要求便签当时仍是删除状态。便签更新影响 0 行时，成员行保留，`return false` 仍会提交事务。

[`Note.Update`](../src/DeskNodes.Core/Storage/NoteRepository.cs) 把 `deleted_at` 当成普通列写回。[`AppCoordinator.Update`](../src/DeskNodes.App/AppCoordinator.cs) 构造 `Note` 时不传 `DeletedAt`，默认是 null。对一张已软删除便签的后续保存会把它写活，并留下 `note_deletion_items`。下一次 [`SoftDelete`](../src/DeskNodes.Core/Storage/NoteRepository.cs) 向该表插入相同 `item_id`。该列是主键，语句没有 `ON CONFLICT`，插入失败会回滚整次删除。单项 `Restore(ItemId)` 在事项并未删除时会在写入前返回。

**M7 `dock_order` 没有上限。** [`Schema`](../src/DeskNodes.Core/Storage/Schema.cs) 的检查只要求 `dock_order >= 0`。读取用 `GetInt32`。大于 2147483647 的手改行会让 `GetNotes()` 抛错，启动无法列出便签。[D31](DECISIONS.md) 要求范围是 0..2147483647。应用里的 `Placement.DockOrder` 是 `int?`，写不出更大的值；备份导入会拒绝。测试只覆盖了导入拒绝。

**M8 回滚本身失败后，连接仍被当成空闲。** [`DeskNodesDatabase`](../src/DeskNodes.Core/Storage/DeskNodesDatabase.cs) 在 `ROLLBACK` 或 `ROLLBACK TO` 抛错时，内层 `finally` 仍把 `transactionDepth` 减到 0 并安排回滚回调。连接没有被标记为不可用。下一次读取可能看到仍开着的事务。这是少见路径。

**M9 备份 JSON 里的重复字段按最后一个值接受。** [`WindowsBackupCodec`](../src/DeskNodes.Core/Backup/WindowsBackupCodec.cs) 的 `JsonSerializerOptions` 没有把 `AllowDuplicateProperties` 设为 false。.NET 10 的默认值是 true。令牌扫描检查深度、长度和数组上限，不记录已经出现过的属性名。第二个 `deleted_at`、`completed` 或 `hotkey_new` 会静默覆盖。正常导出会每个属性写一次。

### 停靠与布局

**M10 每次「停靠到…」写入同一个序号。** [`PopulateNoteMenu`](../src/DeskNodes.App/Views/NoteWindow.Menus.cs) 把 `DockOrder` 设为 `GetNotes().Count`。停靠不新建便签，所以同一条边上多次停靠得到相同整数，直到拖动调用 `ReorderDock` 重写成 0..n-1。相等键按仓库顺序稳定排序，后停靠的便签可以出现在先停靠的前面。[FR-05](REQUIREMENTS.md) 要求同边有顺序。

**M11 停靠拖动的预览和松手位置不是同一个下标。** [`NoteWindow.DockMove`](../src/DeskNodes.App/Views/NoteWindow.Dock.cs) 在指针越过当前页每个可见中心时，`target` 为空。预览用当前页 `visible.Last()` 的边界，记录的下标是 `peers.Count - 1`，包含其他页。松手按这个下标插入。页已满时，放在最后一个可见槽会把便签送到整条边的末尾，也就是溢出列表的末尾。命中一张真实可见便签时，用的是那张的序号。拖出保留带仍恢复 `FreeRestore`。

**M12 一张过高的侧边停靠便签被缩短，却没有溢出标签。** [`DockLayout`](../src/DeskNodes.Core/Presentation/DockLayout.cs) 用未钳制的长度判断溢出，再在可用高度至少 216 DIP（最短便签 120 加溢出条 96）时先扣掉 96 DIP 再排布。一张高于这段可用高度的便签被钳到第 0 页，`Overflow` 仍为空。[`PresentationCoordinator`](../src/DeskNodes.App/PresentationCoordinator.cs) 只在 `Overflow.Count > 0` 时显示标签。例如可用 300、便签 400 时，便签被排成 204，旁边留下空档。测试只在数量大于 1 时要求出现溢出标签。

**M13 自动增高只改了 Win32 的顶边。** [`MeasureHeight`](../src/DeskNodes.App/Views/NoteWindow.Layout.cs) 用 `SetWindowPos` 把顶边钳进工作区，不写 WPF 的 `Top`。靠近工作区底部长高的便签会被 Win32 挪上去，下一次 WPF 布局再把它拉回去。`Place` 会同时写 WPF 的 `Left`/`Top` 和 `SetWindowPos`。

### 工具条

**M14 收缩被打断后，看不见的按钮仍能点到。** [`ToolbarWindow.Down`](../src/DeskNodes.App/Views/ToolbarWindow.Input.cs) 增加 generation 并停掉帧计时。收缩的 `finished` 因此不再收起 `Parts`。透明度可以已经是 0，这些按钮仍然参与命中。圆形标签不参与命中，所以右键会落在隐藏按钮上，`OpenMenu` 直接返回。

**M15 边缘唤起的命中层被放进普通窗口的最上面。** [`PlacePopupBehindActiveApplications`](../src/DeskNodes.App/Views/ToolbarWindow.xaml.cs) 使用 `HWND_NOTOPMOST`（-2）。这会取消置顶，并把窗口插到普通 Z 序的顶部，仍在其他应用之上。入口填充是 `#01000000`，别的应用盖住这条边时它仍能收到点击。[FR-08](REQUIREMENTS.md) 要求边缘唤起只在入口真正露出来时生效。入口和数量提示打开时都会走这里。

**M16 停在数量叠放提示上会开始闲置计时。** 指针是否在内部只看工具条和入口命中层。叠放提示是另一个弹出层，不调用 `Tick`。鼠标放在提示上时闲置计时继续，下一次收缩会关掉提示。

**M17 减少动画时，过渡结束会跑两次。** 减少动画的 `Transition` 直接调用 `finished()`，不停止帧计时。下一帧把已经减少动画的经过时间当成时长，再调用一次 `finished`。`SavePreferences` 和 `AnimationCompleted` 会各跑两次。

**M18 文字缩放 1.5 时，手柄和圆形入口不重合。** [`ToolbarGeometry.FullSize`](../src/DeskNodes.Core/Presentation/ToolbarGeometry.cs) 的短边是 `64 * max(1, textScale)`。展开的横轴中心用固定的 32 DIP 和沿边 ±28。圆形入口在文字缩放 1 时是 56 DIP，放在工作区角上。缩放 1.5 时，顶边或底边上的垂直工具条、左边或右边上的水平工具条，手柄会偏离圆形入口 16 DIP。贴住屏幕边的那一轴仍由 `Fit` 对齐。测试 `ExpandedHomePreservesTheHandleEntrance` 只用缩放 1。[FR-08](REQUIREMENTS.md) 要求手柄端留在圆形入口上。小于 1 的文字缩放不会缩小命中目标（`Math.Max(1, Scale)`），字号仍会变小。

**M19 悬停展开后的 1.5 秒宽限，不会被拖动或菜单重置成完整闲置。** [`ToolbarIdleMachine`](../src/DeskNodes.Core/Presentation/ToolbarIdleMachine.cs) 只在 `Operated` 或 `Clicked` 时清掉宽限。拖动、菜单打开、设置可见只把截止时间设成空，宽限标志还在。只靠悬停展开再离开后，宽限为真；接着拖动或打开菜单，下一次等待仍是 1.5 秒，而不是 10、15 或 30 秒。菜单关闭时的 `Tick()` 没有带 `Operated: true`。[FR-08](REQUIREMENTS.md) 要求菜单或打断重新计算完整闲置。测试从冷的工具条开始，宽限一开始就是 false。

**M20 混合 DPI 下拖完整工具条会跳。** [`ToolbarWindow`](../src/DeskNodes.App/Views/ToolbarWindow.Input.cs) 在按下时用那块屏幕的 DIP 记下 `grabOffset`，指针换屏之后仍减去这个数。两块屏幕的 DIP 不是同一个空间。圆形入口拖动走物理点的 `ProjectHome`，不在本项。

### 展示、设置与外观

**M21 未处理异常没有标记为已处理，退出也不冲掉编辑缓冲。** [`App.OnStartup`](../src/DeskNodes.App/App.xaml.cs) 的 `DispatcherUnhandledException` 显示对话框并 `Shutdown(1)`，没有把 `args.Handled` 设为 true。WPF 仍把它当作未处理异常。这条路径上的 `Stop()` 不等待 400 ms 编辑缓冲。菜单里的退出会先走 `Run`。

**M22 全局收起被第一张便签的结束回调提前关掉。** [`Collapse`](../src/DeskNodes.App/PresentationCoordinator.cs) 给每张可见便签调用一次 `Present`（0.28 秒）。回调里先 `state.Complete`，再 `Refresh`。刷新时，只要过渡不再是 `Collapsing`，或者隐藏原因不只是收起，窗口就被 `Hide`。第一张结束之后，其余仍在动画里的便签被藏起来。减少动画时 [`Present`](../src/DeskNodes.App/Views/NoteWindow.Presentation.cs) 在方法内部同步调用回调，循环还没走完过渡就结束了。更新的 `Request` 会增加 generation，旧回调被丢掉，这一条是对的。

**M23 点溢出标签后，便签会停在临时置顶。** [`SelectDockNote`](../src/DeskNodes.App/PresentationCoordinator.cs) 在 `Refresh` 之后调用 `SetTemporarilyRaised(true)`。这个方法里没有再把它设回去。[`WindowLevelService`](../src/DeskNodes.App/Platform/WindowLevelService.cs) 于是使用 `HWND_TOPMOST`。下一次刷新会按「正在浮起或正在多选」重算；切到其他应用时 `EndRaised` 也会按是否仍在多选收回。[FR-05](REQUIREMENTS.md) 要求溢出标签把对应便签显示出来。

**M24 从工具条或托盘进入多选时，键盘没有落点。** [`EnterSelection`](../src/DeskNodes.App/PresentationCoordinator.cs) 显示覆盖层和操作条，不把焦点给任何便签。[`PresentationBar`](../src/DeskNodes.App/Views/PresentationBar.xaml.cs) 设置 `WS_EX_NOACTIVATE`，自己不处理按键。`Esc`、`Ctrl+A`、`Delete` 只从便签的 `PreviewKeyDown` 进入 [`Keys`](../src/DeskNodes.App/PresentationCoordinator.cs)。[FR-15](REQUIREMENTS.md) 要求这些键在模式内可用。条上的按钮仍可用指针操作。空白点击清选择且不退出，这一条是对的。

**M25 快捷键保存被拒绝后，按钮仍显示被拒绝的组合。** [`SaveHotkey`](../src/DeskNodes.App/Views/SettingsViewModel.SystemServices.cs) 在 `catch` 里设置 `HotkeyError`，不调用 `CancelRecording`。录制标志还在时，`NewHotkey` 和 `FloatHotkey` 返回刚录下的字符串。错误文案写的是原快捷键已保留。其他设置在保存被拒绝后会再通知一次，把界面绑回已保存的值。

**M26 高对比下，日格档位只靠透明度区分。** [`HighContrast.xaml`](../src/DeskNodes.App/Themes/HighContrast.xaml) 里 `HistoryWeak` 和 `HistoryBackground` 都是系统 Window 色。日格的低、中、满三档共用 `HistoryProgress`（Highlight），不透明度来自 [`ShadeOpacity`](../src/DeskNodes.Core/Services/HistoryQueries.cs) 的 0.18、0.38、0.62。[UI 规格](UI_SPEC.md#selection) 写明高对比不能把低透明度当作唯一反馈。历史按钮禁用时只有 0.45 的透明度。多选遮罩是 Window 色加 0.5 透明度；已选便签仍有 Highlight 描边。七色便签在高对比下收成 Window，选中收成 Highlight，这与「用语义色替换装饰色」一致，不单列。

## 低

**L1 启动失败一律说无法打开数据库。** [`App.OnStartup`](../src/DeskNodes.App/App.xaml.cs) 的总 `catch` 使用这句话。偏好、字体或热键在数据库已经打开之后失败，对话框仍这么写。

**L2 折叠后的摘要文字不能拖。** [`HeaderDrag`](../src/DeskNodes.App/Views/NoteWindow.Layout.cs) 只在事件源就是标题网格时开始拖动。折叠摘要 `TextBlock` 可以命中，没有自己的鼠标处理。顶部 30×10 的手柄仍可拖。[FR-05](REQUIREMENTS.md) 要求非编辑标题区域拖动。

**L3 收起落点在约 6 DIP 的窄带里会左右分开。** [`CollapseGeometry.Target`](../src/DeskNodes.Core/Presentation/CollapseGeometry.cs) 按每一层单独判断是否超出工作区右缘。层 0 和层 1 可以留在右侧，层 2 翻到左侧。

**L4 历史窗口和字体授权窗口不处理 `Ctrl+,`。** 便签和工具条会打开设置。快捷键表把 `Ctrl+,` 列为进入设置的键。历史窗口只通过 [`AuxiliaryWindowShortcuts`](../src/DeskNodes.App/Views/AuxiliaryWindowShortcuts.cs) 转发 `Ctrl+N`。[`LicenseWindow`](../src/DeskNodes.App/Views/LicenseWindow.xaml.cs) 没有按键处理。

**L5 分母为 0 的日期，辅助说明说完成率 0%。** 月标题在 `Total == 0` 时是「—」。[`HistoryViewModel`](../src/DeskNodes.App/Views/HistoryViewModel.cs) 把 `Rate ?? 0` 写进日格的 `HelpText`。自动化名称只有日期。`HelpText` 不是 UIA 名称。Narrator 是否读出说明，见末节。

**L6 框选的起拖阈值是 5 个物理像素。** [`MoveBox`](../src/DeskNodes.App/PresentationCoordinator.cs) 用 `GetCursorPos` 的曼哈顿距离。缩放到 200% 以上时，一次很小的点击会变成拖动。

**L7 几处自动化名称丢掉了状态。** 最近删除的按钮内容只有「恢复」，多张卡片无法区分。字体卡片的 `AutomationProperties.Name` 只有字体名，可见的「未安装」不在名称里。设置里的热键按钮名称是「全局新建」和「全局浮起」，当前组合不在名称里。

**L8 点工具条滚动会把键盘焦点从便签拿走。** [`ToolbarScroll`](../src/DeskNodes.App/Themes/Toolbar.xaml) 把 `Focusable` 设为 true，盖过动作按钮的 `Focusable` false。四个主按钮仍然不能获得焦点。

## 测试没有锁住的缺陷

这些测试现在是绿的，锁住的是有问题的行为，或者根本没走到有问题的输入。

- 粘贴测试没有 `3.14` 或 `10.5`。
- 编辑会话测试只通过 `SetComposition(false)` 结束组词，没有 Esc 取消。
- `HistoryActionsTests` 期望从 2026-12-01 向左落到 2026-11-15。
- 仓库恢复测试只恢复一张仍处于删除状态的便签。
- 停靠分页测试只在数量大于 1 时要求溢出标签。
- 手柄与入口重合只在文字缩放 1 时断言。
- 闲置宽限测试从冷工具条开始。
- 导入锁测试在写出任何备份页之前就失败，没有覆盖拷贝中途失败。
- 没有「删除唯一事项再撤销，仍然只有一行」的测试。
- 没有「连续两次菜单停靠得到不同 `dock_order`」的测试。

## 已核对且与现行设计一致

下列路径读过源码，不列入上面的缺陷。

- 非结构的 `Ctrl+Z` 在标记已处理之前返回，交给文本框。
- 热键修饰值与 `MOD_ALT`、`MOD_CONTROL`、`MOD_SHIFT` 一致。录制时 `WM_HOTKEY` 走 `Recorded`，不触发动作。
- 设置里除快捷键显示以外的保存失败会再通知，把控件绑回已保存的值。开机启动和跨天时间也是。字体或字号被拒绝时在发布之前抛出。
- 托盘菜单在 `Opening` 时重建。`DisposeItems` 卸下子项并释放 `ToolStripControlHost`。`Stop` 释放图标、`NotifyIcon` 和菜单。
- `SetWindowRgn` 返回 0 时删除区域；成功时区域所有权交给窗口。
- 多选：空白点击清空且不退出；按下时按住 Ctrl 才追加；相交用物理矩形；没有选中时删除不可用；删除后退出。
- 历史读取失败进入失败态，空状态保持收起。过期的 `HistoryGeneration` 丢掉结果。
- 虚拟桌面查询失败时当作仍在当前桌面。轮询只在 `IsCurrent` 与 `OtherDesktop` 标记不一致时刷新。
- 跨天在外层事务里使用保存点。编辑器的 `Committed` 要等外层提交。这条本身不构成用户可见错误。
- 整理翻页和停靠翻页的界面入口经过 `Run`。`ChangePage` 和 `Collapse` 本身不提交；工具条和托盘的调用先提交。
- 单实例管道使用 `ConfigureAwait(false)`。互斥体是 `Local\`，管道名另加会话号，同一会话内一致。
- 登录项只写本应用的 Run 值，启动时不重写。隔离数据目录、无引号路径、路径中的引号，以及进程名为 `dotnet` 时拒绝修改。
- 清单声明了 Windows 10 的 supportedOS，因此 `Environment.OSVersion` 能读到真实构建号。DWM 偏好只在构建号大于等于 22621 时设置。
- 自由便签用 `DragMove`，靠边不自动停靠。拖出停靠保留带之后恢复自由几何。
- 失焦清理空白是后台调用，菜单打开、正在移除、焦点仍在窗口内或仍在组词时跳过，并且不进撤销队列。
- 停靠页下标的取模写法与数学结果一致。
- 文本缩放服务会在登录提示前加入 `TextSize16`。减少动画的系统参数读失败时，按减少动画处理。

## 需 Windows 真机确认

这些是实现里已经能看见的平台边界。静态阅读不能判定它们在真机上是否违反需求。

- `IVirtualDesktopManager` 的 BOOL 封送，以及切换虚拟桌面时是否收到 `WM_ACTIVATEAPP`，置顶的多选覆盖层会不会留在新桌面上。代码里的轮询间隔是 1 秒。
- 收起的 0.28 秒里，WPF 的 `Left` 与按该窗口 DPI 调用的 `SetWindowPos` 是否互相改写。覆盖层的 DIP 与像素位置是否对齐。
- 分层覆盖层和便签 `HWND_TOPMOST` 之间，点击落在哪一层。
- Narrator 是否朗读日格的 `HelpText`，以及 `WS_EX_NOACTIVATE` 操作条的按钮能否从 UIA 调用、是否不在 Tab 顺序里。
- 每屏 `Place` 同时写 WPF 位置和 `SetWindowPos` 时，混合 DPI 下是否打架。M13 的顶边钳制是已经确定的代码差异。
- 单实例目录哈希使用 `GetFullPath` 和去掉末尾分隔符。联接、尾点路径是否会被收成两个实例。
- 组词候选、AltGr 与全局热键、Mica／Acrylic 及高对比切换、系统大文本。H2 的取消路径是静态缺口；候选窗口的焦点行为仍要真机看。
- 收起动画里 `target * (工具条 DPI / 便签 DPI)` 是否正好落在便签窗口自己的坐标系里。
