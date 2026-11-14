# DeskNodes 验收

验收对照 [功能与交互](REQUIREMENTS.md) 与 [UI 规格](UI_SPEC.md)，不在本文件重新定义规则。构建和隔离操作见 [本机指南](native-build.md)。

## 证据分层

源码存在、静态契约通过、Swift 测试通过、签名应用人工操作通过分别记录。浏览器原型不能证明 AppKit 焦点、输入法、Space、全局热键或登录项正确。

历史阶段执行记录与已移除功能的失败用例由 Git 历史追溯；不把旧测试数量或临时日志路径当作当前结果。下列人工项未标记通过，自动覆盖仅说明有对应测试。

## 自动覆盖入口

- [FR-01](REQUIREMENTS.md#fr-01)、[FR-02](REQUIREMENTS.md#fr-02)：[DesktopRedesignTests](../Tests/DeskNodesAppTests/DesktopRedesignTests.swift)、[NoteActionsTests](../Tests/DeskNodesActionsTests/NoteActionsTests.swift)、[DesignTokensTests](../Tests/DeskNodesCoreTests/DesignTokensTests.swift)。
- [FR-03](REQUIREMENTS.md#fr-03)：[EditingImprovementTests](../Tests/DeskNodesAppTests/EditingImprovementTests.swift)、[NativeFoundationTests](../Tests/DeskNodesAppTests/NativeFoundationTests.swift)、[NoteSurfacesTests](../Tests/DeskNodesAppTests/NoteSurfacesTests.swift)。
- [FR-04](REQUIREMENTS.md#fr-04)、[FR-15](REQUIREMENTS.md#fr-15)：NoteActionsTests、DesktopRedesignTests 以及 [RecentlyDeletedTests](../Tests/DeskNodesPersistenceTests/RecentlyDeletedTests.swift)。批次原子性测试为 testBatchDeleteIsOneUndoEntryAndRollsBackOnFailure；真实框选事件仍需人工验证。
- [FR-05](REQUIREMENTS.md#fr-05)、[FR-06](REQUIREMENTS.md#fr-06)、[FR-07](REQUIREMENTS.md#fr-07)：[WindowStateTests](../Tests/DeskNodesActionsTests/WindowStateTests.swift)、[DockingTests](../Tests/DeskNodesActionsTests/DockingTests.swift)、[ArrangementTests](../Tests/DeskNodesActionsTests/ArrangementTests.swift)。
- [FR-08](REQUIREMENTS.md#fr-08)、[FR-09](REQUIREMENTS.md#fr-09)：[ToolbarGeometryTests](../Tests/DeskNodesActionsTests/ToolbarGeometryTests.swift)、DesktopRedesignTests、NativeFoundationTests。
- [FR-10](REQUIREMENTS.md#fr-10)、[FR-11](REQUIREMENTS.md#fr-11)：[RolloverTests](../Tests/DeskNodesPersistenceTests/RolloverTests.swift)、[RolloverCompatibilityTests](../Tests/DeskNodesActionsTests/RolloverCompatibilityTests.swift)、[HistoryTests](../Tests/DeskNodesPersistenceTests/HistoryTests.swift)、[HistoryPresentationTests](../Tests/DeskNodesAppTests/HistoryPresentationTests.swift)、[StruckItemTests](../Tests/DeskNodesPersistenceTests/StruckItemTests.swift)。
- [FR-12](REQUIREMENTS.md#fr-12)、[FR-13](REQUIREMENTS.md#fr-13)：[HotkeyTests](../Tests/DeskNodesPersistenceTests/HotkeyTests.swift)、[SettingsIntegrationTests](../Tests/DeskNodesAppTests/SettingsIntegrationTests.swift)、[BackupTests](../Tests/DeskNodesPersistenceTests/BackupTests.swift)、[ImportUndoTests](../Tests/DeskNodesActionsTests/ImportUndoTests.swift)、[StoreTests](../Tests/DeskNodesPersistenceTests/StoreTests.swift)。
- [FR-14](REQUIREMENTS.md#fr-14)：DesignTokensTests、DesktopRedesignTests 的字号布局与首行圆圈对齐用例。

## 原生人工检查清单

使用隔离数据运行；每项的预期结果以链接章节为准。

- [ ] [启动与新建](REQUIREMENTS.md#fr-01)：空库、菜单恢复、关闭辅助窗口、重启；结合 [新建](REQUIREMENTS.md#fr-02) 检查全局快捷键、中文首字符、配色与默认／自选尺寸。
- [ ] [输入](REQUIREMENTS.md#fr-03)：中英混排、长行、组词中的 Return／Esc、粘贴拆项、排序、箭头跨行、完成／划掉与文字撤销。
- [ ] [删除与恢复](REQUIREMENTS.md#fr-04)：连续操作、期限边界、最后一张、重启、从最近删除单项恢复及封存历史保持。
- [ ] [多选](REQUIREMENTS.md#fr-15)：各入口、同手势进入框选、追加／替换、空白点击、全选、键盘删除／退出、批次撤销、隐藏页及溢出窗口排除、多显示器拖框。
- [ ] [多选与其他状态](REQUIREMENTS.md#fr-15)：折叠、停靠、收起、原已浮起、组词、切换应用和工具条动作的组合。
- [ ] [自由与停靠](REQUIREMENTS.md#fr-05)：拖动／缩放重启、菜单勾选、取消停靠还原、溢出标签、离线显示器与不同缩放比例。
- [ ] [整理](REQUIREMENTS.md#fr-06)：高矮混排、手动高度、折叠、多屏、分页与重复整理；圆形工具条展开后占位仍正确。
- [ ] [全局收起](REQUIREMENTS.md#fr-07)：反复反向动画、收起时新建／整理／浮起、删除后恢复，无透明热区或半透明残留。
- [ ] [工具条](REQUIREMENTS.md#fr-08)：横竖与各边组合、接缝／角落、阈值两侧、各闲置选项、悬停／单击／拖动、设置打开、VoiceOver 与睡眠唤醒。
- [ ] [层级与浮起](REQUIREMENTS.md#fr-09)：桌面、普通应用、全屏应用、多屏；各放回路径、系统未激活时的替代入口与旧全局置顶偏好迁移。
- [ ] [跨天与历史](REQUIREMENTS.md#fr-10)：唤醒跨多日、时区与回拨、组词延迟；核对 [统计口径](REQUIREMENTS.md#fr-11) 与只读状态。
- [ ] [字号](REQUIREMENTS.md#fr-14)：四档、键盘快捷键、组词拒绝、重启、固定／自动高度与停靠；对照 [排版](UI_SPEC.md#type) 检查对齐和滚动。
- [ ] [设置与系统服务](REQUIREMENTS.md#fr-12)：热键冲突与保留旧值；稳定安装路径下实测首次拒绝、同意、待批准、关闭和重新登录。
- [ ] [导入导出](REQUIREMENTS.md#fr-13)：往返与重启、无效／未来版本／取消／冲突、相同 ID 替换后的旧编辑器与撤销失效，本机偏好和业务布局边界。
- [ ] [恢复操作](native-build.md#recovery)：自动副本轮转、离线目录恢复及侧文件隔离。
- [ ] [可读性](UI_SPEC.md)：深浅色、系统强调色、后台描边、长标题／事项、减少动态效果和 VoiceOver 关键控件。

## 本轮验证记录

2026-11-13，代码基线见 [文档入口](README.md)。本轮只整理文档、演示及其静态契约，没有修改应用源码或业务测试。

- `python3 scripts/check-n1.py`、`check-n7.py`、`check-n8.py`、`check-n9.py`、`check-n10.py` 均退出 0；涵盖现行配色、资源、源码契约及全部 Markdown／HTML 本地链接和显式锚点。
- 提取 UI_PROTOTYPE.html 的内联脚本后执行 `node --check`，退出 0；`git diff --check` 通过。
- 通过仅本机预览服务在浏览器中检查初始布局、设置分组、字号标准切到特大后的示例、新建默认尺寸、瀑布流整理、全选、批量删除与一次撤销恢复全部，未观察到控制台脚本错误。
- 演示检查中修正了隐藏元素样式、设置变更后的刷新，以及删除动画与快速撤销的计时冲突；预览服务检查后关闭。浏览器检查范围仅限说明模型。
- 未重新执行 Swift 测试、release 打包或签名应用人工验收；不引用旧结果代表当前通过。

## 后续记录方式

更新本节的日期、代码提交、实际命令与退出码、证据位置、失败与未执行项；功能的预期结果仍只维护在功能文档，视觉数值仍只维护在 UI 规格。
