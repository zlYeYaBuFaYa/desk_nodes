# DeskNodes 验收、追溯与一致性记录

日期：2026-11-12；基线 `4ec6ac4caa6ac84e49aa8b8dbbc4225a319fbf1f`。下文测试结果为初次整理时的记录；本轮只调整文档与相关静态检查，不重新验证工作区后续业务改动。

## 1. 结论边界

“源码存在”“自动测试通过”“签名应用真实操作通过”是三种不同证据。本次已阅读源码并运行当前 Mac 测试；没有启动个人数据目录中的应用，没有验证系统登录项、全屏 Space 或外接显示器。原型检查只证明说明文件自身可用。

## 2. 需求到代码与测试的追溯

- **FR-01 启动／空状态**：`Sources/DeskNodesApp/Application.swift`、`AuxiliaryWindows.swift`、`Toolbar.swift`；参考 `Tests/DeskNodesAppTests/DesktopRedesignTests.swift`。仍需人工检查无 Dock 图标、菜单恢复和关闭辅助窗口。
- **FR-02 新建／颜色**：`Application.swift`、`Desk.swift`、`Sources/DeskNodesActions/NoteActions.swift`、`Sources/DeskNodesCore/DesignTokens.swift`；参考 `NoteActionsTests.swift`、`DesignTokensTests.swift`、`DesktopRedesignTests.swift`。人工检查首字符和中文焦点。
- **FR-03 输入／排序**：`NotePanel.swift`、`NoteTextView.swift`、`NoteSurfaces.swift`、`EditorSynchronization.swift`；参考 `EditingImprovementTests.swift`、`NativeFoundationTests.swift`、`NoteActionsTests.swift`。原双视图同步失败用例已随边缘面板移除，见 §3.3。
- **FR-04 删除／恢复**：`NoteActions.swift`、`DeletionToast.swift`、`RecentlyDeleted.swift`、`RecentlyDeletedView.swift`；参考 `RecentlyDeletedTests.swift`、`NoteActionsTests.swift` 中的恢复／删除栈测试、`HistoryPresentationTests.swift`。人工检查真实计时和多次删除。
- **FR-05 自由／停靠／尺寸**：`WindowState.swift`、`Docking.swift`、`DockController.swift`、`WindowChrome.swift`；参考 `WindowStateTests.swift`、`DockingTests.swift`。人工检查触摸板、屏幕和 Dock 可用区域。
- **FR-06 整理／分页**：`Arrangement.swift`、`Desk.swift`、`PresentationDefaults.swift`；参考 `ArrangementTests.swift`、`ToolbarGeometryTests.swift`。人工检查真实容量、分页编辑和多屏。
- **FR-07 三类折叠边界**：`Desk.swift`、`Toolbar.swift`、`WindowState.swift`；参考 `ArrangementTests.swift` 的 DeskPresentation 测试和 `DesktopRedesignTests.swift`。快速反向动画仍需录像验收。
- **FR-08 工具条形态／吸边**：`Toolbar.swift`、`ToolbarGeometry.swift`、`PresentationDefaults.swift`、`SettingsWindow.swift`；参考 `ToolbarGeometryTests.swift`、`DesktopRedesignTests.swift`。计时／手势中断没有被几何测试充分证明。
- **FR-09 层级／浮起**：`WindowChrome.swift`、`WindowState.swift`、`Desk.swift`、`Application.swift`；参考 `DesktopRedesignTests.testPeekLiftsRealNotesTemporarilyAndYieldsToTopmost`、`NativeFoundationTests.testOnlyTopmostNotesJoinFullscreenSpaces`。真实激活、Esc、切换应用放回、全屏 Space 与多屏未验收。
- **FR-10 跨天**：`BusinessDay.swift`、`Store.swift`、`AutomaticBackup.swift`、`Application.swift`；参考 `RolloverTests.swift`、`RolloverCompatibilityTests.swift`、`OptimizationTests.swift`。测试中的注入时钟不等于真实睡眠唤醒。
- **FR-11 历史**：`History.swift`、`HistoryWindow.swift`、`Store.swift`；参考 `HistoryTests.swift`、`HistoryPresentationTests.swift`。人工检查长内容、无数据、深色和日历导航。
- **FR-12 设置／系统服务**：`SettingsWindow.swift`、`SystemServices.swift`、`Preferences.swift`；参考 `HotkeyTests.swift`（含浮起快捷键默认值／冲突／旧载荷）、`SettingsIntegrationTests.swift`、`EdgeSettingsTests.swift`（遗留字段持久化）。注册真实 Carbon 热键冲突、登录项需单独测试。
- **FR-13 备份**：`Backup.swift`、`SQLite.swift`、`Schema.swift`、`Application.swift`；参考 `BackupTests.swift`、`ImportUndoTests.swift`、`StoreTests.swift`、`StruckItemTests.swift`（schema 8 迁移、划掉归档、schema 7 备份导入）。人工验证文件面板和 signed app 重启。

