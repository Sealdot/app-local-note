# Local Note

简体中文 · [English](README.md)

**给想随手记录当天工作、勾选完成并按日期回看的 Mac 用户：Local Note 把工作日志放进菜单栏，记录优先保存在本机。**

## 下载与项目状态

下载 [v0.2.0 macOS ZIP](https://github.com/Sealdot/app-local-note/releases/download/v0.2.0/LocalNote-macOS.zip)，解压并打开 `LocalNote.app`。[版本说明与 SHA-256 校验文件](https://github.com/Sealdot/app-local-note/releases/tag/v0.2.0)。

下载包包含 Apple 芯片与 Intel 两种架构，**最低构建目标为 macOS 11**。本次在 Apple 芯片、macOS 14.2.1 上检查；Intel/macOS 11 的运行验证仍待完成。**应用界面目前以中文为主。**

> **项目处于自用 MVP 阶段；下载包使用临时签名，未经 Apple 公证。** macOS 可能阻止首次打开。确认信任下载来源后，通过系统“隐私与安全性”的允许打开流程处理，并保留 Gatekeeper。也可以[从源码构建](docs/development.md#build-and-run)。

## 看一个工作日

<a href="docs/assets/readme/workday-light.png"><img src="docs/assets/readme/workday-light.png" alt="Local Note 当天大纲：已完成的周会任务、编号步骤和两项未完成待办；内容均为虚构示例" width="440"></a>

*真实原生应用视图截图，来自 v0.2.0 代码；以虚构任务替代私人工作记录。截图不包含菜单栏和弹窗外框。点击查看原图。[截图来源与版本说明](docs/readme-media.md)。*

## 三个核心收益

- **随手记下，不打断工作。** 从菜单栏打开当天清单，离线也能编辑。
- **把待办拆成可执行步骤。** 勾选任务、添加编号子项；复制粘贴多行大纲时保留层级和完成状态。
- **回看自己做过什么。** 在月历选择日期，回到那天的记录。颜色反映已完成复选框的数量，不代表生产力评分。

## 第一次使用

1. 打开 `LocalNote.app`，点击 **macOS 菜单栏**的清单图标；应用没有 Dock 图标或文档主窗口。
2. 点击 **+**，输入“准备周会”，按 Return 添加下一项。无需配置 Notion 或 Token。
3. 勾选第一项，点击日历按钮，再选今天的日期回到清单。

**你应该看到：** 关闭再打开弹窗，今天的文字和勾选状态仍在。未配置 Notion 时，底部可能显示“未配置 Notion”或“仅本地”，本地记录仍会保存。[快捷键、月历与外观设置](docs/user-guide.md)。

**本地隐私：** 记录和同步快照以未加密的 JSON 保存在 `~/Library/Application Support/LocalNote/`。请自行备份；应用没有内置备份流程。外观设置只留在当前 Mac。当前源码没有统计分析或遥测客户端。[安全政策](SECURITY.md)。

## 可选 Notion 同步

Notion 同步已有实现，属于**可选的实验性集成**；本次 README 核验未连接真实 Notion 页面。请先使用专门的测试页面并另行备份。在设置中填写自己的页面 ID/URL 和集成 Token；Token 存入 macOS 钥匙串，启用同步后会向 Notion 传输页面内容。

同步由事件触发，远端修改需手动刷新或重新打开弹窗。两边都修改时，要选择保留哪一方当天内容，不会自动合并。API 写入会替换整页 Markdown，无法通过事务合并保护其他日期的并发修改。[配置、冲突选择与覆盖风险说明](docs/user-guide.md#optional-notion-sync)。

Local Note 是独立开源项目，与 Notion Labs, Inc. 无关联，也未获得其认可。

## 开发文档

从[构建与验证指南](docs/development.md)和[贡献约定](CONTRIBUTING.md)开始。可复现的问题和功能讨论请提交到 [Issues](https://github.com/Sealdot/app-local-note/issues)；凭据泄露或数据丢失漏洞请按 [SECURITY.md](SECURITY.md) 私下报告。

[架构](docs/architecture.md) · [测试计划](docs/test-plan.md) · [历史性能测量](docs/performance.md) · [里程碑与延后项](docs/implementation-plan.md) · [MIT 许可证](LICENSE)

公共 OAuth、Webhook 更新、协作合并、附件与富文本行内内容、Apple 公证分发仍在延后清单中，没有承诺交付日期。
