# DeskNodes · 原生 macOS 便签

Swift + AppKit 常驻便签，SwiftUI 设置与只读历史，系统 SQLite 本机存储。macOS 14+，中文界面，菜单栏常驻，无 Dock 图标、无沙盒、无第三方运行时依赖。

支持自由便签与兼容停靠、七色明暗配色、工具条横竖排列与吸边收缩、一键整理、全局收起／展开与置顶、单张折叠、事项排序、删除撤销、最近删除、跨天归档与顺延、边缘唤出及原生 JSON 备份。

完整文档统一放在 [docs 文档总览](docs/README.md)：

- [需求文档](docs/REQUIREMENTS.md)
- [技术文档](docs/TECHNICAL_DESIGN.md)
- [UI 规范](docs/UI_SPEC.md)与[交互原型](docs/UI_PROTOTYPE.html)
- [交互说明](docs/INTERACTIONS.md)
- [验收记录与清单](docs/ACCEPTANCE.md)
- [本机构建、签名、运行与恢复](docs/native-build.md)

文档注明了整理基线；工作区后续实现变更需同步更新文档。自动测试和 HTML 原型不代替签名应用的真实输入、窗口、全屏、多屏与登录项验收，实际验证结果见验收记录。

## 构建与运行

在已安装兼容完整 Xcode 的 Mac 上，从项目根目录执行：

```sh
xcrun swift --version
xcrun swift test
./scripts/build-macos.sh
/usr/bin/codesign --verify --strict --verbose=2 build/DeskNodes.app
open build/DeskNodes.app
```

构建脚本默认采用本地 ad-hoc 签名，不安装证书或修改系统设置。登录启动需要从稳定路径的签名 `.app` 实机验证；详细步骤见构建指南。

## 数据与备份

默认数据库：`~/Library/Application Support/local.desknodes.native/DeskNodes.sqlite3`。设置 → 数据可导出／导入完整原生 JSON，导入前校验并确认替换；与旧 Tauri 备份不兼容，无自动迁移或云同步。格式与可接受版本以 `Sources/DeskNodesPersistence/Backup.swift` 为准。

每次成功跨天后写入同目录 `Backups/`，保留最近 7 份 SQLite 副本。恢复原始数据库必须先退出应用；完整备份和离线恢复操作见构建指南。
