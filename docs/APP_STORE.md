# LibraScan — App Store 文案（iOS 1.0）

> 参考 Things 3 的商店页：短段落、小标题、不喊口号。事实核对自代码与 Info.plist（2026-08-22）。

| 字段 | 填写 |
| --- | --- |
| Name | `LibraScan` |
| Category | Utilities（次选 Productivity） |
| Age Rating | 全 None → 4+ |
| Copyright | `2026 Jinrui Hu` |
| Support / Marketing / Privacy URL | `https://scan.libra.wiki/support/` · `https://scan.libra.wiki/` · `https://scan.libra.wiki/privacy/` |
| App Privacy | 第一题答 No → Data Not Collected |
| Sign-in | 不需要，无演示账号 |

## English

**Subtitle (≤30)**

```text
Offline QR & Barcode Scanner
```

**Promotional Text (≤170)**

```text
Scan QR codes and barcodes — nothing leaves your phone. Add the free Mac app and every scan is typed into the focused text field, like a wireless barcode scanner.
```

**Description (≤4000)**

```text
LibraScan scans QR codes and barcodes and keeps the history on your iPhone. It never connects to the internet.

Add the free Mac app, and every scan is typed straight into whatever text field has focus on your Mac — a spreadsheet, a web form, a terminal. Like a wireless barcode scanner.

SCAN
QR, Data Matrix, Aztec, PDF417, EAN, UPC, Code 39/93/128, ITF-14, Codabar. Results show in a banner while the camera keeps running. Pinch to zoom, torch for dark places.

HISTORY
Every scan is saved with its type and time. Search, swipe to delete, export everything as TXT.

TYPE TO MAC
Get LibraScan for Mac at scan.libra.wiki. Tap “Type to Mac”, pick your Mac, click Allow. Scans appear at the cursor, optionally followed by Return or Tab. Works with CJK text and emoji.

PRIVACY
No account, no server, no analytics, no third-party SDK. Camera frames never leave the device. The iPhone-to-Mac link is an encrypted peer-to-peer connection built on Apple’s MultipeerConnectivity framework; nothing sits in between.

Requires iOS 18. Type to Mac needs macOS 15, with Wi-Fi and Bluetooth on for both devices. Scanning and history work without a Mac.
```

**Keywords (≤100)**

```text
code,reader,scan,ean,upc,isbn,sku,inventory,wireless,keyboard,mac,excel,private,history,export,bar
```

## 简体中文

**副标题 (≤30)**

```text
不联网的二维码 / 条形码扫描器
```

**推广文本 (≤170)**

```text
扫二维码、条形码，数据不出手机。装上免费的 Mac 端，iPhone 扫到什么就实时键入 Mac 当前聚焦的输入框——Excel、网页表单、终端都行，像一把无线扫码枪。
```

**描述 (≤4000)**

```text
LibraScan 扫二维码和条形码，记录存在 iPhone 本地，从不联网。

装上免费的 Mac 端，iPhone 扫到什么，就实时键入 Mac 当前聚焦的输入框——Excel、网页表单、终端都行。像一把无线扫码枪。

扫描
QR、Data Matrix、Aztec、PDF417、EAN、UPC、Code 39/93/128、ITF-14、Codabar。结果以横幅显示，相机不停，连续扫。支持捏合变焦和手电筒。

记录
每次识别自动保存，带码制和时间。可搜索、左滑删除、一键导出 TXT。

键入到 Mac
在 scan.libra.wiki 下载 LibraScan for Mac。点「键入到 Mac」，选中你的 Mac，点「允许」。内容出现在光标处，可自动补回车或 Tab。中文、emoji 照样键入。

隐私
没有账号、没有服务器、没有统计、没有第三方 SDK。相机画面不出设备。iPhone 到 Mac 的连接是基于 Apple MultipeerConnectivity 框架的加密点对点连接，中间没有任何东西。

需要 iOS 18。键入到 Mac 需要 macOS 15，两台设备开启 Wi-Fi 与蓝牙。扫描与记录不需要 Mac。
```

**关键词 (≤100)**

```text
扫码,扫一扫,条码,扫描,扫码枪,无线,键盘,电脑,录入,盘点,库存,离线,隐私,本地,记录,导出,商品,快递,链接,识别,工具,仓库,序列号,批量,ISBN,Mac,Excel
```

## App Review Notes（英文，粘进 App Review Information → Notes）

**Notes (≤4000)**

```text
LibraScan is a QR/barcode scanner with on-device history. No account, no sign-in, no server, no analytics, no third-party SDK. No demo account is needed.

NETWORK: The app makes no internet connections. Its only network feature is the optional “Type to Mac”, built entirely on Apple’s MultipeerConnectivity framework (MCNearbyServiceBrowser + MCSession, encryptionPreference = .required): the iPhone connects directly to the user’s own Mac over peer-to-peer Wi-Fi / the local network, with no server or relay. This is the reason for NSLocalNetworkUsageDescription and NSBonjourServices (_librascan-key._tcp/_udp); the Local Network prompt appears only when the user opens “Type to Mac”. Only Apple’s built-in encryption is used (ITSAppUsesNonExemptEncryption = NO).

PERMISSIONS: Camera (frames are processed on device, never stored or uploaded) and Local Network (Type to Mac only).

TESTING WITHOUT A MAC: Scanning, history, search and TXT export are fully functional on their own. Opening “Type to Mac” with no Mac nearby shows an empty list with a hint — expected behaviour, not a bug.

TESTING TYPE TO MAC (optional): Install the free, Developer ID–signed and notarized Mac app from https://scan.libra.wiki/download/LibraScan-1.0.dmg on macOS 15 or later, grant Accessibility when prompted, and keep Wi-Fi and Bluetooth on for both devices. On the iPhone, tap the keyboard icon, choose the Mac, and click Allow on the Mac. Put the cursor in TextEdit and scan any code; the text is typed at the cursor.

REGIONS: The app functions identically in all regions; there are no regional differences in features or content.

Privacy policy: https://scan.libra.wiki/privacy/
Support: https://scan.libra.wiki/support/
Contact: me@libra.wiki
```
