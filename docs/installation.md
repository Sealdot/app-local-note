# Installation / 安装

## Installation

### Requirements

- The v0.2.0 release contains Apple Silicon and Intel binaries and declares macOS 11 as its minimum system version. Intel and macOS 11 runtime validation remains outstanding; see the [verification scope](readme-media.md#精修的验证范围).
- The application interface is primarily Chinese. Local use does not require a Notion account or token.
- This is an early MVP. The download is ad-hoc signed and **not Apple notarized**; macOS may block it on first launch.

### Install and open

1. Download `LocalNote-macOS.zip` from the [v0.2.0 release](https://github.com/Sealdot/app-local-note/releases/tag/v0.2.0). The same page provides its SHA-256 checksum file.
2. Extract the ZIP and open `LocalNote.app`. You can move the app into Applications for future use.
3. If macOS blocks it, proceed only if you trust the source and the file has not been tampered with. After the attempted launch, follow macOS's per-app approval flow in **System Settings → Privacy & Security → Open Anyway**, then confirm **Open**. Names differ on older macOS versions; follow the instructions for your installed system. Keep Gatekeeper enabled. [Apple's first-launch guidance](https://support.apple.com/en-us/102445).
4. Click the checklist icon in the **menu bar**. There is no Dock icon or main document window. Continue with [First use](../README.md#first-use).

If you prefer to build locally, see [Build and run](development.md#build-and-run). A local build does not add Apple notarization.

## 安装

### 安装要求

- v0.2.0 下载包包含 Apple 芯片与 Intel 两种架构，声明的最低系统版本为 macOS 11。Intel 和 macOS 11 实际运行尚未验证，详见[验证范围](readme-media.md#精修的验证范围)。
- 应用界面以中文为主；本地使用无需 Notion 账号或 Token。
- 项目处于早期 MVP 阶段。下载包使用临时签名，**未经 Apple 公证**，macOS 可能阻止首次打开。

### 下载与首次打开

1. 从 [v0.2.0 版本页面](https://github.com/Sealdot/app-local-note/releases/tag/v0.2.0)下载 `LocalNote-macOS.zip`；同页提供 SHA-256 校验文件。
2. 解压并打开 `LocalNote.app`。也可以将应用移到“应用程序”文件夹，方便以后启动。
3. 如果 macOS 阻止打开，只有在确认信任来源且文件未被篡改时才继续。先尝试打开应用，再通过系统“**系统设置 → 隐私与安全性 → 仍要打开**”的单个应用允许流程，并确认打开。旧版 macOS 的菜单名称可能不同，请按当前系统的说明操作。保留 Gatekeeper。[Apple 首次打开说明](https://support.apple.com/zh-cn/102445)。
4. 点击 **菜单栏**的清单图标；应用没有 Dock 图标或文档主窗口。接着按[第一次使用](../README.zh-CN.md#第一次使用)创建本地记录。

如需在本机编译，见[构建与运行](development.md#build-and-run)；本机构建不会增加 Apple 公证。