上述测试文件按其现有目录位于 `Tests/DeskNodesCoreTests/`、`DeskNodesPersistenceTests/`、`DeskNodesActionsTests/`、`DeskNodesAppTests/`；没有为本次文档新增业务测试。

## 3. 本次实际检查

### 3.1 工具链与测试

实际读取：`xcode-select -p` 为 `/Applications/Xcode.app/Contents/Developer`；`xcrun swift --version` 返回 Apple Swift 6.4.2、arm64 目标。此为本机测量，不是新增最低版本承诺。

第一次 `xcrun swift test` 因默认 `~/.cache/clang/ModuleCache` 不可写而在 manifest 编译前失败。为避免改动用户工具链配置，使用临时缓存重试：

```sh
CLANG_MODULE_CACHE_PATH=/tmp/desknodes-docs-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/desknodes-docs-swift-cache \
xcrun swift test --disable-sandbox --cache-path /tmp/desknodes-docs-spm-cache
```

构建完成，测试命令退出码 **1**。四个 XCTest 目标合计 **192 个测试方法，191 个通过、1 个失败；失败方法内 2 处断言失败**：

- DeskNodesCoreTests：6 个，全部通过。
- DeskNodesPersistenceTests：73 个，全部通过。
- DeskNodesActionsTests：80 个，全部通过。
- DeskNodesAppTests：33 个，32 个通过、1 个失败。

失败方法：`NativeFoundationTests.testTwoSurfacesSynchronizeWithoutPassiveFlushOrMarkedReplacement`，位置 `Tests/DeskNodesAppTests/NativeFoundationTests.swift:279`、`:281`。预期数据库和被动编辑视图均为 `new 中文`，实际仍为 `first`。涉及桌面／边缘双视图的编辑提交和同步；本次不能据此断言失败是产品缺陷还是测试会话／焦点条件所致，需在后续修复任务复现定位。

本次未修改该测试或业务代码，不把失败隐藏为“测试全通过”。末尾 Swift Testing 的“0 tests”是额外 runner 输出，不能覆盖 XCTest 的失败结果。

### 3.3 后续改动（划掉事项、浮起、工具条去删除）

在提交 `12b21f9` 之后的工作区上运行 `swift test`：四个 XCTest 目标 **186 个测试全部通过**（Core 6、Persistence 78、Actions 69、App 33），`scripts/check-n*.py` 全部通过。边缘面板相关的 `EdgeRevealTests`、`SharedRevealTests` 与双视图同步用例随功能删除；§3.1 的失败用例因此不再存在，不代表其根因已定位。仍未启动签名应用做真实交互验收。

执行日志在本机会话 `/tmp/desk-nodes-docs-swift-test.log`，属于临时诊断文件，不是仓库长期交付物。未执行 release 打包、签名或真实 .app 启动。

### 3.2 文档与原型检查范围

已检查六份新增 Markdown 的本地链接，未发现断链；原型 JavaScript 经 Node 语法解析通过。使用不包含浏览器或布局引擎的最小 DOM 适配器执行演示模型，22 处状态断言通过，覆盖新建、七色补缺、整张／事项删除与恢复、全局收起独立性、圆形前置条件、整理、历史统计、无快照提示、设置分组、空场景及用户文本转义。

