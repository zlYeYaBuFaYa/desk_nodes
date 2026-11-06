# DeskNodes 设计资料包

## 目录

- 01-需求文档/DeskNodes 需求文档.md：完整需求文档（功能、视觉规范、技术方案、版本规划与验收标准）
- 02-原型设计/design-tokens.json：配色、字体、圆角、投影、动效等设计参数，开发时可直接转为 CSS 变量
- 02-原型设计/source/：界面原型源文件
  - Main.dc.html：桌面交互原型（便签、托盘菜单、勾选/添加/删除/撤销、换色、置顶、深色模式）
  - Palette.dc.html：8 色配色，浅色与深色
  - History.dc.html：管理面板历史页（月历完成率 + 日详情）
  - canvas.json：画布布局

## 说明

原型源文件是 Claude 设计画布格式，依赖画布运行时，不能直接用浏览器打开。
在线查看与操作：https://claude.ai/artifact/5LAyTipTVwWGs7eRwMJFj1
在线需求文档：https://claude.ai/artifact/5qMPeV9tcRj1nEgoTyN9pV

## 交给 Claude Code 开发时

把整个文件夹放进项目目录，告诉它：以需求文档为准、视觉参数取自 design-tokens.json、交互细节参考 source/Main.dc.html，从 V0.1 的技术原型与内存实测开始。
