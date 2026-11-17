# HandwritingFontGen iPadOS App

原生 iPadOS 手写字体采集客户端（SwiftUI + PencilKit），支持 Apple Pencil 压感采集、米字格与半透明参考字叠加，以及直接对接局域网 FastAPI 后端（默认 `http://192.168.31.31/fontgen`）。

---

## 通过 GitHub Actions 自动打包 `.ipa`

1. 将本仓库推送到 GitHub（需包含 `ios-app/` 与 `.github/workflows/build-ipa.yml`）。
2. 打开 GitHub 仓库的 **Actions** 标签页，选择 **Build iPadOS IPA** 工作流。
3. 点击右上角 **Run workflow** 手动触发（或每次修改 `ios-app/**` 后自动触发）。
4. 等待约 2~3 分钟构建完成后，在工作流详情页底部的 **Artifacts** 中下载 `HandwritingFontGen-ipa`（解压后得到 `HandwritingFontGen.ipa`）。

---

## 安装到 iPad（Sideloadly / AltStore）

由于 GitHub Actions 产出的 `.ipa` 为未签名包（`CODE_SIGNING_ALLOWED=NO`），需要使用自签名工具安装到 iPad：

### 方式一：Sideloadly（推荐，支持 Windows / macOS）
1. 在电脑上下载并安装 [Sideloadly](https://sideloadly.io/)。
2. 用数据线将 iPad 连接到电脑，信任此电脑。
3. 打开 Sideloadly，将 `HandwritingFontGen.ipa` 拖入窗口，输入你的 Apple ID（普通免费账号即可）。
4. 点击 **Start**，等待签名并安装完成。
5. 首次打开 App 前，在 iPad 的 **设置 -> 通用 -> VPN 与设备管理** 中信任你的 Apple ID 开发者证书。

### 方式二：AltStore
1. 在电脑和 iPad 上安装 [AltStore](https://altstore.io/)。
2. 将 `HandwritingFontGen.ipa` 发送到 iPad（如隔空投送或文件 App）。
3. 在 iPad 上打开 AltStore -> **My Apps** -> 左上角 `+` -> 选择 `HandwritingFontGen.ipa` 即可自动签名安装。

---

## 使用说明

- **服务器地址**：默认连接 `http://192.168.31.31/fontgen`，可在右侧可折叠设置面板中修改并自动保存。
- **仅 Apple Pencil**：开启后手掌可放心搭在屏幕上防误触；关闭后可用手指书写测试。
- **参考字透明度**：在右侧设置面板滑动调节背景参考字透明度，方便临摹。
