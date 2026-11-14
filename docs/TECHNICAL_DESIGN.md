# DeskNodes Windows 技术设计

这是待实施架构，未创建工程或应用代码。行为见 [需求](REQUIREMENTS.md)，数值见 [UI](UI_SPEC.md)，平台裁决及技术栈完整比较见 [可行性](FEASIBILITY.md)。

<a id="architecture"></a>
## 技术栈与职责

推荐 **C# + WPF（实施时锁定受支持的稳定 .NET LTS）+ SQLite + 少量公开 Win32 互操作**，Windows 11 22H2 起。优先保留系统文字服务、焦点、选区、撤销，再以 XAML 模板形成精致卡片和工具条。WPF 的向量布局与模板支持此方向；这属于设计判断，不是性能或 IME 实测排名。[WPF 官方概览](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/overview/)

不必为此引入 Windows App SDK 运行时；将来若采用其能力，应单独评估部署与版本。按职责分层，以下是建议模块名而非已有类型：

| 模块 | 职责与所有权 |
|---|---|
| AppCoordinator | 组合根、单实例协调、启动退出、系统事件、导入代际切换 |
| Domain | UUID 类型、业务日、统计、布局算法、规则；不引用 HWND |
| Store | SQLite 连接、迁移、事务、快照、备份、完整性校验 |
| NoteActions | 新建、删除、批次撤销、恢复和结构操作提交屏障 |
| EditorCoordinator | 每标题／事项的编辑所有者、组词、选区、修订号与提交 |
| NoteSurfaces | NoteID→WPF Window／HWND，差量更新，禁止刷新复活隐藏窗口 |
| PresentationCoordinator | 收起、浮起、多选、分页和 generation；不编辑业务内容 |
| Dock／ToolbarLayout | 工作区、停靠、溢出、吸边、完整目标避让 |
| WindowsServices | 托盘、热键、登录启动、DPI、电源／时钟／主题及虚拟桌面查询 |

UI 和 HWND 在同一 STA Dispatcher 上操作。持久化由一个串行仓库队列管理；事务内部不 await、不跨线程。UI 在进入事务前提供已提交文本的不可变快照，不从存储线程触碰编辑器。单实例拟用命名 Mutex 和当前用户范围的命名管道；第二次启动只请求显示工具条，不能抢占第一实例的热键或开第二套写库。隔离验证实例必须用独立库／偏好，且明确禁止修改个人登录项。

<a id="models"></a>
## 数据模型与边界

保留 Mac 产品模型语义：NoteID／ItemID 包装 UUID，删除不循环身份；Note 包含标题、颜色、顺序、placement、savedLevel、freeRestore、automaticHeight、collapsed、时间与 tombstone；Item 包含 noteID、文本、completed、struck、顺序、archivedDay、时间与 tombstone，数据库 CHECK 禁止完成和划掉同时为真。

DailySnapshot／SnapshotNote／SnapshotItem 保存冻结成员，包括删除、划掉、carriedTo；HistoryDay 严格公历 YYYY-MM-DD，检查点保存 activeDay 与 highWater。删除待记录集合、归档映射和冻结成员分开，恢复实时 tombstone 不改历史。

Windows placement 使用显示器相对 DIP 矩形与可识别的显示设备线索、停靠边及序号、自由还原位置。Windows 屏幕坐标左上原点、Y 向下，虚拟屏幕可有负坐标，不能复制 Mac 左下原点值。显示器句柄不跨重启存储；标识失配时按已连接屏幕、工作区和最近位置回退主屏。业务库不保存 HWND、瞬时 DPI 或动画坐标。

业务偏好保留跨天时间、快捷键和登录意愿；本机偏好另存全局收起目标、工具条锚点／方向／闲置、字号、新建尺寸、整理页。自由锚点用中心、吸边用边及归一化比例。选择、焦点、浮起、多选、过渡、撤销和保存任务不序列化。Windows 无已有发布 schema，不冒称继承 Mac v8 迁移；以后明确 Windows schema 和 application_id 后才冻结格式。

<a id="storage"></a>
## 存储、事务与恢复