核对七色、六动作、工具条尺寸／时间、备份 version／schema 与源码一致；原型是简化说明模型，未重复实现所有原生算法。

**浏览器视觉预览未完成**：浏览器工具安全策略拒绝 `file://` 协议访问本地原型。本次未绕过该限制，也未使用截图声称视觉验证通过。原型的实际浏览器排版、点击命中、拖动和动画仍需用户打开文件检查；上述 22 处断言只证明模型逻辑，不证明浏览器事件或渲染。HTML 文件没有外部脚本、字体或远程资源依赖。

## 4. 原生人工验收步骤

以下均为待执行，不因有对应测试而自动打勾。使用隔离 `DESKNODES_DATA_DIR` 和独立备份，避免拿真实清单做破坏性试验；该设置不会自动隔离系统登录项。

### A. 启动和主工作流

- [ ] 空库启动只有工具条及首次登录询问；拒绝后重启不再询问。
- [ ] 菜单栏和无 Dock 图标符合预期；关闭设置／历史后主流程仍可用。
- [ ] 连续新建七张，颜色各不相同；删除一张后再新建优先补缺色。
- [ ] 新建后立即输入中文首字符不丢；全局收起时快捷键新建先恢复便签。
- [ ] 工具条没有删除按钮；从便签“更多”菜单删除只删该张。
- [ ] 删除最后一张后只剩工具条；五秒内撤销恢复，五秒后使用最近删除。

### B. 输入与事项操作

- [ ] 输入中文／英文／数字／混排／多行，圆圈对齐第一行，标题不因悬停跳动。
- [ ] 拼音组词中 Return 只确认候选，不新增；结构删除、导入导出、跨天和退出不会丢 marked text。
- [ ] 多行粘贴拆项、空行过滤、箭头跨行、⌘Return 和文字撤销正确。
- [ ] 悬停事项显示划掉、删除（22pt，悬停底板，删除变红）与排序手柄，按钮不遮挡正文；⌘⇧X 切换划掉。
- [ ] 划掉与完成互斥；划掉不计入“完成／总数”，跨天归档且不顺延，历史以删除线显示且不计入完成率。
- [ ] 设置中新建宽度／高度生效于之后新建的便签；固定高度可在菜单恢复“随内容”。

### C. 布局与状态

- [ ] 自由便签拖动／缩放后重启恢复；靠边仍自由，显式停靠和拖出可用。
- [ ] 单张折叠、全局收起、工具条圆形组合不互相改写，叠放提示／角标一致。
- [ ] 整理按屏幕稳定排布，避开完整工具条目标；溢出出现可访问分页。
- [ ] 圆形时新建／整理，再展开工具条仍不覆盖自动放置的便签；手动内容不承诺自动避让。
- [ ] 快速反复收起／展开与删除／撤销，不遗留透明窗口或半透明卡片。

### D. 工具条

- [ ] 横／竖 × 自由／四边；最长“取消置顶”完整，小屏滚动保留手柄。
- [ ] 81pt 阈值内外、角落同距、显示器接缝、拖动预览和 8pt 最终间距正确。
- [ ] 闲置 10／15／30 秒、关闭、设置打开、鼠标停留、VoiceOver、睡眠唤醒均正确重计时。
- [ ] 圆形悬停 140ms、外部拖放经过、1.5 秒宽限、单击及 ≥4pt 拖动不误触按钮。
- [ ] 收缩中移入、展开中拖动、切方向和断开屏幕连续恢复，无跳变和透明热区。

### E. 层级、全屏和多屏

- [ ] 普通应用前台，便签默认被遮挡；单张与全局置顶正确，关闭全局仍保留单张置顶。
- [ ] 全屏应用中工具条可访问；点“浮起”或按 ⌃⌥F，全部便签原地出现在全屏应用之上且可直接编辑。
- [ ] Esc、再按一次、切换到其他应用都能放回；组词中 Esc 只交给输入法；全部置顶时浮起禁用，开启置顶会结束浮起。
- [ ] 收起状态下浮起先展开；浮起快捷键可录制、清除，与新建快捷键相同时报错。
- [ ] 系统拒绝激活时，按钮／菜单／快捷键仍可放回。
- [ ] 外接屏断开／排列改变／Dock 自动隐藏、不同缩放比下入口均可达。

