# Local Note

简体中文 · [English](README.md)

Local Note 是一款轻量的 macOS 菜单栏工作记录工具。无需打开浏览器即可记录每天的待办和笔记；数据优先保存在本机，也可以选择与 Notion 页面同步。

它使用 AppKit 和 SwiftUI 原生实现，不依赖 Electron 或第三方运行库。每天的数据分别保存在本机 JSON 文件中，Notion Token 保存在 macOS 钥匙串。同步由打开应用、编辑和手动刷新等事件触发，不进行后台轮询。

> Local Note 是独立的开源项目，与 Notion Labs, Inc. 无关联，也未获得其认可。

## 下载与安装

下载[最新 macOS ZIP](https://github.com/Sealdot/app-local-note/releases/latest/download/LocalNote-macOS.zip)，解压后打开 `LocalNote.app`。通用版本支持搭载 Apple 芯片或 Intel 处理器、运行 macOS 11 或更新版本的 Mac。更新说明和 SHA-256 校验值见 [Releases 页面](https://github.com/Sealdot/app-local-note/releases/latest)。

下载包使用临时签名，**未经 Apple 公证**。首次打开时，macOS 可能要求在“系统设置 → 隐私与安全性”中允许打开。也可以按下文从源代码自行构建。当前应用界面以中文为主；项目文档提供中文和英文版本。

## 从源代码构建

需要 macOS 11 或更新版本，以及 Swift 5.4 或更新版本的命令行工具。无需安装完整 Xcode。

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/package-app.sh
open build/LocalNote.app
```

## 主要功能

- 菜单栏弹窗和大纲编辑，支持待办、编号子项、缩进、撤销与重做。
- 复制、粘贴多行大纲时保留行类型、层级和完成状态。
- 按月查看待办完成情况。
- 四组明暗配色、跟随系统的外观模式和六种强调色。
- 可选的 Notion 同步；本地与远端同时修改时提示冲突，由用户决定保留哪个版本。

设置 Notion 同步时，请创建自己的 Token，只授权给用于 Local Note 的页面。Token 保存在本机钥匙串，不写入每天的记录文件。

项目仍处于自用 MVP 阶段。更多实现细节见 [架构说明](docs/architecture.md)、[测试计划](docs/test-plan.md)和 [性能记录](docs/performance.md)。

## 许可证

[MIT](LICENSE)
