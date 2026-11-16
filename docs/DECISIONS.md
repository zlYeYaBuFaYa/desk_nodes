# DeskNodes Windows 决策记录

记录日期：2026-11-15。.NET 生命周期依据 [微软支持策略](https://dotnet.microsoft.com/en-us/platform/support/policy)。下列为已采用的实现选择，Windows 行为仍需真机验证；构建步骤见 [WINDOWS_BUILD](WINDOWS_BUILD.md)，产品规则仍以原六份文档为准。

## D1 技术栈与工程结构

- 背景：需要可移植业务逻辑与原生 Windows UI。
- 方案列表（利弊）：WPF/.NET 10 LTS：原生编辑且支持至 2028-11；.NET 8：成熟但支持期止于 2026-11；其他 UI 栈：增加适配成本。
- 推荐／采用：WPF/.NET 10 + Microsoft.Data.Sqlite + 公开 Win32。
- 理由：选择当前 LTS 可延长维护窗口；Core 不依赖桌面框架，业务测试可在 Linux 执行。
- 影响：Core net10.0，App net10.0-windows 并启用交叉编译。
- 需真机验证项：Windows 启动、中文输入及 SQLite 原生库。
- 相关代码／文档：[DeskNodes.App.csproj](../src/DeskNodes.App/DeskNodes.App.csproj)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D2 未发布 schema v1

- 背景：数据库尚未发布。
- 方案列表（利弊）：直接修订 v1：简单；预先写迁移：增加无现存用户的分支。
- 推荐／采用：直接修改 v1，application_id=0x44534B4E（DSKN）。
- 理由：尚无已发布数据库需要兼容；先校验标识与版本，可避免错误覆盖其他应用或未来版本的数据。
- 影响：拒绝外来／未来库；启动失败不创建空库。
- 需真机验证项：外来库、未来库与启动失败提示。
- 相关代码／文档：[DeskNodesDatabase.cs](../src/DeskNodes.Core/Storage/DeskNodesDatabase.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D3 删除业务日

- 背景：时区和跨天设置可以改变。
- 方案列表（利弊）：封存时反推：可能错归；写入时固定 day：归属稳定。
- 推荐／采用：pending_deleted_*.day 写入时固定。
- 理由：删除发生时的业务日才是稳定事实，不能在设置或时区变化后依据时间戳重新推断。
- 影响：封存 day<=active_day；推进后清理 day<current，不补未观察日。
- 需真机验证项：改时区、回拨和睡眠跨天。
- 相关代码／文档：[DayRolloverService.cs](../src/DeskNodes.Core/Services/DayRolloverService.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D4 整张删除成员

- 背景：同毫秒可能发生独立删除。
- 方案列表（利弊）：按 deleted_at 匹配：误恢复；显式成员：多一张关系表但准确。
- 推荐／采用：note_deletion_items 显式记录。
- 理由：时间戳不保证删除操作的唯一性，显式成员关系才能准确恢复一次整张删除。
- 影响：恢复整张便签只恢复其删除成员。
- 需真机验证项：同毫秒独立删除与整张恢复。
- 相关代码／文档：[RecentlyDeleted.cs](../src/DeskNodes.Core/Services/RecentlyDeleted.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D5 空白事项清理

- 背景：失焦后的空白事项无需历史。
- 方案列表（利弊）：软删除：污染最近删除；物理删除：无恢复记录。
- 推荐／采用：物理删除空白事项。
- 理由：空白行属于编辑清理，保留软删除记录会制造用户未实际删除的历史内容。
- 影响：不进入最近删除或快照删除成员。
- 需真机验证项：输入法候选失焦与空白清理。
- 相关代码／文档：[NoteActions.cs](../src/DeskNodes.Core/Services/NoteActions.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D6 混合 DPI 坐标

- 背景：各屏缩放不同。
- 方案列表（利弊）：全屏 DIP：接缝错位；全部像素：Core 复杂；混合约定：职责清楚。
- 推荐／采用：单屏屏 DIP=像素/该屏缩放，跨屏 PixelBounds。
- 理由：单屏布局保留 DIP 可读性，跨屏拓扑使用像素才能比较不同缩放屏幕的真实边界。
- 影响：接缝、指针屏、框选求交用物理像素。
- 需真机验证项：100/125/150/200% 与负坐标屏。
- 相关代码／文档：[Screens.cs](../src/DeskNodes.Core/Presentation/Screens.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D7 便签右键菜单

- 背景：需保留原生编辑功能。
- 方案列表（利弊）：整窗菜单：丢失编辑菜单；分区菜单：便签入口不够近；分区加子菜单：两者可达。
- 推荐／采用：编辑框原生菜单附便签子菜单，其他区域便签菜单。
- 理由：保留文本剪切、复制与撤销入口，同时让编辑区仍能访问便签操作。
- 影响：Shift+F10／菜单键跟随焦点。
- 需真机验证项：鼠标与键盘上下文菜单。
- 相关代码／文档：[NoteWindow.Menus.cs](../src/DeskNodes.App/Views/NoteWindow.Menus.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D8 视图结构

- 背景：需要原生品质和可维护样式。
- 方案列表（利弊）：第三方 MVVM：额外依赖；XAML+轻量 ViewModel：足够且简单。
- 推荐／采用：XAML、资源样式、轻量 ViewModel。
- 理由：现有视图规模可用轻量绑定表达状态，资源集中维护视觉，无需引入额外框架生命周期。
- 影响：Segoe Fluent Icons；Segoe UI 计数使用 Tabular。
- 需真机验证项：图标字体与等宽计数。
- 相关代码／文档：[Controls.xaml](../src/DeskNodes.App/Themes/Controls.xaml)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D9 整理降级

- 背景：屏幕可能没有可避让工具条的空间。
- 方案列表（利弊）：抛异常：阻断整理；降级放置：可能被覆盖。
- 推荐／采用：允许覆盖工具条的降级放置。
- 理由：空间不足时仍应完成可恢复的布局操作，允许遮挡比阻断整理更可用。
- 影响：极小工作区仍能完成整理。
- 需真机验证项：小工作区整理。
- 相关代码／文档：[NoteLayout.cs](../src/DeskNodes.Core/Presentation/NoteLayout.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D10 本机偏好

- 背景：本机布局与业务数据分离。
- 方案列表（利弊）：整文件强反序列化：单字段损坏影响全部；逐键解析：字段级容错。
- 推荐／采用：LocalPreferences.json 逐键显式解析。
- 理由：一个坏字段不应丢失其他有效偏好；保留损坏原文件便于诊断，空锚点可按当前屏幕解析。
- 影响：字段回退；损坏文件改名保留；I/O 失败默认；空 anchor 用 ResolveAnchor。
- 需真机验证项：权限拒绝、损坏偏好、首次启动。
- 相关代码／文档：[LocalPreferences.cs](../src/DeskNodes.Core/Presentation/LocalPreferences.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D11 工具条非激活

- 背景：点击工具条不应打断编辑。
- 方案列表（利弊）：普通窗口：抢焦点；NOACTIVATE：键盘依赖其他入口；临时激活：复杂。
- 推荐／采用：WS_EX_NOACTIVATE + SWP_NOACTIVATE。
- 理由：工具条是指针操作入口，保持编辑焦点可避免点击引发失焦提交；键盘操作走已有等价入口。
- 影响：托盘与全局热键提供键盘等价入口；完整范围见 [D39](#d39-托盘作为非激活工具条的键盘等价入口)。
- 需真机验证项：工具条点击期间编辑焦点。
- 相关代码／文档：[ToolbarWindow.xaml.cs](../src/DeskNodes.App/Views/ToolbarWindow.xaml.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D12 工具条材质

- 背景：需系统材质与形变。
- 方案列表（利弊）：纯色：稳但失去质感；分层透明：失去 DWM 材质／阴影且性能差；公开 backdrop：需回退。
- 推荐／采用：动态边界并集、公开 DWMWA_SYSTEMBACKDROP_TYPE 与圆角区域。
- 理由：公开 DWM 材质保留系统渲染路径，动态区域适配形变；不可用时以纯色保证可读性。
- 影响：build>=22621 浅 Mica／深 Acrylic；高对比、透明关闭、远程或失败回退纯色。
- 需真机验证项：材质、边缘、阴影、形变及所有回退。
- 相关代码／文档：[ToolbarWindow.Motion.cs](../src/DeskNodes.App/Views/ToolbarWindow.Motion.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D13 拖动 Esc

- 背景：非激活工具条收不到键盘消息。
- 方案列表（利弊）：临时激活：干扰焦点；不支持 Esc：交互缺失；拖动轮询：范围有限。
- 推荐／采用：仅拖动期间每 20ms GetAsyncKeyState 查询 Esc。
- 理由：限定拖动期的查询既能支持取消，也不会改变前台焦点或安装全局事件钩子。
- 影响：不安装全局键盘钩子。
- 需真机验证项：拖动 Esc 与捕获丢失。
- 相关代码／文档：[ToolbarWindow.Input.cs](../src/DeskNodes.App/Views/ToolbarWindow.Input.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D14 外观检测

- 背景：需要统一系统外观来源。
- 方案列表（利弊）：各处检测：容易分歧；集中检测：统一可测试映射。
- 推荐／采用：ThemeService 集中检测。
- 理由：集中系统信号可以防止窗口判断不一致，纯映射规则可在 Core 独立验证。
- 影响：Core ThemeRules 验证映射。
- 需真机验证项：系统主题及高对比切换。
- 相关代码／文档：[ThemeService.cs](../src/DeskNodes.App/Themes/ThemeService.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D15 单实例

- 背景：同库只能有一个写入实例。
- 方案列表（利弊）：全局固定 Mutex：阻止隔离实例；按目录哈希：允许隔离。
- 推荐／采用：Local\ 命名 Mutex + CurrentUserOnly 命名管道。
- 理由：目录哈希将互斥范围与数据范围对齐，用户范围管道限制第二实例的唤起通道。
- 影响：第二实例仅请求显示工具条。
- 需真机验证项：第二次启动与隔离实例并存。
- 相关代码／文档：[SingleInstance.cs](../src/DeskNodes.App/Platform/SingleInstance.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D16 多选覆盖层 Z 序

- 背景：混合 DPI 与逐张层级需保留。
- 方案列表（利弊）：覆盖层 owner：破坏保存层级；单跨屏窗：DPI 错；每屏 topmost：需顺序管理。
- 推荐／采用：每屏覆盖层→所选便签临时 topmost→操作条。
- 理由：逐屏窗口可按各屏缩放绘制，临时 Z 序无需改变便签的持久化层级。
- 影响：黑色 10%；退出立即关闭覆盖层归还命中。
- 需真机验证项：跨屏框选、Z 序与退出命中。
- 相关代码／文档：[PresentationCoordinator.cs](../src/DeskNodes.App/PresentationCoordinator.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D17 可见性与虚拟桌面

- 背景：多种原因可同时隐藏窗口。
- 方案列表（利弊）：各流程直接显示：可能误复活；原因集合：统一计算；私有固定桌面接口：不采用。
- 推荐／采用：suppressed 原因集合 + 公开 IVirtualDesktopManager 查询。
- 理由：统一原因计算避免一个显示操作绕过其他隐藏条件；公开查询遵守平台边界。
- 影响：收起、分页、溢出、虚拟桌面统一；1 秒轮询，COM 失败视为当前桌面。
- 需真机验证项：任务视图、切桌面及 COM 失败。
- 相关代码／文档：[VirtualDesktop.cs](../src/DeskNodes.App/Platform/VirtualDesktop.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D18 第二实例失败提示

- 背景：管道唤起失败并非数据库损坏。
- 方案列表（利弊）：通用数据库错误：误导；专用提示：说明恢复入口。
- 推荐／采用：显示“已在运行，可从托盘打开”。
- 理由：唤起通信失败不能推出数据库故障，专用提示能给出正确的恢复入口。
- 影响：不误报数据库错误。
- 需真机验证项：第一实例忙碌或管道失败。
- 相关代码／文档：[App.xaml.cs](../src/DeskNodes.App/App.xaml.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D19 历史深色色表

- 背景：UI_SPEC 未提供深色色值。
- 方案列表（利弊）：系统色：失去纸感；声称 Mac 同款：无依据；语义深色：需检查对比度。
- 推荐／采用：自定语义深色色表，正文／次要／选中对比均 >7:1。
- 理由：没有上游深色色值证据，因此明确自定语义配色，并以对比度约束文字可读性。
- 影响：便签纸面固定浅色；视觉仍待验收。
- 需真机验证项：历史色阶、选中态与可读性。
- 相关代码／文档：[Dark.xaml](../src/DeskNodes.App/Themes/Dark.xaml)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D20 主题资源机制

- 背景：所有窗口必须同步外观。
- 方案列表（利弊）：每窗服务：重复不同步；键加 Light/Dark 后缀：易漏；应用单例：统一。
- 推荐／采用：应用级 ThemeService 切换 Light/Dark/HighContrast。
- 理由：单例服务与同名动态资源使所有窗口同时更新，减少手工分支和遗漏。
- 影响：DynamicResource 使用同名语义键。
- 需真机验证项：多窗口即时切换主题。
- 相关代码／文档：[ThemeService.cs](../src/DeskNodes.App/Themes/ThemeService.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D21 文楷获取

- 背景：字体约 50MB 且需可复现离线构建。
- 方案列表（利弊）：二进制入库：膨胀；构建自动联网：不可离线；显式脚本：可控。
- 推荐／采用：fetch-fonts.sh/.ps1 固定 v1.530 和三个 SHA-256。
- 理由：显式固定版本下载兼顾仓库体积、离线构建和来源校验，字体缺失状态可被用户理解。
- 影响：原始字体 gitignore；存在才打包；缺失显示未包含且禁止切换；不安装系统字体。
- 需真机验证项：打包／未打包文楷与 Medium 标题。
- 相关代码／文档：[fetch-fonts.ps1](../build/fetch-fonts.ps1)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D22 字体授权

- 背景：需可访问打包授权。
- 方案列表（利弊）：临时文件外部打开：生命周期与关联依赖；应用只读窗：稳定。
- 推荐／采用：包内授权用 LicenseWindow。
- 理由：应用内展示不依赖临时文件和系统文件关联，包内授权可离线阅读。
- 影响：包内缺失则固定版本在线页。
- 需真机验证项：离线授权与缺包在线入口。
- 相关代码／文档：[LicenseWindow.xaml.cs](../src/DeskNodes.App/Views/LicenseWindow.xaml.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D23 工具条 Ctrl+,

- 背景：非激活工具条依赖外部焦点。
- 方案列表（利弊）：钩子或强夺焦点：侵入；等价入口：保留焦点但需其他入口。
- 推荐／采用：便签 Ctrl+, 与托盘设置入口。
- 理由：不激活窗口不能保证收到快捷键；沿用便签与托盘入口可保留编辑焦点及公开 API 约束。
- 影响：不保证无焦点工具条接收 Ctrl+,。
- 需真机验证项：便签快捷键与托盘入口。
- 相关代码／文档：[NoteWindow.xaml.cs](../src/DeskNodes.App/Views/NoteWindow.xaml.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D24 跨天时间输入

- 背景：逐字符写入会产生中间无效状态。
- 方案列表（利弊）：逐键写库：频繁且无效；Enter／失焦提交：完整验证。
- 推荐／采用：Enter／失焦校验，无效提示并恢复保存值。
- 理由：完整时间才具有业务含义，提交边界校验可避免把输入过程中的半成品持久化。
- 影响：仅完整有效时间写库。
- 需真机验证项：无效时间、Enter 与失焦。
- 相关代码／文档：[SettingsWindow.xaml.cs](../src/DeskNodes.App/Views/SettingsWindow.xaml.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D25 辅助窗位置

- 背景：主屏工作区不代表指针所在屏。
- 方案列表（利弊）：SystemParameters.WorkArea：错屏；共享逐屏放置：符合 DPI。
- 推荐／采用：AuxiliaryWindowPlacement 指针屏居中并限制尺寸。
- 理由：指针屏幕比主屏更符合用户打开窗口的位置预期，共用放置规则可避免 DPI 逻辑分叉。
- 影响：历史和设置共用。
- 需真机验证项：跨屏打开历史与设置。
- 相关代码／文档：[AuxiliaryWindowPlacement.cs](../src/DeskNodes.App/Platform/AuxiliaryWindowPlacement.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D26 全局热键

- 背景：替换失败需保留旧绑定。
- 方案列表（利弊）：低级钩子：侵入及杀软误报；RegisterHotKey：公开且可检测冲突。
- 推荐／采用：隐藏顶层服务窗 RegisterHotKey + MOD_NOREPEAT，候选先注册。
- 理由：公开注册接口可发现冲突；先注册候选再释放旧绑定，才能在失败时保留可用入口。
- 影响：导入新建热键冲突整体回滚保旧库；浮起冲突提示未生效。
- 需真机验证项：冲突、AltGr、导入回滚。
- 相关代码／文档：[HotkeyService.cs](../src/DeskNodes.App/Platform/HotkeyService.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D27 登录启动

- 背景：用户与系统禁用状态必须被尊重。
- 方案列表（利弊）：计划任务：权限多；启动快捷方式：需 ShellLink 无优势；HKCU Run：简单。
- 推荐／采用：仅写自有 HKCU Run 值，完整 exe 路径加引号。
- 理由：用户级 Run 值无需额外权限；不触碰系统禁用记录才能尊重任务管理器中的用户选择。
- 影响：不碰 StartupApproved；提示系统可能禁用；隔离实例与 dotnet 宿主禁止写入。
- 需真机验证项：任务管理器禁用后不重建、重登录和卸载。
- 相关代码／文档：[LoginItemService.cs](../src/DeskNodes.App/Platform/LoginItemService.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D28 备份格式

- 背景：Mac 格式未冻结且导入需保旧库。
- 方案列表（利弊）：猜 Mac 格式：不可靠；独立 DTO：明确边界；直接覆盖文件：不安全。
- 推荐／采用：desknodes.windows.backup v1，严格拒绝未知字段。
- 理由：冻结独立协议可明确兼容边界，先验证 staging 再替换可避免无效输入破坏活库。
- 影响：staging 业务校验及 SQLite 检查后 online backup；导出同目录唯一临时文件 Replace/Move。
- 需真机验证项：往返、取消、磁盘满、无效文件与热键冲突。
- 相关代码／文档：[WindowsBackupCodec.cs](../src/DeskNodes.Core/Backup/WindowsBackupCodec.cs)、[数据库替换](../src/DeskNodes.Core/Storage/DeskNodesDatabase.cs)、[备份协议](BACKUP_FORMAT.md)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D29 导入会话

- 背景：旧回调与撤销不能作用于新库。
- 方案列表（利弊）：保留旧会话：可能误写；清空重建：明确失效。
- 推荐／采用：清空撤销、结束多选／浮起、编辑失效并重建窗口。
- 理由：导入改变了数据身份与状态，旧编辑回调和撤销内容必须失效；跨天留给正常业务检查。
- 影响：导入后不立即跨天。
- 需真机验证项：组词导入拒绝、旧回调及跨天状态。
- 相关代码／文档：[AppCoordinator.SystemServices.cs](../src/DeskNodes.App/AppCoordinator.SystemServices.cs)、[技术设计](TECHNICAL_DESIGN.md)、[验证门槛](FEASIBILITY.md#verification)。

## D30 导入后台解析与有界输入

- 背景：审查 A5+B1、B4/C13 指出无界导入与同步读取阻塞界面；数据库现为单连接加锁串行模型。
- 方案列表（利弊）：仅检查 FileInfo.Length：无法限制读取时变化及内部集合；有界读取并后台解析／staging：限制资源且隔离活库；完整后台存储队列：增加线程亲和、退出时序及替库同步风险。
- 推荐／采用：字节、集合、字符串长度与显式 MaxDepth 上限；读取、解析、staging 后台执行，替换活库仍在 UI 线程串行；历史采用月份统计缓存与 generation 丢弃过期结果。
- 理由：在可验证边界内降低导入阻塞；拒绝本轮建立完整后台存储队列，其收益尚无 Windows 实测支撑，风险不匹配。
- 影响：封存、自动备份保持同步；完整队列延后至真机测量卡顿后决定。
- 需真机验证项：大文件导入期间 UI 响应、取消／失败保留活库、快速历史导航及退出时序。
- 相关代码／文档：[导入协调](../src/DeskNodes.App/AppCoordinator.SystemServices.cs)、[备份校验](../src/DeskNodes.Core/Backup/WindowsBackupCodec.cs)、[历史模型](../src/DeskNodes.App/Views/HistoryViewModel.cs)、[构建验证](WINDOWS_BUILD.md)。

## D31 停靠序号限定 int 范围

- 背景：审查 A2 发现协议可接受的 long 序号可能在领域 GetInt32 读取时溢出。
- 方案列表（利弊）：领域全部扩为 long：波及布局和视图而无实际收益；导入重编号：改变输入数据；收紧协议范围：兼容领域且拒绝不可读取数据。
- 推荐／采用：dock_order 限定 0..int.MaxValue，staging 必须能被领域读取层完整读出。
- 理由：序号仅表示单条停靠边内顺序，协议 v1 尚未发布，无需扩宽领域。
- 影响：当前与快照都拒绝越界序号；同步备份协议约束。
- 需真机验证项：合法边界导入往返与失败不替库。
- 相关代码／文档：[备份校验](../src/DeskNodes.Core/Backup/WindowsBackupCodec.cs)、[领域读取](../src/DeskNodes.Core/Storage/NoteRepository.cs)、[备份协议](BACKUP_FORMAT.md)。

## D32 系统文本缩放与 Windows SDK 目标

- 背景：审查 C9 要求 Windows 辅助文本大小独立于显示 DPI；平台最低基线是 Windows 11 22H2（22621）。
- 方案列表（利弊）：仅应用内比例：不跟随系统；仅系统消息字体：不能覆盖自定义字号；(a) 原始 WinRT ABI（RoGetActivationFactory + 手写 IUISettings2 vtable）：无体积成本，但手写 IInspectable 布局、订阅事件需自实现委托 COM 对象，维护与正确性风险高；(b) 注册表 HKCU\Software\Microsoft\Accessibility\TextScaleFactor + 设置变更消息：最简单，但读取的是未文档化的存储位置；公开 UISettings 官方投影：可读比例并订阅变化，需要 Windows SDK 目标与 WinRT 投影。
- 推荐／采用：Platform/TextScaleService 使用 UISettings.TextScaleFactor／TextScaleFactorChanged，失败回退 1.0，事件切回 Dispatcher；便签使用独立排版参数，设置／历史使用应用级动态字号资源。
- 理由：直接跟随系统辅助设置，保留编辑器与输入缓冲，通过排版更新重新量高。初拟 net10.0-windows10.0.19041.0 与 SupportedOSPlatformVersion=10.0.22621.0 被 SDK 以 NETSDK1135 拒绝；采用 net10.0-windows10.0.22621.0 和同版本支持下限。另一方案是把支持下限降至 19041，但违反文档平台裁决，故不采用。
- 采用理由与代价：选择官方投影以换取正确性与可维护性，体积代价可接受；若后续体积成为问题再评估 (a)。发布证据统一见[当前验证证据](WINDOWS_BUILD.md#当前验证证据)；App TFM 改为 net10.0-windows10.0.22621.0；Core 仍 net10.0。
- 需真机验证项：系统文本 100/150/200% 与多屏 DPI 交叉、编辑／组词缓冲、固定／自动高与辅助窗口无裁字、实时切换与退出解绑。
- 相关代码／文档：[文本缩放服务](../src/DeskNodes.App/Platform/TextScaleService.cs)、[排版](../src/DeskNodes.Core/Presentation/NoteTypography.cs)、[App 项目](../src/DeskNodes.App/DeskNodes.App.csproj)、[构建验证](WINDOWS_BUILD.md)、[公开文本缩放 API](https://learn.microsoft.com/en-us/uwp/api/windows.ui.viewmanagement.uisettings.textscalefactorchanged)。

## D33 展示计时使用单调 TimeProvider

- 背景：审查 C14 指出 UTC 回拨会使动画及闲置等待停滞，单纯限制时间不递减仍需等待 UTC 追平。
- 方案列表（利弊）：时间变化时重建基准：依赖消息完备；累计非负 UTC 差值：无法完整表达调整与挂起；可注入单调计时：独立于业务日期且可测试。
- 推荐／采用：展示持续时间使用 TimeProvider.GetTimestamp 的单调来源，业务日期继续使用 IClock。
- 理由：系统时间前进／回拨不改变动画和闲置持续时间语义。
- 影响：展示与业务时间分离，保留可注入测试来源。
- 需真机验证项：动画／闲置中回拨一小时、前跳及挂起恢复，检查最终状态和计时器停止。
- 相关代码／文档：[工具条](../src/DeskNodes.App/Views/ToolbarWindow.xaml.cs)、[工具条动画](../src/DeskNodes.App/Views/ToolbarWindow.Motion.cs)、[构建验证](WINDOWS_BUILD.md)。

## D34 暂保留 GetDpiForMonitor

- 背景：审查 B7 指出 PerMonitorV2 线程不建议调用 GetDpiForMonitor，但尚无可复现错误，同文档说明 per-monitor aware 进程返回实际有效 DPI。
- 方案列表（利弊）：探测窗口配合 GetDpiForWindow：增加窗口与生命周期复杂度；直接推断 DPI：可能偏离实际；保留并真机对照：改动最小但需实测。
- 推荐／采用：暂保留现有 GetDpiForMonitor，加入 GetDpiForWindow 真机对照；发现偏差后再采用探测窗口方案。
- 理由：Linux 无法验证新增探测窗口行为，不以文档建议替代已复现错误证据。
- 影响：本轮不改屏幕 DPI 获取；跨屏判断继续使用 PixelBounds，屏 DIP 仍为像素除以该屏缩放。
- 需真机验证项：各屏 GetDpiForMonitor 与 GetDpiForWindow 对照，含跨屏、远程会话与显示设置变化。
- 相关代码／文档：[屏幕服务](../src/DeskNodes.App/Platform/ScreenProvider.cs)、[构建验证](WINDOWS_BUILD.md)、[平台可行性](FEASIBILITY.md)。

## D35 偏好与布局的提交边界

- 背景：整理同时改数据库布局和本机分页偏好；先提交布局再保存偏好，会在偏好写入失败后留下错配状态。
- 方案列表（利弊）：将分页搬入 SQLite：可共用事务，但违反 D10 与备份协议的本机偏好边界；数据库提交后逐项恢复布局：补偿范围大且容易遗漏；事务委托内先保存偏好、数据库失败时补偿偏好：维持现有边界，但两种存储不具备跨进程崩溃原子性。
- 推荐／采用：CombinedCommitCoordinator 在外层数据库事务内写布局，COMMIT 前保存偏好；偏好保存失败抛出使数据库回滚，保存成功后注册外层回滚回调恢复旧偏好。PreferencesState 仅在文件持久化成功后发布新值。新建／整张恢复需要展开桌面时，展开偏好保存失败即中止，不继续写业务库。
- 理由：分页属于本机展示状态，不应进入业务库与导出备份；保留文件边界并在统一事务入口补偿，避免布局已提交而分页仍旧。
- 影响：整理失败保留旧布局与页码；回滚补偿失败通过异常及日志暴露，不承诺文件与 SQLite 在断电／强杀时跨介质原子提交。没有采用把本机偏好移入 SQLite 的方案。持久化与发布的分离见 [D38](#d38-偏好持久化与发布分离)。
- 需真机验证项：偏好权限拒绝／磁盘满、COMMIT 失败及补偿失败，检查提示、菜单勾选、布局与位置；解除故障后可重试。
- 相关代码／文档：[组合提交](../src/DeskNodes.Core/Presentation/CombinedCommitCoordinator.cs)、[偏好发布](../src/DeskNodes.Core/Presentation/PreferencesState.cs)、[应用协调器](../src/DeskNodes.App/AppCoordinator.cs)、[D10](#d10-本机偏好)、[备份格式](BACKUP_FORMAT.md)、[手工清单](WINDOWS_BUILD.md#三组修复回归步骤全部待执行)。

## D36 编辑缓冲的外层事务确认协议

- 背景：跨天事务内提交编辑会嵌套保存；savepoint 成功不能代表外层封存已提交，提前确认缓冲会在外层失败后丢失重试依据。
- 方案列表（利弊）：各个业务调用处补偿编辑状态：容易遗漏新路径与嵌套失败；先独立保存编辑再封存：违反单事务封存要求；统一外层提交／回滚确认回调：集中处理事务结果，需要维护回调生命周期。
- 推荐／采用：DeskNodesDatabase 提供 OnOuterCommitted／OnOuterRolledBack。PendingCommitTracker 在嵌套保存后注册结果回调，EditorCoordinator 仅在外层提交成功且 owner 有效、修订仍匹配时更新 Committed 文本；回滚保留旧确认文本和当前编辑缓冲，标记失败并在非组词时重新安排 debounce 保存。
- 理由：只有最外层 COMMIT 才能确认持久化，统一协议覆盖跨天和其他组合事务；逐处补偿易漏，独立落库会拆散封存的一致性边界。
- 影响：回调在事务完成、离开数据库锁后执行；嵌套 savepoint 失败时移除其成功回调，将其回滚回调保留至外层完成，即使上层捕获异常也不误确认写入。owner／修订检查避免旧回调覆盖新编辑；回调失败汇总抛出。
- 需真机验证项：编辑中跨天封存写锁／磁盘故障后文字、选区与组词缓冲保留；解除故障后重试，重启读取和历史内容一致。
- 相关代码／文档：[数据库事务](../src/DeskNodes.Core/Storage/DeskNodesDatabase.cs)、[确认协议](../src/DeskNodes.Core/Services/PendingCommitTracker.cs)、[编辑协调器](../src/DeskNodes.App/Editing/EditorCoordinator.cs)、[跨天服务](../src/DeskNodes.Core/Services/DayRolloverService.cs)、[手工清单](WINDOWS_BUILD.md#三组修复回归步骤全部待执行)。

## D37 外部输入限制与内部往返分离

- 背景：外部 JSON 有界解析曾被内部导出／staging 复核复用，中文序列化转义放大字节数后会误拒合法业务数据。
- 方案列表（利弊）：仅换 encoder：可减少部分转义，仍无法保证内部数据不触及外部大小限制；另定规范化限制：新增一套规则且仍可能拒绝合法内部往返；分离外部入口和内部 DTO／业务校验：保留输入防护，不将用户文件资源预算施加到内部数据。
- 推荐／采用：Parse(string／Stream) 仅处理外部输入，按实际 UTF-8 字节、解码后的字符串长度、数组条数和嵌套深度限流，支持取消；Export 使用 DTO 转换及头部／业务状态校验，Stage 写入临时库后执行 SQL 完整性、领域完整读取及 Export 复核，不再调用有界 Parse。
- 理由：外部资源限制防止不受信任文件耗尽资源，内部往返保证合法业务状态可复核，两者职责不同；encoder 和另定规范化限制都不能建立这个边界。
- 影响：内部转换仍保留协议、引用和领域一致性验证；不保证任意大的内部导出文件都能作为外部文件重新导入，外部上限仍以备份协议为准，不扩大用户文件限额。
- 需真机验证项：大量中文导出／staging 复核与合法导入，四类外部上限的恰好值／超限分类提示，取消和失败后活库不变、临时库清理。
- 相关代码／文档：[外部有界解析](../src/DeskNodes.Core/Backup/WindowsBackupCodec.Parsing.cs)、[内部导出与 staging](../src/DeskNodes.Core/Backup/WindowsBackupCodec.cs)、[备份测试](../tests/DeskNodes.Core.Tests/BackupParsingTests.cs)、[备份格式](BACKUP_FORMAT.md)、[手工清单](WINDOWS_BUILD.md#三组修复回归步骤全部待执行)。


## D38 偏好持久化与发布分离

- 背景：组合提交中，偏好已落盘但发布通知抛出时，原流程尚未登记回滚恢复，可能留下偏好与数据库布局错配。
- 方案列表（利弊）：先登记补偿再保存：可覆盖通知异常，但保存前失败也会触发多余恢复写入，否决；回读文件判定：可检查落盘状态，但增加复杂度与 IO，否决；分离持久化与发布：持久化成功即登记恢复，发布延后到外层提交后，边界明确，但发布失败需要单独报告。
- 推荐／采用：CombinedCommitCoordinator 在偏好持久化成功后立即登记外层回滚恢复，再登记外层提交后的发布回调；PreferencesChanged、主题刷新、工具条重建与可见性刷新均在外层提交后执行。发布异常不回滚已提交数据，经既有错误提示路径报告。
- 理由：补偿应依据持久化结果登记，界面发布不能混入落盘成功的判定；无需提前补偿或回读文件即可覆盖通知异常。
- 影响：保留 [D35](#d35-偏好与布局的提交边界) 的文件与 SQLite 非崩溃原子取舍；数据库回滚时恢复旧偏好，提交后发布失败则保留已提交数据，界面可能需要重新刷新。
- 需真机验证项：分别注入偏好保存失败、外层 COMMIT 失败与提交后发布异常，核对偏好文件、布局、错误提示及日志；发布失败时已提交数据保持，重启后读取一致。
- 相关代码／文档：[组合提交](../src/DeskNodes.Core/Presentation/CombinedCommitCoordinator.cs)、[应用协调器](../src/DeskNodes.App/AppCoordinator.cs)、[事务确认测试](../tests/DeskNodes.Core.Tests/TransactionConfirmationTests.cs)、[D35](#d35-偏好与布局的提交边界)、[第三轮回归清单](WINDOWS_BUILD.md#4-第三轮审查回归全部待执行)。

## D39 托盘作为非激活工具条的键盘等价入口

- 背景：[D11](#d11-工具条非激活) 保持工具条非激活，键盘操作依赖等价入口；原托盘缺少整理、收起／展开与翻页。
- 方案列表（利弊）：托盘补齐：复用通知区域键盘入口与既有动作，菜单变长；便签内快捷键：操作直接，但无便签时不可达；命令面板：可集中检索命令，但增加界面与焦点管理成本。
- 推荐／采用：托盘补齐整理、收起／展开、上一页／下一页，共用工具条动作与可用条件。
- 理由：保持非激活工具条模型，以已有系统入口补齐键盘可达性，避免新增交互层与重复业务规则。
- 影响：托盘菜单比 FR-01 的“工具条菜单同类项 + 显示工具条／新建／浮起”多出整理、收起／展开、上一页／下一页，属于 Windows 可达性补充。
- 需真机验证项：通过通知区域键盘导航与 Narrator，全程不用指针完成整理、收起／展开和翻页，核对菜单名称、状态与结果。
- 相关代码／文档：[托盘菜单](../src/DeskNodes.App/Views/AppMenus.cs)、[工具条视图模型](../src/DeskNodes.App/Views/ToolbarViewModel.cs)、[工具条可用规则](../src/DeskNodes.Core/Presentation/ToolbarRules.cs)、[应用协调器](../src/DeskNodes.App/AppCoordinator.cs)、[第四轮回归清单](WINDOWS_BUILD.md#5-第四轮整体审查回归全部待执行)。
