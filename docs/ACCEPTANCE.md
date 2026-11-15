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
- [FR-08](REQUIREMENTS.md#fr-08)、[FR-09](REQUIREMENTS.md#fr-09)：[ToolbarGeometryTests](../Tests/DeskNodesActionsTests/ToolbarGeometryTests.swift) 覆盖吸边、固定位置、角落距离、多屏接缝、入口命中区与停靠预留；DesktopRedesignTests、NativeFoundationTests 覆盖展示偏好与窗口层级。实际闲置计时、右键事件和动画仍需人工验证。
- [FR-10](REQUIREMENTS.md#fr-10)、[FR-11](REQUIREMENTS.md#fr-11)：[RolloverTests](../Tests/DeskNodesPersistenceTests/RolloverTests.swift)、[RolloverCompatibilityTests](../Tests/DeskNodesActionsTests/RolloverCompatibilityTests.swift)、[HistoryTests](../Tests/DeskNodesPersistenceTests/HistoryTests.swift)、[HistoryPresentationTests](../Tests/DeskNodesAppTests/HistoryPresentationTests.swift)、[StruckItemTests](../Tests/DeskNodesPersistenceTests/StruckItemTests.swift)。
- [FR-12](REQUIREMENTS.md#fr-12)、[FR-13](REQUIREMENTS.md#fr-13)：[HotkeyTests](../Tests/DeskNodesPersistenceTests/HotkeyTests.swift)、[SettingsIntegrationTests](../Tests/DeskNodesAppTests/SettingsIntegrationTests.swift)、[BackupTests](../Tests/DeskNodesPersistenceTests/BackupTests.swift)、[ImportUndoTests](../Tests/DeskNodesActionsTests/ImportUndoTests.swift)、[StoreTests](../Tests/DeskNodesPersistenceTests/StoreTests.swift)。
- [FR-14](REQUIREMENTS.md#fr-14)：DesignTokensTests、DesktopRedesignTests 的字号布局与首行圆圈对齐用例；[NoteFontTests](../Tests/DeskNodesAppTests/NoteFontTests.swift) 覆盖字体选择、中文 cascade 与文楷字重。字体资源未获取时文楷用例会跳过，不能据此认为打包字体通过。

## 原生人工检查清单

使用隔离数据运行；每项的预期结果以链接章节为准。

- [ ] [启动与新建](REQUIREMENTS.md#fr-01)：空库仅新建按钮可用，菜单仍可访问、无状态栏图标、关闭辅助窗口不退出；退出时工具条已收缩，重启仍完整展开。结合 [新建](REQUIREMENTS.md#fr-02) 检查全局快捷键、中文首字符、配色与默认／自选尺寸。
- [ ] [输入](REQUIREMENTS.md#fr-03)：中英混排、长行、组词中的 Return／Esc、粘贴拆项、排序、箭头跨行、完成／划掉与文字撤销。
- [ ] [删除与恢复](REQUIREMENTS.md#fr-04)：连续操作、期限边界、最后一张、重启、从最近删除单项恢复及封存历史保持。
- [ ] [多选](REQUIREMENTS.md#fr-15)：各入口、同手势进入框选、追加／替换、空白点击、全选、键盘删除／退出、批次撤销、隐藏页及溢出窗口排除、多显示器拖框。
- [ ] [多选与其他状态](REQUIREMENTS.md#fr-15)：折叠、停靠、收起、原已浮起、组词、切换应用和工具条动作的组合。
- [ ] [自由与停靠](REQUIREMENTS.md#fr-05)：拖动／缩放重启、菜单勾选、取消停靠还原、溢出标签、离线显示器与不同缩放比例；停靠条避让固定入口，工具条收缩／展开及同屏移动时停靠不抖动，修改收缩位置后正确重排。
- [ ] [整理](REQUIREMENTS.md#fr-06)：高矮混排、手动高度、折叠、多屏、分页与重复整理；圆形工具条展开后占位仍正确。
- [ ] [全局收起](REQUIREMENTS.md#fr-07)：反复反向动画、收起时新建／整理／浮起、删除后恢复；工具条回到固定位置后从新入口展开便签，无透明热区或半透明残留。
- [ ] [工具条](REQUIREMENTS.md#fr-08)：四按钮、横竖与各边组合、完整形态吸边阈值、自由位置闲置回归、固定位置原地收缩、先缩后滑与弹簧展开、移动中唤起／拖动；入口到屏幕边的间隙可命中、角落／多屏接缝回退、拖动入口与恢复默认、各闲置选项、悬停宽限、设置／右键菜单打开、VoiceOver 与睡眠唤醒。检查误触展开与减少动态效果。
- [ ] [层级与浮起](REQUIREMENTS.md#fr-09)：桌面、普通应用、全屏应用、多屏；各放回路径、系统未激活时的替代入口与旧全局置顶偏好迁移。
- [ ] [跨天与历史](REQUIREMENTS.md#fr-10)：唤醒跨多日、时区与回拨、组词延迟；核对 [统计口径](REQUIREMENTS.md#fr-11) 与只读状态。
- [ ] [历史菜单与导航](REQUIREMENTS.md#fr-11)：最近快照跨月、业务日标签、完成计数、最近删除计数、无快照／读取失败／零恢复数；点选菜单日期、今天按钮、日／周上限、月导航可到未来、文字选区和完整键盘控制、日格色阶与 VoiceOver；大量历史时菜单读取无可感知停顿。
- [ ] [字号与字体](REQUIREMENTS.md#fr-14)：四档字号 × 四种字体的中英混排、键盘字号、组词拒绝、重启、固定／自动高度与停靠；圆体已安装、下载成功／失败／断网；文楷打包后首次可用、正文 Regular／标题 Medium、授权可打开。对照 [排版](UI_SPEC.md#type) 检查首行圆圈、折叠标题、添加入口与计数，其他界面字体不随选择改变。
- [ ] [设置与系统服务](REQUIREMENTS.md#fr-12)：工具条菜单与 ⌘, 入口、菜单修改后设置同步、三种外观及浅色便签；热键冲突与保留旧值；稳定安装路径下实测首次拒绝、同意、待批准、关闭和重新登录。
- [ ] [导入导出](REQUIREMENTS.md#fr-13)：往返与重启、无效／未来版本／取消／冲突、相同 ID 替换后的旧编辑器与撤销失效，本机偏好和业务布局边界。
- [ ] [恢复操作](native-build.md#recovery)：自动副本轮转、离线目录恢复及侧文件隔离。
- [ ] [可读性](UI_SPEC.md)：深浅色、系统强调色、后台描边、长标题／事项、减少动态效果和 VoiceOver 关键控件。

## 本轮验证记录

2026-11-15，核对代码提交见 [文档入口](README.md)。本轮合并已实现提案、修正需求／技术／UI 差异，移除重复提案、过时 HTML 原型与效果图，并将依赖已删除原型的静态检查转向现行文档；没有修改应用源码或业务测试。

- `python3 scripts/check-n1.py`、`python3 scripts/check-n7.py`、`python3 scripts/check-n8.py`、`python3 scripts/check-n9.py`、`python3 scripts/check-n10.py` 均退出 0，覆盖配色、资源、源码静态契约、保留文档的本地链接与显式锚点。
- `git diff --check` 退出 0；旧文档路径、旧提交基线及已被替换的工具条规则扫描无匹配。
- 未执行 Swift 测试、release 打包或签名应用人工验收。本轮文档核对与静态检查不代表这些项目通过，以上人工清单保持待验收；历史结果由 Git 历史保留。

## 后续记录方式

更新本节的日期、代码提交、实际命令与退出码、证据位置、失败与未执行项；功能的预期结果仍只维护在功能文档，视觉数值仍只维护在 UI 规格。
