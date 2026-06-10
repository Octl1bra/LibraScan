# ScanKeyboard

macOS 菜单栏 App：把 iPhone 上 [LibraScan](https://github.com/Octl1bra/LibraScan) 扫到的码，
通过局域网（MultipeerConnectivity）实时**模拟键盘键入**到 Mac 当前聚焦的输入框——
让 iPhone 变成 Mac 的无线扫码枪。

设计文档见 LibraScan 仓库的 `docs/MAC_KEY_BRIDGE.md`。

## 工作原理

```
iPhone (LibraScan)  ──扫码──►  MultipeerConnectivity（加密 P2P，免服务器）
                                      │
                              ScanKeyboard（菜单栏）
                                      │  CGEvent Unicode 键入
                                      ▼
                          Mac 上任何聚焦的输入框（Excel / 网页 / 终端…）
```

- **连接**：Mac 端广播 `librascan-key` 服务，iPhone 端发现并邀请；首次连接 Mac 弹窗确认，
  之后进入信任列表（设置中可管理 / 关闭自动接受）。
- **键入**：CGEvent 直写 Unicode（中文 / emoji 均可，与键盘布局无关），按 20 个 UTF-16
  单元分块；可配置结尾后缀（回车 / Tab / 无）与键入间隔。
- **可靠性**：消息带 seq 去重（断线补发不会重复键入），每条回 ack 给 iPhone。
- **安全**：传输强制加密；菜单栏有「暂停键入」急停开关；最近键入仅存内存。

## 运行要求

- macOS 15.0+
- **辅助功能权限**（系统设置 → 隐私与安全性 → 辅助功能）：模拟键入必需，首次使用会引导授权
- 本地网络权限：首次启动系统会弹窗询问
- iPhone 与 Mac 同时开启 Wi-Fi 与蓝牙（无需在同一路由器下，支持 AWDL 点对点）

## 构建

```bash
xcodebuild -project ScanKeyboard.xcodeproj -scheme ScanKeyboard -configuration Debug build
```

注意：本 App 不可上架 Mac App Store（模拟键盘事件与 App Sandbox 不兼容），
分发需走 Developer ID 签名 + 公证。

## 配套 iOS 端

iPhone 侧的连接与发送逻辑（BridgeClient）在 LibraScan 仓库中实现，
协议层 `BridgeMessage.swift` 两端各持一份，需保持同步。
