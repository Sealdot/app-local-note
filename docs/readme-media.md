# README 截图来源与版本核验

## 本轮起点：此前仅有本地稿

2026-09-28 核对时，`main` 和 `codex/sync-normalization-conflict` 均指向 `e342c66a2465ccd5ef84e1223221fbda48fa8acc`，两者的 `README.md` blob SHA 都是 `ccbd029e11211f00d0ef3edc74a2b31b2c0cdc52`。上一轮重构未提交、未推送，没有对应的新版 commit 或 GitHub 文件链接。本轮基于该本地稿整理，提交目标为 `codex/sync-normalization-conflict`；应用源码、`main`、仓库可见性及 v0.2.0 发布状态不随文档更新改变。

GitHub 首页实际展示根目录 `README.md`；中文入口为 `README.zh-CN.md`。本轮两份 README 都按“用户价值 → 下载与必要状态 → 一张真实界面截图 → 三个收益 → 第一次使用 → 可选 Notion → 开发文档”组织。详细快捷键、月历/外观操作和同步覆盖风险在 [使用指南](user-guide.md)，构建和工程索引在 [开发指南](development.md)。

## 一张真实界面截图

采用 [workday-light.png](assets/readme/workday-light.png)。它来自运行中的生产 `ContentView` / `AppModel`，使用 `NSHostingController` 承载原生视图，通过 AppKit 的 `cacheDisplay` 截取实际界面；不是生成图、重绘 UI 或拼接控件。截图不包含菜单栏和弹窗外框，不宣称它是完整菜单栏现场录屏。

- 应用源码版本：v0.2.0，`e342c66a2465ccd5ef84e1223221fbda48fa8acc`。文档提交与这个应用源码基线是两个不同的版本标识。
- 捕获环境：Apple 芯片、macOS 14.2.1、Swift 5.4 Command Line Tools。
- 视图 440 × 560 point；PNG 880 × 1120 pixel（2×）；README 按 440 px 展示，窄屏缩至容器宽度，可点击原图。
- 固定示例日期：2026-09-28。内容为“准备周会”“整理上周进展”“列出本周优先事项”“跟进反馈”“确认下一步安排”“写下今天的复盘”，完全虚构，不是历史工作成果。
- 脱敏方式：先用隔离的虚构记录替代私人数据，再捕获；没有模糊真实文字、伪造截图内容或覆盖产品控件。Notion 未配置，不包含 Token、页面 ID、真实工作内容或其他应用窗口。
- [截图脚本](../scripts/ReadmePreview.swift)使用临时数据目录、独立 UserDefaults suite、空 SecretStore，关闭网络监视，不读取用户笔记、钥匙串或偏好。正常退出时清理自己的样本。

在仓库根目录复现：

```sh
./scripts/render-readme-media.sh
```

输出为 `build/readme-media/workday-light.png`。工具也验证完成状态切换、保存、切换日期及重新加载后记录内容一致。逐张打开检查后，才复制到 `docs/assets/readme/`。如果进程异常退出，可能留下带 `LocalNoteReadmePreview-*` 或 `dev.sealdot.LocalNote.readme-preview.*` 前缀的临时样本；不要清理用户的数据目录。

此截图验证了真实视图和模型存储路径，不能替代菜单栏点击、Gatekeeper 首次启动或完整键盘操作验收。原生窗口控制服务本轮仍返回启动失败；这不妨碍复现上述真实视图截图。**本轮不要求视频，未录视频不是完成阻塞项。**

### PNG SHA-256

```text
4666e5f429759167b4a5123b6ced1f1ccc643eb034e9e81bd2e96bace84a27b5  docs/assets/readme/workday-light.png
```

## 既有素材的边界

`docs/assets/theme-appearance-p0-option-1.png` 是生成的设计参考；`theme-p0-settings-comparison.png` 含有该参考，都不得作为产品截图。其余 `theme-p0-*` 原生主题图是历史示例状态，本轮不采用。品牌图标也不是产品界面截图。既有素材来源见 [历史设计 QA](../design-qa.md) 和 [图标说明](icon-design.md)。

## 验证记录

- [v0.2.0](https://github.com/Sealdot/app-local-note/releases/tag/v0.2.0) 的 ZIP 与校验文件已实际下载并核验；包内版本 0.2.0、arm64 + x86_64、最低系统声明 11.0、ad-hoc 签名。没有新增或虚构下载链接。
- 上一轮 `package-app.sh`、`test.sh`、`verify.sh` 通过，测试 80/80；性能 smoke 也通过。这是当时本机检查，未作为跨设备兼容或新性能宣传结论。源码本轮没有变化。
- 本轮重新检查截图脚本、文档路径/锚点、图片来源、中文强调语法及 `git diff --check`。具体结果和远端提交在本任务最终反馈中列明。
- 最终检查需要直接打开指定分支的中英文 README，确认七段顺序、图片加载、语言入口以及原图链接。另下载远端图片，与本地 PNG SHA-256 比对。API 渲染或本地预览不能替代此项。

尚未验收的产品条件：真实 Notion 往返需要授权测试页面和令牌；Intel/macOS 11 运行需要对应测试环境。Notion 的“实验性”描述的是验证程度，不是新增 feature flag。开发指南保留这些限制以及未经公证、中文界面、MVP 状态。
