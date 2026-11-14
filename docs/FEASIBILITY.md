# DeskNodes Windows 可行性、选型与验证

核对日期 2026-11-13。产品依据为 [入口记录的 feat-mac 文档提交](README.md)，不是更早的 cursor／macos-native-desknodes 文档。本文件基于公开文档和设计分析；环境为 Linux，无 Windows SDK、桌面运行时或真机测试。**所有 Windows 系统交互结果均需 Windows 真机验证**，“可行”表示有合理公开实现路径，不表示已实现／已验收。

## 最低版本与裁决定义

推荐最低 **Windows 11 22H2，build 22621**：统一 Windows 11 外观基线，并能用公开 DWM_SYSTEMBACKDROP_TYPE 请求 Mica／Desktop Acrylic，避免为视觉效果调用未公开属性。该枚举最低客户端为 build 22621。[Microsoft DWM 说明](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwm_systembackdrop_type)

这只是技术最低版本，不承诺该旧发行版仍处于安全维护期。实际部署应使用仍获系统与所选 .NET 支持的 Windows 11 版本，实施时核对支持矩阵。目标硬件先以 x64 验证，ARM64 是后续独立构建／验收范围。

Windows 10 21H2 上托盘、WPF、热键、Per-Monitor V2 等核心路径并非技术上不可用，但无上述公开 DWM backdrop 基线，需纯色材质回退、圆角／阴影适配及第二套系统验证。两个选择：①只做 Windows 11，视觉一致、验证成本小，覆盖面小；②增加 Win10 纯色兼容档，覆盖旧机，视觉与维护分叉。**推荐①**，不在本轮虚构 Win10 支持结果；即使选②也不以未公开 Acrylic 技巧补齐。

- **可行**：可以保留产品语义，以公开 API 和应用逻辑实现。
- **可行但有差异**：主要目标可做，但系统入口、输入、视觉或保证必须改变；表中链接到多个替代方案与推荐。
- **不可行**：在本项目限定的公开 API、普通用户桌面应用路径下无法提供原要求的严格保证；不表示任意私有系统组件都做不到。

<a id="matrix"></a>
## FR-01 至 FR-15 全量映射

每行覆盖来源对应 FR 的全部业务边界；Windows 目标详见链接。含系统差异的一行不代表其余业务逻辑不可行。