### F. 跨天、历史和数据

- [ ] 默认 04:00 规则和自定义时间正确；睡眠跨日只封存上次观察日，不补造中间快照。
- [ ] 已完成移出 live，未完成顺延；历史保持只读，删除标记和完成率口径正确。
- [ ] 30 天内整张／单项恢复，不改封存历史；空白行清理不污染最近删除。
- [ ] 导出后导入到隔离库，核对 ID、文本、顺序、归档、历史、布局、设置和检查点。
- [ ] 无效文件、取消、组词和快捷键冲突均保留原数据；成功导入清旧撤销而保留本机展示偏好。
- [ ] 跨天自动备份保留 7 份；应用退出后用副本恢复，主库和 WAL／SHM 不混用。
- [ ] 登录项在稳定签名路径上检查拒绝、同意、待批准、关闭和重新登录；不以保存的意愿值代替 OS 状态。

### G. 可读性与辅助功能

- [ ] 浅／深色文字与禁用态清楚；长标题、长事项、无标题、超多数据不截断关键操作。
- [ ] 减少动态效果不残留位置错乱；VoiceOver 可识别入口、完成按钮、月份导航和恢复。

## 5. 已知差异与待验证项

1. 原始需求／README 中八色、旧尺寸、旧测试数与当前代码不同；边缘唤出已由浮起取代。本套文档已按整理基线源码订正；重复旧资料已在本轮清理中删除，旧版本可通过 Git 历史追溯。
2. 原双视图同步失败用例已随边缘面板删除，未定位根因；单视图编辑提交仍需真机验收。
3. 工具条形态方案包含较细的手势与计时要求，现有纯几何测试不能充分覆盖真实中断动画和指针事件；保留人工录屏门槛。
4. 浮起依赖应用激活检测离开；不使用全局监听，因此若系统未让 DeskNodes 成为活动应用，只能用按钮／菜单／快捷键放回。
5. UserDefaults 展示偏好保留到导入后；导入 note placement 仍会更换业务布局。旧分页 ID 与导入布局组合还需按实际导入场景验收。
6. 最近删除 30 天仅列表范围，底层恢复方法本身没有独立的 30 天校验，不等于物理清理策略。
7. 工具条可以覆盖用户手动摆放的便签；避让只在新建、整理和停靠规划时保证。新建在屏幕已满时可级联重叠，整理超容量才分页。
8. 未承诺内存阈值、断电恢复保证、所有系统窗口之上的层级或所有 CPU 架构的可用性。

## 6. 后续变更记录模板

每次更新记录日期、代码 SHA、影响的 FR 编号、文档修改点、实际命令与退出码、原生截图／录屏位置、失败用例和未执行项。禁止用“设计图看起来正确”替代真实输入、焦点、数据或系统服务验证。


## 7. 本轮目录与重复资料清理

六份新增文档与一个 HTML 原型移入 `docs/`，总览改名为本目录 `README.md`；项目根目录 README 保留简介、构建入口及文档链接。

保留独立构建／签名／离线恢复指南和桌面设计效果图；删除 29 个被取代的旧文档及原型资源。旧资料在 Git 中有历史记录，无需在现行文档树中重复保留。

静态检查 `check-n1.py`、`check-n8.py`、`check-n9.py`、`check-n10.py` 改为引用现行 UI 文档和原型；`check-n7.py` 的文档说明同步更新。旧资料字节冻结脚本、清单和专用测试一并退役，因为用户明确要求删除被取代材料；应用源码与 Swift 测试不因这次清理修改。

迁移后已检查全部现存 Markdown／HTML 的本地链接，未发现断链，HTML 脚本语法解析通过；五个静态脚本 `check-n1.py`、`check-n7.py`、`check-n8.py`、`check-n9.py`、`check-n10.py` 在本轮执行时全部通过。未重新执行 Swift 测试或原生应用验收，不将本轮静态检查结果用于推断正在进行的业务改动已通过验证。
