# LibraScan

iPhone 扫码器 + Mac 键入桥，一个仓库、一个 Xcode 工程、一个 bundle ID（`com.Libra.Scan`）。

- **LibraScan（iOS）**：二维码 / 条形码扫描，记录本地保存（SwiftData），可导出 TXT。不联网、无账号、无第三方 SDK。
- **LibraScan（macOS，菜单栏）**：把 iPhone 扫到的内容通过局域网实时**模拟键盘键入**到 Mac 当前聚焦的输入框——iPhone 变成 Mac 的无线扫码枪，行为与 USB 扫码枪的 HID 键盘模式一致。

```
iPhone (LibraScan)  ──扫码──►  MultipeerConnectivity（加密 P2P，免服务器）
                                      │
                              LibraScan for Mac（菜单栏）
                                      │  CGEvent Unicode 键入
                                      ▼
                          Mac 上任何聚焦的输入框（Excel / 网页 / 终端…）
```

## 仓库结构

| 路径 | 内容 |
| --- | --- |
| `LibraScan.xcodeproj` | 两个 target：`LibraScan`（iOS）、`LibraScanMac`（macOS），产品名都是 LibraScan |
| `LibraScan/` | iOS 源码：`Scan/`（相机 + 横幅 + 连接面板）、`History/`、`Bridge/BridgeClient.swift` |
| `LibraScanMac/` | macOS 源码：`Bridge/BridgeServer.swift`、`Typing/TypingEngine.swift`、`UI/` |
| `Shared/` | `BridgeMessage.swift`——两端共用的线上协议，只此一份 |
| `docs/` | [PRD](docs/PRD.md) · [技术设计](docs/TECH_SPEC.md) · [Mac 键入桥设计](docs/MAC_KEY_BRIDGE.md) |
| `site/` | 官网 [scan.libra.wiki](https://scan.libra.wiki)：纯静态 HTML/CSS，中英双语，部署在 Cloudflare Pages（`site/deploy.sh`）。含隐私政策与支持页，即 App Store 所需的两个 URL |

版本号（`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`）定义在工程级，两端共用；发版时只改一处。

## 运行要求

| | iOS | macOS |
| --- | --- | --- |
| 系统 | iOS 18.0+ | macOS 15.0+ |
| 权限 | 相机；使用键入桥时需本地网络 | 辅助功能（模拟键入必需，首次引导授权）；本地网络 |
| 构建 | Xcode 26 | Xcode 26 |

iPhone 与 Mac 同时开启 Wi-Fi 与蓝牙即可，无需在同一路由器下（支持 AWDL 点对点）。

## 构建

```bash
xcodebuild -project LibraScan.xcodeproj -scheme LibraScan -destination 'generic/platform=iOS' build
```

```bash
xcodebuild -project LibraScan.xcodeproj -scheme LibraScanMac build
```

## 键入桥如何工作

- **连接**：Mac 端广播 `librascan-key` 服务，iPhone 端发现并邀请；首次连接 Mac 弹窗确认，之后进入信任列表（设置中可管理 / 关闭自动接受）。
- **键入**：CGEvent 直写 Unicode（中文 / emoji 均可，与键盘布局无关），按 20 个 UTF-16 单元分块；可配置结尾后缀（回车 / Tab / 无）与键入间隔。
- **可靠性**：消息带 seq 去重，每条回 ack；30s 心跳，离线时 iPhone 端排队最多 50 条，重连后按序补发（可关）。
- **安全**：传输强制加密；菜单栏有「暂停键入」急停开关；最近键入仅存内存；扫描记录永远先落本地，桥是旁路。

协议细节见 [docs/MAC_KEY_BRIDGE.md](docs/MAC_KEY_BRIDGE.md) §5。

## 分发

| | 渠道 | 说明 |
| --- | --- | --- |
| iOS | App Store / TestFlight | 已关闭「在 Apple 芯片 Mac 上提供」，Mac 上只有原生版 |
| macOS | Developer ID 签名 + 公证的 dmg | 不上 Mac App Store：不是沙箱限制，是 App Review 对合成键入的审核不稳定，见设计文档 §6.3 |

两端 bundle ID 一致，将来若要上 Mac App Store 可直接并入同一条 App Store Connect 记录（Universal Purchase）。

### 出包

两端都用 Xcode 自动签名，凭据来自登录 Xcode 的开发者账号：

```bash
# iOS → App Store Connect（TestFlight）
xcodebuild archive -project LibraScan.xcodeproj -scheme LibraScan -destination 'generic/platform=iOS' -archivePath build/LibraScan-iOS.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/LibraScan-iOS.xcarchive -exportOptionsPlist <(printf '<plist version="1.0"><dict><key>method</key><string>app-store-connect</string><key>signingStyle</key><string>automatic</string><key>teamID</key><string>6NK6HJKB8Z</string><key>destination</key><string>upload</string></dict></plist>') -exportPath build/ios-upload -allowProvisioningUpdates
```

```bash
# macOS → 公证（通过 Xcode 账号提交）→ 取回已 staple 的 app → dmg
xcodebuild archive -project LibraScan.xcodeproj -scheme LibraScanMac -archivePath build/LibraScanMac.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/LibraScanMac.xcarchive -exportOptionsPlist <(printf '<plist version="1.0"><dict><key>method</key><string>developer-id</string><key>signingStyle</key><string>automatic</string><key>teamID</key><string>6NK6HJKB8Z</string><key>destination</key><string>upload</string></dict></plist>') -exportPath build/mac-upload -allowProvisioningUpdates
xcodebuild -exportNotarizedApp -archivePath build/LibraScanMac.xcarchive -exportPath build/mac-notarized   # 公证未完成时会报错，稍后重试
create-dmg --volname LibraScan --app-drop-link 400 190 --icon LibraScan.app 140 190 --skip-jenkins build/LibraScan-1.0.dmg build/mac-notarized
```

dmg 本身不签名、不公证：Xcode 自动创建的 Developer ID / Apple Distribution 证书是**云托管**的，私钥不在本机钥匙串，`xcodebuild -exportArchive` 能签而本地 `codesign` 找不到身份。Gatekeeper 校验的是 dmg 里的 app（已 staple，`spctl` 给出 `Notarized Developer ID`），这已足够。若以后要给 dmg 签名公证，需在开发者后台用 CSR 手动建一张非托管的 Developer ID Application 证书，并为 `notarytool` 配 App Store Connect API key。

Mac 端脱离商店没有自动更新；协议带版本号（`BridgeMessage.v`），不匹配时回 `unsupported`，不会乱键入。

## 隐私

所有数据只在设备本地和你自己的局域网里：扫描记录存在 iPhone 上，键入内容仅在 Mac 内存里保留最近 5 条；没有服务器、没有统计、没有账号。
