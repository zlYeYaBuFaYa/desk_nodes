# DeskNodes 验收

本文件只记录验证覆盖和结果。预期产品行为以 [功能与交互](REQUIREMENTS.md) 为准，视觉参数以 [UI 规格](UI_SPEC.md) 为准，构建和隔离运行步骤见 [本机操作指南](native-build.md)。

## 自动覆盖

| 需求 | 主要测试入口 |
| --- | --- |
| [FR-01–02](REQUIREMENTS.md#fr-01) 启动与新建 | [DesktopRedesignTests](../Tests/DeskNodesAppTests/DesktopRedesignTests.swift)、[NoteActionsTests](../Tests/DeskNodesActionsTests/NoteActionsTests.swift)、[DesignTokensTests](../Tests/DeskNodesCoreTests/DesignTokensTests.swift) |
| [FR-03](REQUIREMENTS.md#fr-03) 输入与编辑 | [EditingImprovementTests](../Tests/DeskNodesAppTests/EditingImprovementTests.swift)、[NativeFoundationTests](../Tests/DeskNodesAppTests/NativeFoundationTests.swift)、[NoteSurfacesTests](../Tests/DeskNodesAppTests/NoteSurfacesTests.swift) |
| [FR-04、FR-15](REQUIREMENTS.md#fr-04) 删除、多选与撤销 | [NoteActionsTests](../Tests/DeskNodesActionsTests/NoteActionsTests.swift)、[RecentlyDeletedTests](../Tests/DeskNodesPersistenceTests/RecentlyDeletedTests.swift)、[ImportUndoTests](../Tests/DeskNodesActionsTests/ImportUndoTests.swift) |
| [FR-05–09](REQUIREMENTS.md#fr-05) 窗口、布局与工具条 | [WindowStateTests](../Tests/DeskNodesActionsTests/WindowStateTests.swift)、[DockingTests](../Tests/DeskNodesActionsTests/DockingTests.swift)、[ArrangementTests](../Tests/DeskNodesActionsTests/ArrangementTests.swift)、[ToolbarGeometryTests](../Tests/DeskNodesActionsTests/ToolbarGeometryTests.swift) |
| [FR-10–11](REQUIREMENTS.md#fr-10) 跨天与历史 | [RolloverTests](../Tests/DeskNodesPersistenceTests/RolloverTests.swift)、[HistoryTests](../Tests/DeskNodesPersistenceTests/HistoryTests.swift)、[HistoryPresentationTests](../Tests/DeskNodesAppTests/HistoryPresentationTests.swift) |
| [FR-12–14](REQUIREMENTS.md#fr-12) 设置、数据交换与字体 | [SettingsIntegrationTests](../Tests/DeskNodesAppTests/SettingsIntegrationTests.swift)、[BackupTests](../Tests/DeskNodesPersistenceTests/BackupTests.swift)、[NoteFontTests](../Tests/DeskNodesAppTests/NoteFontTests.swift) |
| 纸白轻笺可读性 | [PaperWhiteDesignTests](../Tests/DeskNodesAppTests/PaperWhiteDesignTests.swift)、[DesignTokensTests](../Tests/DeskNodesCoreTests/DesignTokensTests.swift) |

测试文件说明自动覆盖范围；系统级窗口层级、登录项、多显示器组合及真实壁纸材质仍需原生环境检查。字体资源缺失时，文楷相关用例可能跳过。

## 尚待原生人工检查

以下是尚未由自动测试完整覆盖的系统交互类别；每项的具体预期只以对应 [功能章节](REQUIREMENTS.md) 为准。

- [ ] [FR-01–03](REQUIREMENTS.md#fr-01)：启动／退出、快捷键、输入法组词、原生文本编辑和粘贴。
- [ ] [FR-04、FR-15](REQUIREMENTS.md#fr-04)：真实框选、多选状态组合、批量删除与恢复。
- [ ] [FR-05–07](REQUIREMENTS.md#fr-05)：拖动、停靠、整理分页、多显示器、全局收起与恢复。
- [ ] [FR-08–09](REQUIREMENTS.md#fr-08)：工具条闲置、吸边、动画、浮起、系统窗口层级与全屏应用。
- [ ] [FR-10–11](REQUIREMENTS.md#fr-10)：唤醒后的跨天检查、时区变化、历史窗口键盘与辅助功能操作。
- [ ] [FR-12–13](REQUIREMENTS.md#fr-12)：稳定安装路径下的登录项授权、快捷键冲突、数据导入导出与恢复。
- [ ] [FR-14](REQUIREMENTS.md#fr-14)：四档字号、字体组合、中文回退、安装字体和中英混排布局。
- [ ] [UI 规格](UI_SPEC.md)：不同显示器上的浅／深外观、透明度、减少动态效果、长文本和 VoiceOver 可读性。

## 最近一次验证

记录时间：2026-11-16。纸白轻笺展示层更新后，在当时的工作区代码上完成下列检查；本节不表示人工检查清单已通过。

- 完整 `xcrun swift test`：206 项 XCTest 通过，0 失败、0 跳过（Core 8、Persistence 81、Actions 76、App 41）。包含七色深浅对比度与原有便签、工具条、停靠回归。
- `./scripts/build-macos.sh`：release 构建成功；Info.plist 与 ad-hoc 签名校验通过，产物为 `build/DeskNodes.app`。
- `scripts/check-n1.py`、`check-n7.py`、`check-n8.py`、`check-n9.py`、`check-n10.py` 及 `git diff --check`：通过。
- 已查看实际 `NoteCardView` 与 `ToolbarRoot` 离屏生成的七色浅／深预览：`build/design-review/paper-white-light.png`、`build/design-review/paper-white-dark.png`。它们不是运行中桌面的截图，也不验证系统材质合成。
- 测试中发现的固定日期断言已改为依据刷新后的业务日检查边界；生产历史逻辑未改。

完整设计说明见 [纸白轻笺设计](PAPER_WHITE_DESIGN.md)。下一次验证后更新本节的日期、实际命令、结果与证据；未执行的人工检查继续保持未勾选。
