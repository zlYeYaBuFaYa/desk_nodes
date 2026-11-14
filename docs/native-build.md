# 本机构建、运行与恢复

这里只维护操作步骤。环境与工程机制见 [技术设计](TECHNICAL_DESIGN.md#architecture)，应用行为见 [功能与交互](REQUIREMENTS.md)，验证结果见 [验收](ACCEPTANCE.md)。

<a id="build"></a>
## 构建与验证

在安装了完整兼容 Xcode 的 Mac 上，从仓库根目录执行。DEVELOPER_DIR 只影响当前终端，无需修改系统选择：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault
xcodebuild -version
xcrun swift --version
xcrun --sdk macosx --show-sdk-path
xcrun swift test
./scripts/build-macos.sh
/usr/bin/plutil -lint build/DeskNodes.app/Contents/Info.plist
/usr/bin/codesign --verify --strict --verbose=2 build/DeskNodes.app
open build/DeskNodes.app
```

[构建脚本](../scripts/build-macos.sh) 生成当前主机架构的 release，打包二进制、Info.plist、图标与便签字体霞鹜文楷（首次构建由 [fetch-fonts.sh](../scripts/fetch-fonts.sh) 按固定版本下载到不入库的 `Resources/Fonts/` 并校验 SHA-256，之后离线可用），默认 ad-hoc 签名并验证后替换仓库 build/DeskNodes.app。不会安装应用、证书或执行公证。需要其他签名身份时使用已有身份：

```sh
/usr/bin/security find-identity -v -p codesigning
DESKNODES_SIGNING_IDENTITY='已有身份名称或 SHA-1' ./scripts/build-macos.sh
```

自动检查还包括 `python3 scripts/check-n1.py`、`check-n7.py`、`check-n8.py`、`check-n9.py`、`check-n10.py`，它们只核对静态契约，不替代 Swift 编译与原生操作。

如果受限环境阻止默认缓存写入，可将缓存放到可写临时目录重试，不修改用户工具链配置：

```sh
CLANG_MODULE_CACHE_PATH=/tmp/desknodes-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/desknodes-swift-cache \
xcrun swift test --disable-sandbox --cache-path /tmp/desknodes-spm-cache
```

工具链须满足其自身主机要求；不承诺任意 Xcode 都能运行于应用的最低系统版本。记录实际命令、退出码和各 XCTest 目标结果；额外 runner 的“0 tests”不覆盖 XCTest 结果。

<a id="installation"></a>
## 稳定安装与登录项

登录项需在稳定路径的签名应用上实测。先退出运行副本，确认目标不是要保留的旧安装，再执行：

```sh
mkdir -p "$HOME/Applications"
/usr/bin/ditto build/DeskNodes.app "$HOME/Applications/DeskNodes.app"
/usr/bin/codesign --verify --strict --verbose=2 "$HOME/Applications/DeskNodes.app"
open "$HOME/Applications/DeskNodes.app"
```

同一时间只运行一个副本，保持路径、Bundle ID 与签名身份稳定。登录项操作与状态判定见 [FR-12](REQUIREMENTS.md#fr-12)；ad-hoc 被系统拒绝时记录实际错误，不以其他启动服务绕过。

<a id="isolation"></a>
## 隔离运行

手动验收或截图使用临时数据目录启动二进制，例如：

```sh
DESKNODES_DATA_DIR=/tmp/desknodes-verification build/DeskNodes.app/Contents/MacOS/DeskNodes
```

隔离库与偏好域的机制见 [存储](TECHNICAL_DESIGN.md#storage) 和 [展示偏好](TECHNICAL_DESIGN.md#presentation)。验证域在不同临时目录间共用；该变量不隔离系统登录项。不要并行启动验证副本与个人副本来测试全局快捷键。

<a id="recovery"></a>
## 备份与恢复

### JSON

优先在设置 → 数据 → 导出… 保存备份，并标记导出时间和应用版本。恢复前先导出当前数据，再在同处导入… 选择原生 JSON，阅读并确认替换提示。恢复后检查便签、历史和布局，退出重开复核。兼容版本与载荷归属只见 [备份协议](TECHNICAL_DESIGN.md#backup)，失败与替换行为只见 [FR-13](REQUIREMENTS.md#fr-13)。

### SQLite 离线副本

正常完成输入、从菜单退出并确认进程结束后，复制整个生产数据目录。位置见 [存储](TECHNICAL_DESIGN.md#storage)；示例：

```sh
backup_root="$HOME/Desktop/DeskNodes-recovery-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup_root"
/usr/bin/ditto "$HOME/Library/Application Support/local.desknodes.native" "$backup_root/local.desknodes.native"
```

恢复时同样先退出应用：将当前目录改名保留，再把所选整个离线目录复制回原位置，使用支持该 schema 的应用启动。不要只复制运行中的主库，也不要混用不同副本的 WAL／SHM／journal。

[自动 SQLite 副本](TECHNICAL_DESIGN.md#automatic-backup) 可在退出后用于恢复；保留当前目录，把所选完整副本作为 DeskNodes.sqlite3 放入新的数据目录，不带入旧库的侧文件。强制终止和断电恢复仍需独立验收，不能由正常导入或中断单元测试推断通过。
