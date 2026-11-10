# DeskNodes · 原生 macOS 便签

Swift + AppKit 常驻便签，SwiftUI 设置与只读历史，系统 SQLite 本机存储。macOS 14+，中文界面，菜单栏常驻，无 Dock 图标、无沙盒、无第三方依赖。

支持自由便签与顶部／侧边停靠、八色明暗配色、折叠与窗口层级、事项排序、5 秒删除撤销、默认凌晨 04:00 跨天归档与顺延、全屏侧边唤出、可配置新建快捷键、首次询问登录启动和完整原生 JSON 备份。只有唤出面板具有全屏辅助窗口行为。

**这是待 Mac 验收的原生实现，不是已经通过原生验证的应用。** Linux 的 Swift 6.2.1 生产便携测试、静态检查与语法解析不证明 AppKit／SwiftUI／Carbon／ServiceManagement 的 SDK 编译、签名、启动或实际交互成功。完整证据和已知限制见 [N10 审计与 Mac 验收矩阵](docs/native-n10.md)。

在已安装兼容 Xcode 的 Mac 上，从仓库目录执行：

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault
xcrun swift --version
xcrun swift package clean
xcrun swift test
./scripts/build-macos.sh
/usr/bin/codesign --verify --strict --verbose=2 build/DeskNodes.app
open build/DeskNodes.app
```

[本机构建、签名、运行与备份恢复](docs/native-build.md) 包含准确的工具链要求、稳定安装路径、已有本地签名身份用法和恢复步骤。构建脚本默认临时本地签名（ad-hoc），打包原生 ICNS 图标，不安装证书、不修改系统设置。登录项是否接受该签名必须在实际 Mac 验证。不要用裸 `swift run` 代替签名 `.app` 验收。

新建快捷键默认为 **⌃⌥N**。设置中使用 `Control+Option+N` 这样的修饰键与物理 ANSI 字母／数字／Space 组合；冲突保留旧绑定。登录启动只有首次明确同意或设置中的主动操作才会注册；导入的意愿不修改操作系统注册。

数据位于 `~/Library/Application Support/local.desknodes.native/DeskNodes.sqlite3`。设置 → 数据 → 导出… 生成完整原生 JSON；导入… 校验后要求确认替换全部数据。先备份，再导入；输入法组词期间拒绝导入／导出。成功导入会清理旧编辑器与撤销状态，保留导入的历史、归档、布局、设置、跨天检查点及删除记录。格式为 native backup v1 / schema 7，**不兼容旧 Tauri 备份**，没有自动迁移或云同步。

每次跨天成功后会自动把整个数据库复制到同目录的 `Backups/DeskNodes-日期.sqlite3`，保留最近 7 份；恢复时先退出 DeskNodes，再用其中一份替换 `DeskNodes.sqlite3`（并删除同名的 `-wal`／`-shm` 文件）。

删除的便签和事项可在菜单栏 → 最近删除…（或历史记录窗口顶部的「最近删除」）中 30 天内恢复。恢复只清除删除标记，不改写已封存的历史快照；事项恢复到原便签末尾，随便签一起删除的事项随便签恢复。

N10 基于 `5e6443371a6181f63fe30cd41d8c6f023ea8410b`，保留权威 [需求与全部五组原型](docs/spec/macos-native/README.md) 和 [里程碑计划](docs/macos-native-plan.md)。此前 N1–N9 文档是历史记录。当前补丁由 Codex 编写，留给 supervisor 审查、测试及一次提交；未 commit、push 或 merge。可复现 Linux 检查入口：`/workspace/desknotes/logs/native-n10-checks.sh`，日志同目录。
