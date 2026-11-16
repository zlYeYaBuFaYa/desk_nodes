# DeskNodes Windows 文档入口

核对日期：2026-11-15（America/Los_Angeles）。已有实现（WPF/.NET 10），未在 Windows 真机验收；构建、测试及架构发布状态统一见[当前验证证据](WINDOWS_BUILD.md#当前验证证据)，不代表 Windows 运行结果。

分支 `feat-win` 基于全新 `origin/main` 提交 `4cedf910173cf40d927f1d7db9fc12dfd5f469ab`，该 main 只有初始 README；未继承 feat-mac 代码或分支历史。产品行为来源为远程分支 `feat-mac` 的 `docs/`，提交 `e0b23e660d361fb7963db9c3c1858729ae2ca356`（`docs: align documentation with current implementation`）。该文档声明核对代码提交 `d32a827`。已阅读最新 docs 下现有六份文件：README、REQUIREMENTS、TECHNICAL_DESIGN、UI_SPEC、ACCEPTANCE、native-build，并对照旧基线全文及 Markdown 差异。feat-mac 已移除 HTML 演示和视觉效果图，本轮不以已删除材料为现行依据。macOS 验收与本机构建指南不适用于 Windows，不复制进本目录。

## 文档分工

- [需求与功能](REQUIREMENTS.md)：FR-01 至 FR-15 的 Windows 行为、业务规则及错误边界；产品行为的唯一维护位置。
- [技术设计](TECHNICAL_DESIGN.md)：推荐栈、对象职责、存储与事务、编辑所有权、窗口、系统服务及备份协议边界。
- [UI 规格](UI_SPEC.md)：颜色、字号、尺寸、布局、动画与 Windows 系统铬差异。
- [交互设计](INTERACTION.md)：指针、键盘、托盘、焦点和多窗口事件如何实现需求；不另立业务规则。
- [可行性与验证](FEASIBILITY.md)：逐 FR 与系统行为裁决、多个替代方案、技术栈比较、公开 API 依据和未来验证门槛。

- [Windows 构建与手工验证](WINDOWS_BUILD.md)：字体、发布、数据目录与可执行检查清单。
- [决策记录](DECISIONS.md)：D1–D37 的实现取舍与待验证影响。
- [备份格式](BACKUP_FORMAT.md)：Windows 独立备份协议。

## 维护约定

1. 现有实现不等于已验收；“应／采用／保存”描述仍是产品与设计约束。逐项用源码与 Windows 实测更新，不能把方案、API 存在或 Linux 静态检查写成验收通过。
2. 行为改需求，数值改 UI，机制改技术，可行性裁决和平台证据改可行性。交互文档链接规则，避免双份默认值。
3. Windows 差异必须明确标注，不把 AppKit、Spaces、Carbon 或 SMAppService 名称换皮当作等价实现。公开 API 的支持范围与产品保证分开写。
4. 美观与原生品质优先；个人本地应用，无云同步要求、无内存优化指标。不得为资源指标牺牲文字输入、选区、撤销或视觉完整性。
5. 来源链接与核对日期随变更更新。Windows 版本、.NET 和依赖在实施前重新核对并锁定稳定版本。真机未知项统一标记“需 Windows 真机验证”。