拟存 `%LOCALAPPDATA%\DeskNodes\DeskNodes.sqlite3`，通过 LocalApplicationData 已知目录解析，不硬编码用户名；用户目录 ACL 隔离，不声称等价 Unix 0700 或加密。非空 `DESKNODES_DATA_DIR` 可重定向数据目录，偏好也应以隔离配置名分开；此开关不应自动注册启动项。

SQLite 使用外键、WAL、synchronous=FULL、5 秒 busy timeout；外层 BEGIN IMMEDIATE，嵌套 savepoint，失败回滚。迁移先核对身份和版本、拒绝未来／无关库，独占事务执行。冻结记录用约束／触发器阻止 UPDATE／DELETE 及封存后补插；先成员后 header，延迟外键提交。不能清空数据来修复布局。以上为拟定协议，不是现有库声明。

导入 staging、业务库和自动副本必须在同一串行调度下协调。SQLite 活库不能只复制主文件，WAL／SHM 不能混用。自动副本拟用 VACUUM INTO 写数据库目录 Backups 中唯一 `.partial-UUID.sqlite3`，成功关闭输出后重命名为 `DeskNodes-YYYY-MM-DD.sqlite3`，同日不覆盖，按有效文件名保留最新 7 份；失败仅日志，残余 partial 不计有效副本。[SQLite VACUUM INTO](https://www.sqlite.org/lang_vacuum.html)

离线恢复必须退出进程、保留当前整个目录、把完整副本放进新目录作为主库，不带旧侧文件，再检查完整性、启动和历史。正常恢复通过不能推出断电恢复可靠。

<a id="editing"></a>
## 编辑与 IME

每标题和事项保留独立 TextBox 编辑状态；多行文字通过 TextBox 的输入、选择和 Undo 路径，不自绘光标、不从 KeyDown 拼汉字。WPF TextCompositionManager 的开始／更新／完成事件与输入事件路由用于追踪组合状态；不能把一次 TextChanged 或 KeyUp 当作可靠组词完成。IME 键可能为 Key.ImeProcessed，Return／Esc 应先交给输入法。WPF 与 TSF 是可用基础，并不保证任意 IME 自动正确。[WPF 输入](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/input-overview)、[TSF](https://learn.microsoft.com/en-us/windows/win32/tsf/text-services-framework)

每编辑器记录 owner ID、修订号、composition 状态、最后已提交文本；0.4 秒 debounce 仅提交有效修订。外部刷新不回写活跃 TextBox.Text，不在每次按键重建控件树；完成／划掉样式用展示属性，不改正文来加删除线。提交屏障由当前所有者读取有效内容，组词时拒绝结构操作、导入、退出，跨天进入 deferred 后重试。失焦若由 IME 候选窗引起，不能误判为结构提交／应用离开，需 Windows 真机验证。

标题／事项的文字撤销与结构删除栈分离；Ctrl+Z 分派遵循 FR-04。导入成功使旧 owner、debounce、事件回调和 Undo 全部失效；即使 ID 相同也不得继续旧会话。多行粘贴处理剪贴板文本一次并组织为可理解的撤销单元，不能吞掉输入法或普通单行粘贴。

<a id="windows"></a>
## 多窗口、系统铬与 Z 序

一张便签对应一个 WPF Window／HWND，工具条独立窗口，设置／历史按需复用。便签使用自定义内容与非客户区命中，优先评估 WindowChrome 保留系统调整大小与阴影；[WindowChrome 公开接口](https://learn.microsoft.com/en-us/dotnet/api/system.windows.shell.windowchrome) 可用于非客户区定制；不默认使用整窗 AllowsTransparency=true，因为它改变合成路径和系统圆角／阴影条件。先在 Windows 做圆角、边界、IME 和 DPI 小样，再定最终壳层；不能为阴影牺牲编辑器。

便签／工具条 `ShowInTaskbar=false`，必要时 WS_EX_TOOLWINDOW；不要把所有便签设为工具条的 owned window，以免所有权强制 Z 序影响逐便签层级。工具条非激活显示使用 SWP_NOACTIVATE，鼠标激活策略需区分按钮、菜单、键盘辅助入口；可评估 WS_EX_NOACTIVATE，但不能给可编辑便签永久加此样式，否则正常键盘输入与辅助技术会受影响。样式与任务栏行为以公开定义为界。[扩展窗口样式](https://learn.microsoft.com/en-us/windows/win32/winmsg/extended-window-styles)

层级解析：临时浮起／多选优先于 savedLevel，结束恢复。普通取消 topmost，置顶请求 HWND_TOPMOST，靠后仅在失活／放回等边界请求 HWND_BOTTOM。HWND_BOTTOM 不是桌面图标层，可能被桌面或 Show Desktop 隐藏，不持续轮询其他应用来争 Z 序。不使用 WorkerW／Progman 宿主。[SetWindowPos](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos)

用户动作可尝试 SetForegroundWindow 并检查结果，不能用 AttachThreadInput、模拟输入或反复置顶绕过系统前台锁。失活用 WM_ACTIVATEAPP／前台窗口进程核对，自家设置、菜单、对话框与 IME 候选窗需排除；不安装低级全局钩子。[前台限制](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow)

多选覆盖层只在模式内存在，每屏一层，接收空白拖动；便签与操作条安排在其上。避免透明整屏窗口意外穿透或拦截系统；退出立即撤掉命中区。屏幕物理坐标求交，再分屏转换绘制。虚拟桌面用 IVirtualDesktopManager 查询自有窗口所属／当前状态，不调用私有 COM 置顶到全部桌面。[虚拟桌面接口](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-ivirtualdesktopmanager)

<a id="presentation"></a>
## 状态机、几何与 DPI

便签展示 expanded／collapsing／collapsed／expanding，工具条 expanded／collapsing／round／expanding，另有 peeking 和可空 picked 集合；普通 selection 与键盘 focus 独立。以 generation 丢弃过期动画回调，suppressed 原因集合含收起、页隐藏、停靠溢出、虚拟桌面不在当前；刷新不可自行 Show 所有窗口。动画只改临时展示，完成后写一次布局，不能逐帧写库。

清单、停靠、瀑布流及新建均按完整工具条目标避让。工作区用 MonitorFromPoint／MonitorFromWindow 与 GetMonitorInfo 的 rcWork，屏幕拓扑用 EnumDisplayMonitors；任务栏自动隐藏时保留 UI 安全边距，不把工作区等同物理屏幕框。吸边只选择屏幕外边，排除相接内边。

manifest 声明 PerMonitorV2，WPF 内容为 96 DIP／英寸，Win32 边界为像素，所有跨界明确转换。GetDpiForWindow 获取窗口 DPI，WM_DPICHANGED 建议矩形用于换屏调整并重算布局；WPF 自身 DPI 处理与手工调整要防止重复缩放。显示改变、工作区变化、远程会话和重新连接触发布局校正。[DPI 声明](https://learn.microsoft.com/en-us/windows/win32/hidpi/setting-the-default-dpi-awareness-for-a-process)、[WM_DPICHANGED](https://learn.microsoft.com/en-us/windows/win32/hidpi/wm-dpichanged)

<a id="services"></a>
## 托盘、热键、启动与系统事件

托盘可用 System.Windows.Forms.NotifyIcon（WPF 进程内只复用通知区域组件）或 Shell_NotifyIcon；推荐前者降低工作量，保留消息恢复适配层。Explorer 重启后核对图标重建，不保证系统让其固定可见。应用显式退出才 Dispose 图标，关闭辅助窗口不结束 Dispatcher。[NotifyIcon](https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.notifyicon)

热键用隐藏的非 message-only 顶层服务 HWND 接 WM_HOTKEY，以 RegisterHotKey／UnregisterHotKey 管理两个独立 ID，使用 MOD_NOREPEAT。替换先试注册候选、成功才释放旧绑定；重复组合先验证。导入阶段协调两个绑定，失败恢复旧配置，不把注册失败当成功。Windows VK 不等价 Mac ANSI 物理键，布局／AltGr 需验证。[RegisterHotKey](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey)

推荐非打包个人安装：明确同意后写 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 自有值，使用稳定 exe 路径和正确引号，取消仅删自有值；不修改 StartupApproved 私有状态。Run 项没有 SMAppService 的四态查询合同。用户在任务管理器禁用后，不静默重建来绕过。若改 MSIX，用清单 startupTask + Windows.ApplicationModel.StartupTask（底层 IStartupTask）及其状态，按该发行模型重做授权交互。[Run 项](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys)、[StartupTask](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.startuptask?view=winrt-26100)

服务顶层 HWND 接 WM_POWERBROADCAST（恢复时重计闲置并检查跨天）、WM_TIMECHANGE、WM_SETTINGCHANGE、WM_DISPLAYCHANGE；非 message-only 是为了接广播。计时器不是秒级承诺，恢复／重启时补检查。时区变化还比较当前时区标识和规则，不能只依赖一个消息。夏令时采用 TimeZoneInfo 明确处理无效／重复时刻；高水位阻回拨。挂起时尝试提交有效文本，强制关机不承诺能取消。[电源广播](https://learn.microsoft.com/en-us/windows/win32/power/wm-powerbroadcast)

减少动画读 SystemParametersInfo(SPI_GETCLIENTAREAANIMATION)，监听设置变化并允许用户强制减少；高对比用 SystemParameters.HighContrast 等公开系统状态。屏幕阅读器相关 SPI_GETSCREENREADER 不能穷举所有辅助工具，提供“保持工具条展开”显式设置，不声称可靠探测所有 Narrator／第三方读屏器。[系统参数](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow)

<a id="backup"></a>
## JSON 协议与导入原子性

Mac 源文档的协议为 `local.desknodes.native.backup`、version 1、schema 7／8；Date 默认基于 2001-01-01，StableID 为 rawValue 对象，Placement 为 Swift enum 合成 Codable。**这些信息不足以在本轮定义兼容解码器**；不能假设 Unix JSON 日期、扁平 ID 或相同坐标。Windows 不直接打开 Mac 库，不将本机热键字符当等价绑定。

推荐 Windows 独立带 format／version／schema 的显式 DTO；在实现前以正式协议文档冻结字段、时间单位／时区、ID 形状、可选缺省值、枚举和限制，并生成往返黄金样本。当前不编造可导入 JSON 示例或宣称兼容版本。业务载荷须覆盖所有保留 notes／items、history、pendingNotes／pendingItems、跨天 settings、业务 preferences 和可选 checkpoint；排除本机偏好与实际系统启动注册。跨 Mac 导入只能作为以后显式转换器：取得真实导出样本、逐字段测试、转换布局和热键、用户确认平台差异后再发布。

导入校验 UUID 唯一、引用、顺序、时间、归档／顺延一致性、互斥状态和格式版本；staging 库跑 foreign_key_check／integrity_check，并通过正式导出路径复核。不得执行文件附带 SQL。安全提交→用户确认→热键候选预检后，在所有仓库读写暂停且外层无事务时，用 SQLite online backup API 把 staging 复制到目标连接；失败在 backup_finish 后回滚目标事务，保留旧编辑上下文和绑定；成功才切 generation 和刷新窗口。原子性与磁盘满行为须故障注入验证，不能把多文件复制称为原子替库。[SQLite backup API](https://www.sqlite.org/backup.html)

导出先读一致快照，保存对话框后在目标目录写唯一临时文件、flush／关闭，再以适合目标存在与否的替换／移动操作发布。ReplaceFileW 适用于替换已存在文件，不是任何文件系统都保证断电持久化；跨卷／网络目录失败保留原文件并提示，不降级为截断原件。[ReplaceFileW](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-replacefilew)

## 实施门槛

先做 Windows 小样证明中文输入、多便签焦点和圆角壳层，再进入业务实现；门槛与未验证项见 [验证提纲](FEASIBILITY.md#verification)。没有 SDK／运行时测试证据前，不能把这些建议模块写成已有 API 或已通过能力。
