# LibraScan

*[English](README.md)*

iPhone 上的二维码 / 条形码扫描器，配一个把扫到的内容打进 Mac 的伴生应用。

- **LibraScan（iOS）**：扫二维码和条形码，记录存在本机（SwiftData），可导出 TXT。不联网、无账号、无第三方 SDK。
- **LibraScan（macOS，菜单栏）**：通过局域网接收每一次扫码，**模拟键盘**把内容键入当前聚焦的输入框，让 iPhone 变成一把无线扫码枪。行为与 USB 扫码枪的 HID 键盘模式一致：目标软件不需要做任何接入。

```
iPhone (LibraScan)  ──扫码──►  MultipeerConnectivity（加密 P2P，免服务器）
                                      │
                              LibraScan for Mac（菜单栏）
                                      │  CGEvent Unicode 键入
                                      ▼
                          任何聚焦的输入框（Excel / 网页表单 / 终端）
```

两端在同一个 Xcode 工程里，共用一个 bundle ID（`com.Libra.Scan`）。

## 键入桥如何工作

- **配对**：Mac 端广播 `librascan-key` 服务，iPhone 端发现并邀请。首次连接 Mac 会弹窗确认，之后该设备进入信任列表（设置中可管理，也可关闭自动接受）。
- **键入**：`CGEvent` 直写 Unicode，因此中文和 emoji 都能正确键入，与当前键盘布局无关。内容按 20 个 UTF-16 单元分块，且不会把代理对拆开。结尾按键（回车 / Tab / 无）和键入间隔都可配置。
- **可靠性**：每条消息带序号并有回执；重复投递直接回显已记录的结果，不会重复键入。30 秒心跳检测断链。离线期间扫到的码在 iPhone 端排队（最多 50 条），重连后按序补发，此行为可关闭。
- **安全**：会话强制加密。菜单栏的暂停开关即使在一段内容键入到一半时也会立即生效。Mac 端最近键入只在内存里保留 5 条。扫码内容永远先落 iPhone 本地记录——桥是旁路，不是数据的归属地。

协议细节见 [docs/MAC_KEY_BRIDGE.md](docs/MAC_KEY_BRIDGE.md) §5。

## 仓库结构

| 路径 | 内容 |
| --- | --- |
| `LibraScan.xcodeproj` | 两个 target：`LibraScan`（iOS）与 `LibraScanMac`（macOS），产品名都是 LibraScan |
| `LibraScan/` | iOS 源码：`Scan/`（相机、结果横幅、连接面板）、`History/`、`Bridge/BridgeClient.swift` |
| `LibraScanMac/` | macOS 源码：`Bridge/BridgeServer.swift`、`Typing/TypingEngine.swift`、`Updates/`、`UI/` |
| `Shared/` | `BridgeMessage.swift`——线上协议，只此一份，同时编进两个 target |
| `docs/` | [PRD](docs/PRD.md) · [技术设计](docs/TECH_SPEC.md) · [键入桥设计](docs/MAC_KEY_BRIDGE.md) |
| `site/` | [scan.libra.wiki](https://scan.libra.wiki)——纯静态双语单页，无构建步骤 |

## 运行要求

| | iOS | macOS |
| --- | --- | --- |
| 系统 | iOS 18.0+ | macOS 15.0+ |
| 权限 | 相机；使用键入桥时需本地网络 | 辅助功能（模拟键入必需）；本地网络 |
| 工具链 | Xcode 26 | Xcode 26 |

两台设备都需要开启 Wi-Fi 与蓝牙，但不必在同一路由器下——MultipeerConnectivity 会退回到点对点 Wi-Fi。

## 构建

```bash
xcodebuild -project LibraScan.xcodeproj -scheme LibraScan -destination 'generic/platform=iOS' build
```

```bash
xcodebuild -project LibraScan.xcodeproj -scheme LibraScanMac build
```

## 隐私

所有数据只在你的设备和你自己的网络里。扫描记录存在 iPhone 上；键入过的内容只在 Mac 内存里保留最近 5 条，退出即消失。没有服务器、没有统计、没有账号。两端唯一会发起的网络请求，是 Mac 端每天一次向 `scan.libra.wiki` 检查版本——它不发送任何关于你的信息，且可在设置中关闭。
