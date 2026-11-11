# 本机 Mac 构建、运行与恢复

这些是给个人 Mac 执行的命令，**未在本次 Linux 环境执行或验证**。运行目标为 macOS 14+；构建主机还必须满足所选 Xcode 自身的系统要求。采用完整 Xcode 自带 macOS SDK 和默认 Swift 工具链；建议 Xcode 26.1/26.2（Swift 6.2.1）作为本次 Linux Swift 6.2.1 源码验证的对应起点。Apple 的 [Xcode 兼容表](https://developer.apple.com/xcode/system-requirements) 是工具链／主机要求的依据，不能把 macOS 14 运行下限当作这些 Xcode 的主机下限。更老 Xcode 未验证；更新工具链也必须重新完成 SDK 编译和 native tests。SwiftPM manifest 使用 Swift tools 5.9 / Swift 5 language mode，没有承诺 Swift 6 strict-language-mode 编译或通用二进制。

在仓库根目录，选择**已安装**的 Xcode 路径；环境变量只影响当前终端，不修改系统选择：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault
xcodebuild -version
xcrun swift --version
xcrun --sdk macosx --show-sdk-path
xcrun swift package clean
xcrun swift test
./scripts/build-macos.sh
/usr/bin/plutil -lint build/DeskNodes.app/Contents/Info.plist
/usr/bin/codesign --verify --strict --verbose=2 build/DeskNodes.app
/usr/bin/codesign -dv --verbose=4 build/DeskNodes.app
/usr/bin/codesign -d --entitlements :- build/DeskNodes.app
open build/DeskNodes.app
```

记录每条命令的退出码和输出。Mac 的 `swift test` 应编译全部目标，包括 AppKit 应用和 17 个 native XCTest 方法；必须在有图形登录会话的 Mac 上执行并报告实际发现／通过数，不能直接套用 Linux 的测试数量。测试使用临时 SQLite，不应修改个人库；native tests 会创建窗口，仍需手动验收真实输入法等行为。没有伪造 Darwin SDK、跨平台原生模拟或 Linux Mac 构建步骤。

脚本设置部署目标 14.0，构建当前主机架构的 release 产品，把可执行文件、Info.plist 与 `Resources/DeskNodes.icns` 放入 `.app`，先签名验证再替换仓库内 `build/DeskNodes.app`。不生成 universal 包，不处理分发、公证、付费身份或沙盒 entitlement。默认 `codesign --sign - --timestamp=none` 只提供本地 ad-hoc 签名；签名通过仍不证明运行、登录项或视觉验收通过。`LSUIElement=true` 与 `.accessory` 应无 Dock 图标；Finder 图标来自 bundle 资源，不需要 Dock 图标来展示。

已有适用的本地签名身份时，可以先查看并明确选择它；不会创建或安装身份：

```sh
/usr/bin/security find-identity -v -p codesigning
DESKNODES_SIGNING_IDENTITY='已有本地签名身份的名称或 SHA-1' ./scripts/build-macos.sh
```

登录启动验收需要**一个稳定路径的签名 app**。先从菜单退出运行中的副本，确认 `~/Applications/DeskNodes.app` 不会覆盖想保留的版本，再复制并运行：

```sh
mkdir -p "$HOME/Applications"
/usr/bin/ditto build/DeskNodes.app "$HOME/Applications/DeskNodes.app"
/usr/bin/codesign --verify --strict --verbose=2 "$HOME/Applications/DeskNodes.app"
open "$HOME/Applications/DeskNodes.app"
```

同一时间只运行一个副本。之后保持标识符 `local.desknodes.native`、路径、签名身份稳定。先验证拒绝首次询问后不会注册／重问，再在隔离用户中测试明确同意、系统待批准／错误、退出重新登录启动和设置关闭。ad-hoc 被拒绝时记录实际 `SMAppService` 错误与 OS 状态；这是实际阻碍，不添加 LaunchAgent、私有 API 或新权限来绕过。没有本地签名身份不阻止审查源码，但可能阻止登录项验收。打开系统登录项页面只由用户主动操作触发。

## 备份与恢复

首选设置 → 数据 → **导出…** 保存 JSON，保留导出时间和应用版本。导出覆盖所有保留的 notes/items/tombstones、不可变历史、顺延／归档、顺序／自由恢复位置／显示器／层级、设置、快捷键／登录意愿、跨天检查点及待记录删除成员。尚未结束的输入法组词必须先正常完成；导出只刷新实际拥有焦点的已提交编辑，之后在同一事务内取快照。临时五秒撤销计时器、原生文字 undo、窗口焦点、系统登录项注册不是备份状态。

恢复：先导出当前数据；设置 → 导入… 选择原生 v1/schema7 JSON，阅读并明确确认替换全部数据。错误格式、损坏或未来版本、取消确认、组词中或快捷键冲突都应保留原数据和绑定。成功导入会清理旧编辑器／撤销，刷新历史；系统登录项不随 JSON 注册。检查便签、历史、顺延、设置，退出重开；**随后正常定时跨天可能推进导入的旧检查点**，这是正常行为。导入本身不补造历史。不编辑备份文件来转换 Tauri 格式。

需要原始库灾难恢复时，正常完成输入、从菜单退出，并确认进程结束，然后复制整个数据目录（包含 SQLite 可能存在的 journal/WAL/SHM 文件），不能只复制运行中的主 `.sqlite3` 文件：

```sh
backup_root="$HOME/Desktop/DeskNodes-recovery-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_root"
/usr/bin/ditto "$HOME/Library/Application Support/local.desknodes.native" "$backup_root/local.desknodes.native"
```

恢复原始副本也必须在应用完全退出时进行。将当前数据目录改名保留，复制所选**整个离线目录**到 `~/Library/Application Support/local.desknodes.native`，再启动同 schema 的 app。不要混用新主库和旧 WAL/journal。示例中 `backup_root` 仅在当前终端有效，恢复时应使用实际保留的路径。JSON 是正常备份／导入入口；原始目录仅作离线恢复保障。强制终止或断电后的恢复未验收，不能把中断测试称为断电保证。

完整手动验收见 [N10](native-n10.md)。阻碍必须按实际证据记录：SDK 编译诊断、签名失败、登录项拒绝、显示器或输入法不可用都不算通过。无需为执行本项目更改系统时钟、Dock 设置、隐私授权或安装第三方工具。