| 来源要求 | 裁决 | 保留的行为与 Windows 差异／替代 |
|---|---|---|
| [FR-01](REQUIREMENTS.md#fr-01) 启动／空库／菜单／退出 | 可行但有差异 | 迁移、跨天、空库、工具条恢复、关闭辅助窗不退、编辑屏障均保留。菜单栏常驻／无 Dock 改托盘与任务栏策略；强制关机不能承诺取消。替代 A、H。 |
| [FR-02](REQUIREMENTS.md#fr-02) 新建／配色 | 可行但有差异 | 同入口、组词拒绝、多选退出、收起展开、默认尺寸、避让级联、最少色及已删最近候选均可做。⌘N→Ctrl+N，桌面层近似、激活可能被拒。替代 B、D、E。 |
| [FR-03](REQUIREMENTS.md#fr-03) 原生编辑 | 可行但有差异 | 可空标题、摘要、完成／划掉互斥、进度、排序、视觉行箭头、粘贴拆项、0.4s、安全提交、空白清理可做。NSTextView→WPF TextBox 输入链，快捷键改 Ctrl；第三方 IME／撤销边界无自动保证。替代 E。 |
| [FR-04](REQUIREMENTS.md#fr-04) 删除／恢复 | 可行 | 选择和焦点分离、无工具条删除、软删、5 秒严格边界、最新逐次／批次原子撤销、新输入后文字撤销、队列不跨重启、30 天仅列表、同时间子项恢复、已归档／冻结不变均为应用逻辑。组词屏障依 E。 |
| [FR-05](REQUIREMENTS.md#fr-05) 自由／折叠／停靠 | 可行但有差异 | 拖缩、自动高、顶位置、单张菜单、自由还原、排序拖出／溢出／分页及菜单次序可做。Mac 可用区→Windows 工作区，AppBar 与任务栏避让；不迁移虚构旧全局停靠字段。替代 F、G。 |
| [FR-06](REQUIREMENTS.md#fr-06) 瀑布流／分页 | 可行 | 持久顺序、最短列左优先／放不下换页、手动与自动高、折叠占位、停靠转自由、工具条完整目标避让、全屏共用页码／最后页、新建默认可见、收起整理展开均可做。几何换算依 G。 |
| [FR-07](REQUIREMENTS.md#fr-07) 全局收起 | 可行 | 真实窗口汇聚隐藏、当前页恢复、位置尺寸层级保留、叠放／圆形数量、99+、结束浮起、空目标清除、目标持久化、快速反向均可做；减少动画时直接落位。 |
| [FR-08](REQUIREMENTS.md#fr-08) 工具条 | 可行但有差异 | 五动作、方向、非抢焦点、4／81 阈值、边同距优先级、内边排除、锚点、闲置各条件、140ms／1.5s、反向状态机可做。VoiceOver→Windows 辅助技术策略；遮挡／全屏不能保证边缘接收。替代 A、C、E、F。 |
| [FR-09](REQUIREMENTS.md#fr-09) 三层／浮起／全屏空间 | 可行但有差异 | 逐张保存层级、真实窗临时提升、收起展开、Esc 等结束路径、无全局事件监听、激活失败替代入口可做。严格桌面层、全屏辅助空间和全桌面可见不能等价。Mac 旧全局偏好退役提示不适用于全新 Windows。替代 B、C、D。 |
| [FR-10](REQUIREMENTS.md#fr-10) 跨天／归档／备份 | 可行 | 当前时区、公历、04:00 可改、DST、约30s／启动唤醒时钟变化、初始不造历史、只封存已观察日、不补中间日、回拨高水位、冻结、组词延期、单事务推进、失败仅日志／7份副本可做；电源消息非执行时刻保证，依 H。 |
| [FR-11](REQUIREMENTS.md#fr-11) 历史 | 可行 | 周一起始、月导航、冻结详情、删除／顺延、分母排除划掉但含删除、跨日按次数、月不平均、零分母“—”、只读／空态均可做。 |
| [FR-12](REQUIREMENTS.md#fr-12) 设置／热键／启动 | 可行但有差异 | 分组即时修改、首次拒绝不再问、导入不动系统项可做。Carbon 物理 ANSI 和 Mac 禁用组合不照搬，RegisterHotKey VK 有保留键／AltGr；SMAppService 状态不能套 Run 项。替代 D、H。 |
| [FR-13](REQUIREMENTS.md#fr-13) 导出／导入／本地 | 可行但有差异 | 提交→一致快照→文件面板→原子发布，staging／替换确认／候选热键／事务替库、失败保旧、浮起键后失败不回滚、成功清会话、偏好归属、后续跨天可做。Mac JSON 字段编码／坐标不直接等价，Windows 协议待冻结。替代 I。 |
| [FR-14](REQUIREMENTS.md#fr-14) 字号 | 可行但有差异 | 四档、示例、全便签、端点、自动／固定高、停靠重排、组词拒绝、本机偏好不导出均可做。⌘→Ctrl，字体度量／系统文本缩放另适配。替代 E、G。 |
| [FR-15](REQUIREMENTS.md#fr-15) 多选 | 可行但有差异 | 同手势进入、勾选／框替换追加、空白清空、当前可见全选、批删及撤销、真实窗提升、覆盖层、隐藏排除、退出恢复原浮起、模式外桌面归系统均可做。⌘→Ctrl，跨屏物理坐标转换和当前虚拟桌面可见过滤；不全局截桌面事件。替代 D、E、G。 |
| 错误／质量边界 | 可行但有差异 | 明确启动错误、非激活后台提示、设置可复制、历史重试、深浅／减少动画／关键名称可做。Windows 高对比、UI Automation／Narrator 替代 VoiceOver；强制终止／关机不受提交取消保证。替代 E、G、H。 |

## 系统语义逐项裁决与多个替代方案

<a id="a"></a>
### A：菜单栏 accessory、无 Dock 与工具条非激活

**可行但有差异**。通知区域不是 macOS 菜单栏；WS_EX_TOOLWINDOW 可影响任务栏／Alt+Tab，WS_EX_NOACTIVATE 会限制激活，不能给编辑窗永久使用。依据：[扩展样式](https://learn.microsoft.com/en-us/windows/win32/winmsg/extended-window-styles)、[NotifyIcon](https://learn.microsoft.com/en-us/dotnet/api/system.windows.forms.notifyicon)。

1. **推荐：托盘常驻＋便签不占任务栏＋普通辅助窗口**。界面安静、Windows 用户熟悉；托盘可能被隐藏，必须保留可见工具条与热键。
2. 单一普通任务栏主窗口聚合入口。键盘切换和恢复容易；增加常驻任务栏占位，弱化桌面便签体验。
3. 所有窗口都设非激活工具窗。焦点干扰少；编辑／辅助技术受限，不推荐。工具条可非激活显示，菜单及键盘路径仍需可达，需 Windows 真机验证。

<a id="b"></a>
### B：严格桌面层、Z 序与 WorkerW／Progman

**严格“图标之上且普通窗口之下”不可行**；近似靠后模式**可行但有差异**。公开 SetWindowPos 只提供通用 Z 序，HWND_BOTTOM 不为应用预留 Shell 图标与应用间专用层。[公开 Z 序合同](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowpos)

1. **推荐：靠后近似＋普通＋置顶三档**。靠后仅在失活／放回请求 bottom，编辑可提升；公开、可维护，不能保证 Show Desktop、桌面图标关系或持续最底，UI 必须写明“桌面近似”。
2. 全部用普通非置顶窗口，配合收起／浮起。系统行为最清楚、稳定性更好；失去桌面感，可作为靠后小样失败后的保守回退。
3. 独立普通“便签桌面”容器承载全部卡片。内部图标／层级可控；不再每张独立系统窗口，移动和浮起语义需要改版。
4. WorkerW／Progman 下挂窗口、查类名、发送未公开 Shell 消息。可能接近桌面宿主；依赖未公开层次，常在图标后而非所需层，受 Explorer 重启／系统升级影响。**只作不推荐的脆弱实验方向，不是支持合同，不列实施路径**。没有公开“WorkerW 桌面便签 API”；不能用一次实验成功推导保证。

<a id="c"></a>
### C：全屏辅助空间、独占全屏及边缘 reveal

**保证覆盖独占全屏／安全桌面不可行**；普通桌面和部分无边框全屏的 topmost／边缘入口**可行但有差异**。Windows topmost 不是 macOS fullScreenAuxiliary，也不是高于系统 UI 的权限。圆形被遮挡后没有本地指针消息，不能凭计时器保证边缘唤起。

1. **推荐：可见时本地悬停；全屏时用热键／托盘显式召回**。无需全局监听和权限；热键被系统或应用拦截、前台被拒、独占呈现时仍可能无法显示，必须能在退出全屏后恢复。
2. 用户可选持续 topmost 工具条。一般桌面更易访问；遮挡其他应用，仍不能覆盖独占／UAC，需额外关闭入口。
3. AppBar 自动隐藏边条。公开 Shell 协调能力较强；可能改变工作区、与任务栏边缘冲突，全屏通知通常要求配合降层，仍非独占全屏覆盖保证。非默认，详 F。
4. 提示用户退出全屏后使用工具条。最可靠且最少干扰；多一步操作，是不可覆盖情况下的最终降级，不注入游戏／不切换安全桌面。以上实际呈现需 Windows 真机验证。

<a id="d"></a>
### D：Spaces、全局热键、前台激活和层级恢复

Spaces 辅助窗／所有空间可见的严格等价 **不可行**；自有窗口所属虚拟桌面查询／移动 **可行但有差异**。公开 IVirtualDesktopManager 提供 GetWindowDesktopId、IsWindowOnCurrentVirtualDesktop、MoveWindowToDesktop，未提供“固定全部桌面”或自由枚举／切换桌面的合同。[公开接口](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nn-shobjidl_core-ivirtualdesktopmanager)

1. **推荐：遵循系统所属桌面，不自动切换／搬移**。不打断用户；其他桌面的便签不会随浮起自动出现，提供说明和系统任务视图路径。
2. 用户在任务视图中手动选择“在所有桌面显示”（具体系统 UI／是否可选需真机确认）。无需私有 API；是用户设置，不可由应用保证或静默代办。
3. 以后提供显式“移到目标桌面”，仅当有合法取得的目标 GUID 并对自有窗口调用 MoveWindowToDesktop。可控但难以构成完整桌面选择 UI，不虚构枚举 API。私有虚拟桌面 COM 接口不推荐。

Carbon→RegisterHotKey **可行但有差异**，不是权限相同的逐键替换。Windows 键组合由系统保留，F12 有系统用途，已占用可能注册失败；此产品仅接受至少含 Ctrl 的有限集合。[RegisterHotKey](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey)

热键替代：①**推荐默认 Ctrl+Alt+N/F，可录制其他 Ctrl 组合**，常用但 AltGr 布局有风险；②默认 Ctrl+Shift+N/F，避开 AltGr，但易与其他软件重叠；③不用全局键、只用托盘，冲突最少但召回慢。冲突必须保旧，不能通过键盘钩子抢占。

前台激活和跨应用离开检测 **可行但有差异**。SetForegroundWindow 可被拒，即使满足条件也不保证成功。①**推荐用户触发后请求一次，失败提示点击**，守系统焦点规则；②仅显示不激活，干扰少但不能直接输入；③改用普通任务栏窗口便于用户切换，增加界面占位。不模拟输入绕前台锁。[前台限制](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setforegroundwindow)

<a id="e"></a>
### E：NSTextView、焦点、快捷键与辅助技术

**可行但有差异**。Windows TSF 与 WPF 文字输入提供合理基础，不能宣称与 NSTextView 行为逐字一致，特别是组词、候选窗、选区和独立撤销。[WPF 输入](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/advanced/input-overview)、[TSF](https://learn.microsoft.com/en-us/windows/win32/tsf/text-services-framework)

1. **推荐 WPF TextBox＋组合状态协调**：系统文字链、独立控件状态、视觉模板易控制；需测试 routed events、Return、失焦与 Undo。
2. Win32 Rich Edit 承载文字：系统控件路径成熟；WPF HWND 混合的裁剪／缩放／焦点及样式整合成本更高，可作为 TextBox 小样失败后的替代。
3. WinUI TextBox／RichEditBox：Fluent 控件一致；迁移主 UI 和多窗口互操作工作量较大。
4. WebView2 的 textarea／contenteditable：便于复用原型；浏览器 composition、宿主激活和多窗桥接增加变量。不自行绘制完整 TSF 编辑器来省控件。

⌘→Ctrl、ANSI→VK 的键位差异不能消除：推荐 Windows 习惯映射；备选保留可配置快捷键增加自由但需冲突说明；完全模拟 Mac 键位会与 Windows 系统快捷键冲突，不推荐。

VoiceOver→UI Automation／Narrator **可行但有差异**。推荐标准控件及 AutomationPeer＋显式保持工具条展开；备选只依赖 SPI_GETSCREENREADER 自动停止收缩，工作量小但不能检测全部辅助技术；备选所有用户默认不自动收缩，可达性最好但偏离来源默认。**推荐保留来源默认，同时提供可靠手动覆盖**，读屏检测到时停计时，需 Windows 真机验证。

<a id="f"></a>
### F：停靠、任务栏工作区与 AppBar

**可行但有差异**。应用内停靠不是系统 AppBar；工作区随任务栏／其他 AppBar 变化，自动隐藏边缘有竞争。SHAppBarMessage 是公开注册／定位协议，但会影响别的应用可用区。[AppBar 文档](https://learn.microsoft.com/en-us/windows/win32/shell/application-desktop-toolbars)

1. **推荐应用内停靠／磁吸，不注册 AppBar**。不改变桌面空间、接近来源；最大化应用可盖住，依托盘／热键恢复。
2. 可选 AppBar 模式：通过 ABM_NEW／QUERYPOS／SETPOS，处理位置和全屏通知，退出 REMOVE。系统协调较完整；占屏、边缘冲突、全屏降层和自动隐藏均需专门设计，不是每张便签都注册。
3. 仅普通自由布局＋整理。实现最少、行为清楚；损失停靠条及溢出入口，作为失败降级需显式修改需求。

<a id="g"></a>
### G：材质、圆角、DPI、主题与 Reduce Motion

Mac vibrancy **可行但有差异**，并非当前便签必需（来源便签／工具条本就纯色）。①**推荐纯色主表面＋辅助窗可选公开 Mica／Acrylic**，稳定可读，材质可能回退；②全纯色，最可预测但系统材质感少；③改 WinUI 3 SystemBackdrop，集成路径更直接，但增加主栈或混合窗口成本。不得用未公开 SetWindowCompositionAttribute／私有 DWM 属性作为推荐方案。[公开 backdrop](https://learn.microsoft.com/en-us/windows/win32/api/dwmapi/ne-dwmapi-dwm_systembackdrop_type)

精确 Mac 外圆角／阴影 **可行但有差异**。①**推荐系统非客户区＋内部视觉圆角**，保留系统行为但半径不精确；②自绘透明外壳，可控但阴影、DPI 和命中代价大；③标准矩形壳最稳但审美偏离。先小样后定，不承诺任意 WPF 透明窗口都有 DWM 效果。

多屏 DPI／工作区 **可行但有差异**。①**推荐 manifest PerMonitorV2＋逐窗 DPI 转换**，跟屏清晰，需正确处理物理坐标与 DIP；②系统 DPI aware，工作量低但换屏可能模糊，不达首选品质；③单屏限制，最简单但失去来源多屏能力，不推荐。[DPI 声明](https://learn.microsoft.com/en-us/windows/win32/hidpi/setting-the-default-dpi-awareness-for-a-process)、[窗口 DPI](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getdpiforwindow)

Reduce Motion／深浅／高对比 **可行但有差异**。①**推荐公开系统参数／主题事件＋手动减少动画开关＋高对比语义资源**，最完整，增加状态适配；②只跟系统，设置简单但检测／更新不完整时无覆盖；③全禁动画，最稳定但失去正常视觉反馈。SPI_GETCLIENTAREAANIMATION 可查询客户区动画策略，不宣称等价 macOS 所有减少动态效果设置。[系统参数](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow)

<a id="h"></a>
### H：SMAppService、睡眠唤醒、关机与本地可靠性

登录启动 **可行但有差异**：

1. **推荐普通个人安装使用 HKCU Run 自有值**：无需管理员、实现少；任务管理器／策略可能阻止，无法从值存在推导最终运行，不提供虚构待批准状态。[Run 项合同](https://learn.microsoft.com/en-us/windows/win32/setupapi/run-and-runonce-registry-keys)
2. MSIX＋StartupTask／IStartupTask：有打包清单和状态模型（如 DisabledByUser），系统集成更完整；增加打包身份、安装和更新成本，不得在无包身份项目中直接声称可用。[StartupTask](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.startuptask?view=winrt-26100)
3. 当前用户 Startup 文件夹快捷方式：直观可手工检查；路径更新和用户移动会失效，状态仍不是 SMAppService。适合作为用户手动替代，不同时注册多个入口。

睡眠／恢复、时钟变化检查 **可行**，但系统挂起时不运行定时器，不保证即时保存或跨天。WM_POWERBROADCAST 的恢复通知＋启动／定时补检查保留来源非秒级语义。[电源消息](https://learn.microsoft.com/en-us/windows/win32/power/wm-powerbroadcast)

“退出前可取消”只对主动退出成立；**保证阻止强制关机／杀进程不可行**。①**推荐持续 debounce＋边界事务提交＋副本**，日常损失小但未提交组词可能丢；②每次有效输入都同步提交，减小窗口但易阻塞输入、不解决未提交组词；③关机会话通知尝试保存，补救有效但有时限／可被强制结束。推荐①并加③的尽力处理，不以关机阻止当持久化保证。

<a id="i"></a>
### I：Mac 数据协议与 Windows 备份

Windows 本地 SQLite 与独立 JSON 备份 **可行**；直接宣称现有 Mac 格式可互通 **可行但有差异，当前未定义兼容支持**。

1. **推荐 Windows 独立显式 DTO／版本协议**，能完整定义字段和回滚，开发少；初期不能直接导入 Mac 文件。实施前冻结协议与样本，见 [技术协议边界](TECHNICAL_DESIGN.md#backup)。
2. 单独 Mac→Windows 转换器：取得真实导出样本、验证 Swift 日期／ID／枚举、转换坐标及热键，保留业务语义；需要双平台黄金样本和兼容测试，不能本轮猜载荷。
3. 从第一版就统一跨平台协议：长期互通好；需要 Mac 侧协同与迁移，超出本轮只写 Windows 文档范围，不能修改只读来源来达成。

<a id="privacy"></a>
### J：截图保护与不在范围功能

来源明确不含屏幕共享自动隐藏／隐私锁；Windows 同样不增加该承诺。SetWindowDisplayAffinity **可行但有差异**地限制部分捕获路径，不是加密／DRM／自动检测共享。WDA_EXCLUDEFROMCAPTURE 从 Windows 10 2004 起支持，并不保证阻止所有捕获方式。[官方限制](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity)

若将来新增隐私功能：①**当前推荐不启用，清楚声明本地未加密**，范围明确但共享时可被看见；②用户主动隐藏所有便签，直观但要手动操作；③逐顶层窗口设置 affinity，部分捕获可排除但必须标注局限和验证捕获工具，不得命名为“共享自动隐藏”。

<a id="stack"></a>
## 技术栈比较与唯一推荐

以下为本产品设计权衡，不是基准测试。优先顺序为优雅视觉／原生品质、中文 IME 与多窗口编辑、合理实现成本；无内存优化指标，个人本地应用，无云同步需求。每种栈都仍受同一 Windows Z 序／全屏／虚拟桌面限制，换栈不消除 B／C／D。

| 候选 | 美观与视觉还原 | 中文 IME／文字编辑 | 多便签独立窗口 | 工作量与本产品适配 |
|---|---|---|---|---|
| **WPF + .NET + Win32** | XAML 模板、向量布局和动画可精确表达卡片；默认控件需主动做现代视觉 | TextBox 系统输入链可保留，组合／撤销要实测 | Window／HWND 模型清楚，Z 序／消息可互操作 | **推荐**；本地 SQLite、托盘和设置整合直接；主要风险为壳层、IME 事件和 DPI |
| WinUI 3／Windows App SDK | Fluent 控件、SystemBackdrop 原生感最强，定制卡片也可做 | TextBox／RichEditBox 路径可用，仍须逐 IME 验证 | 官方支持多窗口；特殊非激活／托盘／层级还要 HWND 互操作 | 严肃次选；更现代默认外观，但此产品大量小窗与自定义壳层仍需适配、部署 App SDK 增成本 |
| Win32 + C++，Direct2D／DirectWrite + Rich Edit | 上限高、系统壳层控制最直接；完整 Fluent 外观需自建 | Rich Edit 可用；若自绘编辑则 TSF／选区／撤销成本显著 | HWND 原生直接，逐窗管理自然 | 工作量最大之一，UIA／布局／主题都需补，不为此个人应用首选 |
| Tauri 复用（Rust + WebView2） | CSS 还原卡片方便，系统原生菜单／文字度量另适配 | 浏览器输入可用；composition＋宿主焦点＋桥接更复杂 | 可多 WebView 窗，层级仍要 Win32 插件／桥接 | 仅有 HTML 说明模型不等于完整可复用应用；Swift/AppKit 不可直接复用，不接受旧 Tauri 数据自动迁移假设 |
| Avalonia + .NET | XAML 自绘一致，卡片外观自由；Windows 原生细节需主题／平台适配 | 跨平台文字链可用，Windows IME／候选和辅助技术要验证 | 支持多窗口，特殊 HWND 服务要平台适配 | 若未来重视跨平台共享可考虑；当前只有 Windows 目标，跨平台抽象收益较小 |
| Qt 6 Widgets／Quick + C++ | Quick 定制和动画成熟，Windows 标题栏／菜单可整合；Fluent 风格需额外工作 | Qt 输入法体系可用，中文与自定义编辑需验证 | 多顶层窗成熟，平台层仍需 Win32 | 团队已有 Qt 经验时合理；部署和许可选项需审阅，对纯 Windows 个人应用不比 WPF 简单 |
| Electron + Web 技术 | CSS 视觉自由，原生外观需补 | Chromium 输入链可用，宿主／多窗仍需组合输入验证 | BrowserWindow 多窗可做，Z 序等仍须平台桥接 | 不因内存排除；本任务没有现有完整前端可复用，增加浏览器及 Node 生命周期／更新面，不推荐 |

唯一推荐 **WPF + C#／稳定受支持的 .NET LTS + SQLite + 公开 Win32**。这是基于本产品以精致自定义便签为主、需要真实独立编辑窗口、无需跨平台共享的判断，不是宣称 WPF 默认比 WinUI 更漂亮。先投入卡片模板、排版、菜单和系统铬的小样，再实现业务；不为省工作量退到全网页编辑或自绘输入法。主要风险是透明外壳和 DWM 兼容、组合输入与结构命令、各屏 DPI 和非激活工具条。若小样证明 WPF 壳层无法达到视觉标准，应先评估 WinUI 3 替代，明确更换决定而非叠加两套主 UI。

技术依据：[WPF 官方](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/overview/)、[Windows App SDK](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/)、[Tauri Windows WebView2](https://v2.tauri.app/reference/webview-versions/)、[Avalonia 支持平台](https://docs.avaloniaui.net/docs/supported-platforms)、[Qt 输入法](https://doc.qt.io/qt-6/qinputmethod.html)、[Electron BrowserWindow](https://www.electronjs.org/docs/latest/api/browser-window)。平台文档说明能力入口，表中优先级与成本是设计推断。

<a id="verification"></a>
## 未来 Windows 验证门槛（全部未执行）

1. **原生小样先行**：在选定稳定 .NET 和 Windows 11 真机，做独立便签、非激活工具条、系统阴影／圆角、普通辅助窗、托盘和两热键。用微软拼音、微软五笔及至少一种第三方中文 IME 检查候选窗、Return／Esc、首字符、选区、Undo、失焦和新建，不通过先解决框架路径。
2. **窗口系统**：靠后／普通／置顶、Win+D、最大化、无边框／独占全屏、不同应用权限、UAC／锁屏边界、虚拟桌面切换、任务视图、Explorer 重启、热键被占和前台拒绝。记录预期限制，不把无法覆盖系统窗口当作失败后用私有 API 绕过。
3. **显示与可访问性**：100／125／150／200% 混合 DPI，负坐标／主屏切换／拔屏、任务栏自动隐藏、接缝吸边、多屏框选、远程会话、深浅／高对比、透明关闭、系统大文本、Narrator、保持工具条展开与减少动画。
4. **业务与输入组合**：逐 [FR](REQUIREMENTS.md) 验证四种展示状态、浮起／多选叠加、批次撤销 5 秒边界、30 天删除列表、溢出／分页、组词中导入／退出／字号／跨天、旧编辑器回调失效。测试状态结果，不写镜像实现的空测试。
5. **数据安全**：隔离库跑迁移、冻结不可改、事务回滚、导入往返／无效引用／未来版本／取消／热键冲突、磁盘满／权限拒绝、备份 7 份／同日不覆盖／partial、离线恢复及强制终止。夏令时、回拨、改时区、休眠跨多日必须用可注入时钟和真实系统事件分别验证。
6. **登录启动**：稳定安装路径下首次拒绝／同意、设置关闭、任务管理器禁用后不绕过、重新登录、exe 路径更新和卸载清理；若改 MSIX 重新验证 StartupTask 各状态，不复用 Run 项结论。

每次记录 Windows build、硬件／DPI、IME 版本、.NET／依赖版本、代码 SHA、命令和退出码、实际操作结果、截图／日志路径及失败／未执行项。API 文档核查、Linux 链接检查、Windows 编译、自动业务测试、真机人工验收分开记。Mac ACCEPTANCE.md 的 Swift 测试及浏览器结果均不计入 Windows 通过项。

## 本轮证据范围

本轮只完成来源全文阅读、视觉参考查看、公开文档核查和 Markdown 静态检查；没有 Windows 工程、构建命令、SDK 调用或运行截图。
