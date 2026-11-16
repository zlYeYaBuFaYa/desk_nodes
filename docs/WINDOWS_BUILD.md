# Windows 构建、发布与手工验证

当前已有 WPF/.NET 10 实现，尚未在 Windows 真机验收。**Linux 交叉编译和单元测试通过 ≠ Windows 验收。** 平台限制与验收门槛见 [FEASIBILITY](FEASIBILITY.md#verification)，实现取舍见 [DECISIONS](DECISIONS.md)，备份协议见 [BACKUP_FORMAT](BACKUP_FORMAT.md)。

## 前置条件与获取代码

- Windows 11 22H2+ x64；这是技术最低基线，部署应选仍受支持的系统版本。
- .NET 10 SDK **10.0.404**，与根目录 [global.json](../global.json) 一致（允许 latestFeature 滚动）；`dotnet --version` 记录实际解析版本。
- Git；可选 Visual Studio 2026、Rider 或 VS Code + C# Dev Kit；可选 PowerShell 7。命令可用 Windows PowerShell 执行。

```powershell
git clone --branch feat-win <仓库地址> desknodes-win
cd desknodes-win
dotnet --version
dotnet restore DeskNodes.sln
```

仓库地址使用当前代码托管平台提供的克隆地址。发布前记录 `git rev-parse HEAD` 与 `git status --short`，有未提交改动时同时保留 diff。

## 字体与图标

显式运行获取脚本，联网下载固定霞鹜文楷 v1.530 的 Regular、Medium 和 OFL.txt，并核验三个 SHA-256：

```powershell
powershell -NoProfile -File build/fetch-fonts.ps1
```

PowerShell 7 也可用 `pwsh -File build/fetch-fonts.ps1`；Linux 可用 `bash build/fetch-fonts.sh`。字体保存到 `src/DeskNodes.App/Resources/Fonts/`，被 gitignore，存在才作为 WPF 资源打包，不安装系统字体。构建不会自动联网获取字体。未获取时仍可构建运行，设置显示文楷“未包含”并禁止切换；打包字体后需重新构建。授权优先应用内只读窗口，包内缺失时打开固定版本在线页。

应用与托盘共用内嵌 `Assets/DeskNodes.ico`。可选安装 Python 3 后运行 `python build/generate-icon.py`，只用标准库，无网络依赖，可重复生成 16/20/24/32/48/64/256 图层。16/20/24/32/48/64 图层使用 32 位 BGRA DIB（BITMAPINFOHEADER、高度为图层高度的两倍、含 DWORD 对齐 AND 掩码），256 图层保留 PNG。ICO 已入库，无需为普通构建安装 Python。托盘通过公开 SHAppBarMessage 查询主任务栏所在屏幕 DPI，以 GetSystemMetricsForDpi(SM_CXSMICON, dpi) 选择图层；显示／DPI 变化及 Explorer 重建时刷新。资源读取失败记录日志并回退系统默认应用图标。

## 调试、测试与隔离实例

```powershell
dotnet run --project src/DeskNodes.App
dotnet build DeskNodes.sln -c Release
dotnet test DeskNodes.sln -c Release
```

手工验证前先使用空的独立目录：

```powershell
$env:DESKNODES_DATA_DIR = Join-Path $env:TEMP 'DeskNodes-W11-Test'
dotnet run --project src/DeskNodes.App
Remove-Item Env:DESKNODES_DATA_DIR
```

该变量覆盖整个数据目录；同一目录第二次启动只唤起工具条，不同目录可并存。隔离实例禁止修改登录启动项。变量按进程继承，关闭应用后再清除变量；单实例验证可在另一终端使用同一值运行。

## 自包含单文件发布

```powershell
dotnet publish src/DeskNodes.App -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o ./publish/win-x64
# 等价的发布配置入口（配置内也指定 Release）
dotnet publish src/DeskNodes.App -c Release -p:PublishProfile=win-x64 -o ./publish/win-x64
# ARM64 配置：已完成 Linux 交叉发布，未真机运行
dotnet publish src/DeskNodes.App -c Release -p:PublishProfile=win-arm64 -o ./publish/win-arm64
```

发布实测统一见[当前验证证据](#当前验证证据)。旁边的 PDB 用于诊断，不是运行依赖；产物不入库。用户运行 exe 无需安装 .NET 运行时，自包含运行时安全更新需要重新发布。

项目及两个配置启用 `IncludeNativeLibrariesForSelfExtract=true`，将 SQLite 的 `e_sqlite3.dll` 等原生库纳入单文件，在 Windows 启动时由运行时解压加载；目标机器需允许运行时临时目录写入。本轮确认 bundle 包含 e_sqlite3，**尚未验证 Windows 实际解压和数据库读写**。应将 exe 单独复制到干净 Windows 机器，执行新建、重启读取、导出与导入，检查 Logs 无 DllNotFoundException。

`PublishReadyToRun=false`：减小产物并保持 Linux 跨架构发布流程一致，代价是首次启动仍有 JIT 成本。若以后改为 true，需要适配跨平台编译工具、比较启动收益与体积，并重新验证两个架构；本轮不宣称启动性能结果。未启用 trimming，保留 WPF 所需反射路径。

## 当前验证证据

这是构建、测试、发布实测的唯一证据入口；其他文档只链接本节。日期：2026-11-15，环境：Linux，Windows 清单全部待执行。**交叉构建／发布不能证明 Windows 运行或验收通过。**

- SHA：**以提交时 HEAD 为准**。本次执行基线为 `bbce1bc`，仅有本批文档改动；生成完整 SHA 用 `git rev-parse HEAD`，同时用 `git status --short` 和 `git diff -- docs/` 保留未提交差异。提交文档后应重新记录 HEAD，本节不预写未来 SHA。
- 实际 SDK：`10.0.404`（`dotnet --version`）。
- Release 构建成功：0 警告、0 错误。
- `dotnet test DeskNodes.sln -c Release`：总计 **465**，通过 **465**，失败 **0**，跳过 **0**。运行器另提示缺失 `VSTEST_ARTIFACTS_DIRECTORY` 并回退临时目录，不影响通过结果。
- 当前 win-x64 自包含单文件交叉发布成功：`DeskNodes.App.exe` **254,333,201 字节**；字体状态：已包含文楷 v1.530 Regular、Medium 和 OFL（现有资源目录参与重新构建）。不与字体打包状态未记录的历史体积直接比较。
- **历史 win-arm64**：`DeskNodes.App.exe` **241,368,029 字节**，字体打包状态未记录（当时本机已存在字体文件，可能已打包），仅 Linux 交叉发布。来源：提交 `17ff08d` 的 `docs/WINDOWS_BUILD.md`，可用 `git show 17ff08d:docs/WINDOWS_BUILD.md` 查看；本次未重跑，不能代表当前 ARM64 产物。

本次执行命令（重新构建避免增量资源缓存影响字体打包）：

```bash
export PATH=$HOME/.dotnet:$PATH DOTNET_ROOT=$HOME/.dotnet DOTNET_CLI_TELEMETRY_OPTOUT=1
git rev-parse HEAD
git status --short
dotnet --version
dotnet build DeskNodes.sln -c Release
dotnet test DeskNodes.sln -c Release
dotnet publish src/DeskNodes.App -c Release -p:PublishProfile=win-x64 -p:NoIncremental=true -t:Rebuild,Publish -o /tmp/desknodes-doc-review-x64
stat -c '%n %s bytes' /tmp/desknodes-doc-review-x64/DeskNodes.App.exe
```

PowerShell 取精确字节可用 `(Get-Item <发布目录>/DeskNodes.App.exe).Length`。历史文本缩放修改的体积比较不作为当前发布证据；Windows SDK／WinRT 投影增加依赖，目标版本选择见 [D32](DECISIONS.md#d32-系统文本缩放与-windows-sdk-目标)。

## 数据、日志与卸载

默认数据目录 `%LOCALAPPDATA%\DeskNodes`：`DeskNodes.sqlite3`（及运行期间 SQLite 辅助文件）、`Logs\DeskNodes.log`（轮转 `.1`）、`Backups` 自动备份、`LocalPreferences.json` 本机偏好。设置业务数据在数据库中，备份格式与安全导入见 [BACKUP_FORMAT](BACKUP_FORMAT.md)。隔离实例这些文件均位于覆盖目录。

卸载前从托盘退出，先导出或复制所需备份。删除自有登录启动值和应用目录；确认无需数据后再删除数据目录：

```powershell
Remove-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name DeskNodes -ErrorAction SilentlyContinue
# 以下删除操作不可恢复，先备份，再显式执行：
Remove-Item -Recurse -Force (Join-Path $env:LOCALAPPDATA 'DeskNodes')
```

程序不修改 StartupApproved，不移除系统字体。隔离验证目录可另行删除。

## Windows 手工验证清单（当前全部待执行）

每个条目保存实际结果和截图，失败与未执行单独记录。先对照 [验证门槛 1–9](FEASIBILITY.md#verification)；以下为可执行步骤，不构成已通过声明。

- [ ] 对照各屏 GetDpiForMonitor 与窗口 GetDpiForWindow，有不同 DPI、跨屏及远程会话时记录差异，决定是否替换探测方案。
- [ ] 系统文本缩放分别设 100/150/200%，与显示 DPI 交叉；打开设置、历史及四档字号便签，实时切换，检查固定／自动高、滚动、组词与编辑缓冲保留及无裁字。
- [ ] 有历史／空历史两种状态反复打开托盘菜单数百次，记录 USER/GDI 句柄及 hosted Control 释放情况，确认句柄稳定。
- [ ] 导入上限内的大文件期间继续操作界面，记录 UI 响应与耗时，检查取消、失败、替库串行及旧回调失效。
- [ ] 在干净 x64 机器仅复制 exe 运行；新建中英文事项、重启读取、导出再导入，确认 SQLite 加载及托盘图标清晰；记录字体是否包含。
- [ ] 分别使用微软拼音、微软五笔、一种第三方中文 IME：连续组词、选择候选窗、Return 确认、Esc 取消、首字符输入；拖选文本并撤销；点候选窗和其他应用，确认不误提交、不丢选区。组词中尝试新建、字号切换、导入、退出、跨天，检查屏障与旧编辑回调失效。
- [ ] 在不同背景移动／缩放便签，检查 WindowChrome 圆角、系统阴影、边缘无漏底；锁屏／UAC 后恢复检查窗口。
- [ ] 将多屏设为 100/125/150/200%（含负坐标），跨屏拖便签和工具条，记录 Left/Top 屏 DIP 与 SetWindowPos 物理像素换算；检查接缝、任务栏自动隐藏、主屏切换与拔屏后的可达性。
- [ ] 分别设靠后／普通／置顶，按 Win+D、打开最大化窗口、无边框及独占全屏应用，检查层级与恢复；切虚拟桌面、任务视图，确认不误复活隐藏便签。触发前台激活被拒，确认有可理解提示与托盘恢复入口。
- [ ] 编辑时点击工具条，确认不抢焦点；浅色 Mica／深色 Acrylic 下检查材质，关闭透明效果、切高对比、远程会话验证纯色回退。
- [ ] 观察弹簧展开、收缩、回归与先缩后滑；指针悬停约 140ms 唤起、离开后 1.5s 宽限；在拖动阈值上下移动比较点击／拖动；在 81 DIP 磁吸范围两侧松手，检查吸边及接缝回退。拖动固定收缩位置、按 Esc 取消，确认保存位置正确、无捕获残留；移动中唤起和菜单打开时检查计时暂停。
- [ ] 托盘左键显示、右键菜单可用；在任务管理器重启 Explorer 后确认托盘重建；第二次启动同目录实例只显示工具条；模拟唤起失败检查“已在运行”提示。检查手柄／空白／圆形右键及按钮无误弹菜单；退出后重启工具条展开。
- [ ] 新建多张便签，执行全局收起／展开汇聚；移动入口后再展开；浮起后按 Esc、切应用，检查结束及原层级恢复。进入多选并跨屏框选，核对黑色覆盖、所选窗口与操作条 Z 序；退出后桌面立即可点。
- [ ] 删除一张与批量删除，提示中 5 秒内撤销并比较内容、顺序；超时确认不再可撤销。在最近删除恢复整张及单项，确认无无关成员误恢复；检查 30 天边界与空白事项清理。
- [ ] 拖动停靠标签排序、拖出恢复、制造溢出并打开列表；多张整理触发分页，切页检查可见性；极小工作区检查无法避让时降级放置，不崩溃。
- [ ] 制造跨月的多个封存日，在历史菜单选日、周／月导航、Ctrl+方向、Ctrl+T、Tab 与文本选区，检查今天／未来禁用、日格色阶和深色可读性；比较空快照、读取失败与零恢复数提示。
- [ ] 设置跟随系统／浅／深并同时打开多个窗口，检查同步与便签固定浅色。四种字体 × 四档字号检查中英混排、计数、首行圆圈、折叠标题、固定／自动高、停靠；分别在幼圆已装／未装、文楷打包／未打包运行，检查禁用提示、Regular／Medium 与授权窗口。组词期间尝试切换。
- [ ] 录制并替换两个快捷键，制造与其他程序及彼此冲突，确认失败保留旧绑定；长按检查 MOD_NOREPEAT；在支持 AltGr 的键盘布局输入文本，确认不误触快捷键；通过便签 Ctrl+, 与托盘进入设置。
- [ ] 从稳定 exe 路径启用登录启动，核对 HKCU Run 带引号完整路径；关闭设置确认删值；任务管理器禁用后重启应用与重新登录，确认不绕过或重建；隔离实例和 dotnet 宿主运行尝试启用，确认拒绝。
- [ ] 改跨天时间后 Enter／失焦提交，无效输入恢复已保存值；睡眠跨天、多日唤醒、改时区、改系统时间前进／回拨、夏令时变化，检查封存、删除业务日与不补未观察日。
- [ ] 隔离数据中导出／导入往返，取消文件选择与覆盖确认；导入无效 JSON、未知字段、未来版本、无效引用，检查活库不变；新建热键冲突导入保留旧库，浮起冲突仅提示未生效。成功导入后确认撤销清空、多选／浮起结束、编辑窗口重建且不立即跨天。
- [ ] 对隔离目录模拟只读／磁盘满、强制终止再启动，检查错误提示与旧库完整；自动备份检查 7 份、同日不覆盖、partial 清理，离线恢复导出文件；外来／未来库启动失败不建空库。
- [ ] 打开高对比、Narrator、系统大文本及减少动画，逐个读出按钮名称、通过键盘访问菜单与辅助窗；保持工具条展开，确认无透明残留及不可达控件。

### 三组修复回归步骤（全部待执行）

#### 1. 偏好写入故障与恢复

- [ ] 在独立数据目录正常保存一组基线：方向、闲置时间、字号、分页、桌面收起状态、工具条完整位置和固定收缩位置；截图设置、菜单勾选和窗口坐标，退出后复制库与 `LocalPreferences.json` 作比对基线。
- [ ] 重新启动，以普通用户运行。用文件属性将 `LocalPreferences.json` 设为只读；若原子替换仍能成功，在该隔离目录的“安全→高级”中临时拒绝测试用户写入／创建文件／删除权限（保留读取，记录原 ACL）。必须先确认实际保存被拒，不能仅凭只读属性判定故障已注入。
- [ ] 分别从设置修改方向／字号，从工具条右键菜单修改方向／闲置时间／恢复默认收缩位置。每次只改一项，预期出现“无法保存设置……已恢复上次设置”提示；重新打开设置及菜单，旧值和勾选保持，工具条完整位置与固定位置恢复基线。便签菜单当前仅修改业务状态，没有本机偏好选项：在便签菜单切换颜色／层级，预期可正常写库且勾选同步；再从该便签按 Ctrl+, 打开设置改字号，验证同样的偏好失败提示与旧值恢复，勿把业务菜单误记为偏好写入入口。
- [ ] 故障保持期间执行整理（事先制造多页布局），比较所有便签位置、页码和可见性均保持旧状态；全局收起后尝试新建及最近删除恢复整张，展开偏好不能保存时应中止，不能产生新便签或恢复记录。
- [ ] 恢复原 ACL／清除只读，逐个从相同入口重试；预期保存成功、提示消失，设置和各菜单同步；退出重启后新值及布局保持。保留失败及成功日志，不把解除故障前的失败记成通过。

#### 2. 托盘工具条子菜单同步与持久化

- [ ] 从托盘右键“工具条”子菜单依次切横向、竖向；每次打开设置及工具条右键菜单，核对方向、勾选和实际排列一致，编辑中点击工具条不丢文本。
- [ ] 依次选自动收缩 10／15／30 秒及关闭，每次核对三个入口一致；将指针移开且关闭菜单，计时观察收缩，关闭时等待超过 30 秒仍展开。各档退出重启复测：保留选项，启动先展开并重新计时。
- [ ] 拖动圆形入口保存自定义固定位置，重启确认保持；从托盘子菜单恢复默认位置，设置示意、工具条菜单禁用／勾选状态及实际收缩终点同步；再重启验证默认位置保持。完整工具条摆放与固定收缩位置分别记录。

#### 3. 收缩边界、导入退出与编辑安全

- [ ] 分别录制入口已在固定位置时的原地收缩、自由位置的先缩后滑；在收缩／滑动／展开中拖动并按 Esc，预期从当前可见位置继续原目标动画，停靠预留及命中区域无抖动。
- [ ] 在顶部与左右停靠各放多张便签，通过显示分辨率／缩放及工作区调整，制造避让后沿边可用长度 120、介于 120–239、低于 120 DIP 三类边界；记录工作区像素、缩放及 DIP。空间足够时单张沿边长度不低于 120 DIP；不足时溢出标签覆盖在便签末端，入口可点、正文可滚动访问。打开溢出列表并切换便签；极小工作区同时检查顶部／左右停靠、工具条避让、内容与菜单可达，无负尺寸或崩溃。
- [ ] 在隔离库导入上限内的大备份，分别在读取／解析／staging 阶段从托盘或工具条菜单退出；预期进程有限等待后退出，不发生替库或旧 UI 回调。重新启动核对活库未变、无 `.import-*.sqlite3` 及对应 `-wal`／`-shm` 遗留。正常退出及时完成的导入应立即清理；超出等待或强杀场景应在下次启动清扫。
- [ ] 分别取消选文件、在替库确认对话框选取消，核对活库与编辑缓冲保持，临时文件清理；再造一个可识别的遗留 `.import-*.sqlite3`（只在应用关闭后的隔离目录）验证启动清扫。分别准备文件字节、解码后字符串长度、集合条数、嵌套深度的恰好上限／超过一单位样本（值见 [BACKUP_FORMAT](BACKUP_FORMAT.md)），核对恰好值通过输入限制、超限分类提示且活库不变。
- [ ] 第一实例正常运行时，从同一隔离目录启动第二实例，计时确认第二进程退出且第一实例工具条展开；再暂停第一进程，使管道无法及时响应，第二进程应在连接超时后提示已在运行并退出，不能无限挂起。恢复第一进程，确认无第二套写库与热键。
- [ ] 隔离库设置临近跨天时间，持续编辑未触发 debounce 的中文文本（另测组词中延迟跨天）；用另一 SQLite 连接的 `BEGIN IMMEDIATE` 暂时占用写锁，使封存保存失败，保留截图及日志。预期编辑器文字、选区不丢且不被旧库刷新覆盖，无部分封存；释放锁后等待重试，核对文字成功保存、封存与 checkpoint 一致且不重复。最后退出重启再比对正文与历史。

## 单次验证记录模板

```text
日期／执行者：
Windows 版本与 build／系统架构：
硬件／屏幕布局／各屏 DPI 与主屏：
IME 名称与版本／键盘布局：
.NET SDK／运行时／依赖版本：
代码 SHA／未提交 diff：
发布配置／字体是否打包：
隔离数据目录：
命令、退出码：
清单条目／操作步骤／预期：
实际结果（通过／失败／未执行）：
截图路径／日志路径：
已知限制或后续问题：
```
