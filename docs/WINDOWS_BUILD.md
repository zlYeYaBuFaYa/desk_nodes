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

Linux 本轮实际执行的命令：

```bash
export PATH=$HOME/.dotnet:$PATH DOTNET_ROOT=$HOME/.dotnet DOTNET_CLI_TELEMETRY_OPTOUT=1
dotnet publish src/DeskNodes.App -c Release -p:PublishProfile=win-x64 -o /tmp/desknodes-publish-x64
dotnet publish src/DeskNodes.App -c Release -p:PublishProfile=win-arm64 -o /tmp/desknodes-publish-arm64
```

x64 产物 `DeskNodes.App.exe` 为 **227,679,315 字节（约 217.13 MiB）**，未获取文楷；字体打包会增加数十 MB，SDK/依赖变化也会影响大小。ARM64 产物 `DeskNodes.App.exe` 为 **241,368,029 字节（约 230.19 MiB）**，同样未获取文楷；两个架构均为**仅交叉发布，未真机运行**，临时发布目录已删除。旁边的 PDB 用于诊断，不是运行依赖。产物未入库。用户运行 exe 无需安装 .NET 运行时；自包含运行时安全更新需要重新发布。

项目及两个配置启用 `IncludeNativeLibrariesForSelfExtract=true`，将 SQLite 的 `e_sqlite3.dll` 等原生库纳入单文件，在 Windows 启动时由运行时解压加载；目标机器需允许运行时临时目录写入。本轮确认 bundle 包含 e_sqlite3，**尚未验证 Windows 实际解压和数据库读写**。应将 exe 单独复制到干净 Windows 机器，执行新建、重启读取、导出与导入，检查 Logs 无 DllNotFoundException。

`PublishReadyToRun=false`：减小产物并保持 Linux 跨架构发布流程一致，代价是首次启动仍有 JIT 成本。若以后改为 true，需要适配跨平台编译工具、比较启动收益与体积，并重新验证两个架构；本轮不宣称启动性能结果。未启用 trimming，保留 WPF 所需反射路径。

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

本轮 Linux 证据：Release build 0 警告／0 错误，测试 371 通过、0 失败、0 跳过；x64 与 ARM64 交叉发布均成功（0 警告／0 错误）。ICO 七层结构、AND 掩码与重复生成字节一致性检查通过。所有 Windows 清单项均未执行。
