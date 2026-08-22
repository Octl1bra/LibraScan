# LibraScan Mac 键入桥（Keyboard Bridge）设计文档

| 项目 | 内容 |
| --- | --- |
| 功能名称 | LibraScan Key（Mac 键入桥） |
| 形态 | iOS 端扩展 + macOS 菜单栏 App |
| 传输 | MultipeerConnectivity（局域网点对点，免服务器） |
| 文档日期 | 2026-06-10 |
| 状态 | 双端已实现，同仓库：Mac 端 `LibraScanMac/`，iOS 端 `LibraScan/Bridge/`，协议 `Shared/BridgeMessage.swift`（两端共用一份） |

## 1. 概述与场景

把 iPhone + LibraScan 变成 Mac 的「无线扫码枪」：iPhone 扫到的内容通过
MultipeerConnectivity 实时发给 Mac 上的伴生 App，由它模拟键盘把内容**键入到
Mac 当前聚焦的任意输入框**——行为与 USB 扫码枪（HID 键盘模式）一致，
对目标软件零侵入，Excel / 网页表单 / ERP / 终端都能直接用。

**典型场景**

- 仓库盘点：Mac 开着 Excel / WMS 网页，iPhone 连续扫条码，内容逐行打进表格。
- 序列号录入：扫设备 SN 直接进表单字段，避免手抄出错。
- 跨设备传输：扫到的 URL / 文本即时出现在 Mac 光标处。

**核心原则**：纯局域网点对点（AWDL / 同网段 Wi-Fi），不经任何服务器；
连接需 Mac 端确认；传输全程加密。

## 2. 体验流程

```
   iPhone（LibraScan）                    Mac（LibraScan Key，菜单栏）
┌────────────────────────┐            ┌────────────────────────────┐
│ 扫一扫页新增「键入到 Mac」 │  ① 浏览发现  │  常驻菜单栏，广播服务          │
│ 入口（键盘图标）          │ ─────────► │                            │
│                        │  ② 邀请连接  │  首次连接弹确认框             │
│ 选择列表里的 Mac         │ ─────────► │  「允许 'Libra 的 iPhone'    │
│                        │            │    连接并键入文本？」          │
│ 已连接 ✓（图标变蓝）      │ ◄────────► │  菜单栏图标变为已连接          │
│                        │  ③ 扫码推送  │                            │
│ 扫码 → 本地落库 + 发送    │ ─────────► │  模拟键盘输入到聚焦输入框       │
│ 横幅显示「已键入 Mac」     │  ④ 回执 ack │  （可选自动补 ⏎ / ⇥ 后缀）    │
└────────────────────────┘            └────────────────────────────┘
```

## 3. 总体架构

```
┌─ iOS: LibraScan ────────────────┐   ┌─ macOS: LibraScan Key ──────────┐
│ ScannerController（既有）         │   │ MenuBarExtra（SwiftUI）          │
│        │ ScanPayload            │   │   ├── 连接状态 / 最近键入          │
│        ▼                        │   │   └── 设置（后缀、键入方式、信任表）│
│ BridgeClient                    │   │ BridgeServer                     │
│   MCNearbyServiceBrowser        │   │   MCNearbyServiceAdvertiser      │
│   MCSession ◄═══ 加密 P2P ═══════════► MCSession                       │
│        ▲                        │   │        │ ScanMessage             │
│ 共享协议层 BridgeProtocol/        │   │        ▼                        │
│   ScanMessage.swift（两端共用）    │   │ TypingEngine（CGEvent 模拟键入） │
└─────────────────────────────────┘   └─────────────────────────────────┘
```

两端放在同一个 Xcode 工程里：新增 macOS target `LibraScanKey`，
协议层放 `Shared/Bridge/`（两个 target 同时勾选 / 同步文件夹引用），
消息结构只写一份。

## 4. 连接层：MultipeerConnectivity 设计

### 4.1 角色分配

| 端 | 角色 | 理由 |
| --- | --- | --- |
| Mac | `MCNearbyServiceAdvertiser`（被发现方） | Mac 常驻、是被连接的「外设宿主」；确认弹窗天然落在 Mac 上 |
| iPhone | `MCNearbyServiceBrowser`（发现方） | 用户在手机上从列表选择目标 Mac，符合「拿枪找电脑」的心智 |

- 服务类型：`librascan-key`（≤15 字符、小写+连字符，符合 Bonjour 规范）。
- `MCSession(peer:securityIdentity:encryptionPreference: .required)`——强制加密。
- 一个会话只服务一台 iPhone ↔ 一台 Mac（`maximumNumberOfPeers` 按 2 处理）；
  多台 Mac 同时在线时由用户在 iPhone 列表中选择。

### 4.2 配对与信任

1. iPhone 浏览到 Mac → 用户点击 → `invitePeer`（携带 iPhone 设备名 + 随机配对码摘要）。
2. Mac 首次收到邀请 → 弹确认框（显示设备名）→ 接受后将 peer 标识存入「信任列表」
   （`UserDefaults`，含 displayName + 首次配对时间）。
3. 已信任设备重连可配置为自动接受（默认开，可在设置中关闭回到每次确认）。
4. Mac 菜单栏可随时「断开 / 移除信任」。

### 4.3 系统权限配置（两端都不能漏）

| 端 | 配置 | 说明 |
| --- | --- | --- |
| iOS Info.plist | `NSLocalNetworkUsageDescription` | 本地网络权限文案 |
| iOS Info.plist | `NSBonjourServices` = `_librascan-key._tcp` + `_librascan-key._udp` | 不配 browser 静默失败，这是最常见的坑 |
| macOS Info.plist | `NSLocalNetworkUsageDescription` | macOS 15+ 同样有本地网络隐私弹窗 |
| macOS entitlements | `com.apple.security.network.client` + `network.server` | 若保留沙箱则必须；见 6.3 分发说明 |
| macOS TCC | 辅助功能（Accessibility） | 模拟键入必需，见 5.3 |

### 4.4 生命周期与重连

- iOS 端 MC 不支持后台保活：App 退后台 → 会话断开是**预期行为**；
  回前台后 BridgeClient 自动重新 browse 并重连上次的 Mac（保存 peer displayName）。
- 心跳：30s 一次 `ping` 消息，双向；连续 2 次无响应视为断开并更新两端 UI。
- 断线期间扫码：照常本地落库，同时进入**待发队列**（内存，上限 50 条）；
  重连成功后按序补发（用户可在 iOS 端关闭补发，默认开）。

## 5. 消息协议与 Mac 键入引擎

### 5.1 消息协议（JSON，版本化信封）

```jsonc
// iPhone → Mac：扫码内容
{ "v": 1, "type": "scan",
  "seq": 42,                       // 单调递增，Mac 端去重
  "content": "6901234567892",
  "symbology": "EAN-13",
  "scannedAt": "2026-06-10T22:58:41Z" }

// Mac → iPhone：键入回执（横幅据此显示「已键入 Mac」）
{ "v": 1, "type": "ack", "seq": 42, "typed": true }

// 双向心跳
{ "v": 1, "type": "ping" }   { "v": 1, "type": "pong" }
```

- 发送用 `MCSession.send(_:toPeers:with: .reliable)`。
- `seq` 由 iOS 端维护；Mac 记录最近 64 个已处理 seq，重复直接 ack 不重打——
  防补发与重连造成的重复键入。
- 未知 `type` / 更高版本号：回 `{"type":"unsupported"}`，**并回显被拒消息的 `seq`**（若有），
  让发送方能把那一条结算掉，而不是留在待确认队列里一直显示「发送中」。
  收到 `unsupported` 的一方据此判定「对端版本更旧」，收到高版本消息的一方判定「自己更旧」，
  两端各自在 UI 上说明是哪边需要更新（iOS 连接面板 / Mac 菜单栏）。

### 5.2 TypingEngine：模拟键入（核心）

**主方案：CGEvent + Unicode 直写**

```swift
let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
down?.keyboardSetUnicodeString(stringLength:unicodeString:)   // 直接携带字符
down?.post(tap: .cghidEventTap)
// 对应 keyUp 成对发送
```

- 不查键位映射，天然支持中文 / emoji / 任意 Unicode，与物理键盘布局无关。
- 每个事件最多携带 **20 个 UTF-16 code unit**，超长内容按 20 单元分块循环发送；
  事件间隔 2–5ms（可配置「键入速度」），兼顾可靠性与速度。
- 可选**结束后缀**：无 / 回车（`kVK_Return` 36）/ Tab（`kVK_Tab` 48），
  默认回车——对齐扫码枪习惯，连续扫码自动换行/跳格。

**备选方案：剪贴板 + ⌘V（设置项「键入方式：粘贴」）**

- 超长文本（如 vCard、千字符 QR）逐字键入太慢时更实用。
- 实现：暂存用户剪贴板 → 写入内容 → 合成 ⌘V → 300ms 后恢复原剪贴板。
- 默认关闭：会触碰用户剪贴板，且部分 App 屏蔽程序化粘贴。

**已知边界**：目标输入框若有输入法处于拼写组合态，注入的 Unicode 事件可能被
IME 截断——文档化为已知限制，建议录入场景切英文输入法（扫码枪同样有此问题）。

### 5.3 macOS 权限引导

- 模拟键入需要**辅助功能**授权（TCC Accessibility）。
- 首启检测 `AXIsProcessTrusted()`，未授权则引导页 +
  `AXIsProcessTrustedWithOptions(kAXTrustedCheckOptionPrompt)` 触发系统弹窗，
  并提供深链 `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`。
- 未授权期间收到 scan 消息：不键入，ack 带 `"typed": false, "reason": "no-permission"`，
  iPhone 横幅提示「Mac 未授权键入」。

## 6. macOS App 形态

### 6.1 UI：菜单栏常驻（MenuBarExtra）

- 图标三态：灰（待连接）/ 蓝（已连接）/ 闪烁（正在键入）。
- 下拉内容：连接状态与对端设备名、最近 5 条已键入内容（可点击复制）、
  「暂停键入」开关（全局急停，防止误打进错误窗口）、设置、退出。
- 设置项：后缀（无/回车/Tab）、键入方式（逐字/粘贴）、键入速度、
  信任设备管理、登录时启动。

### 6.2 安全细节

- 收到内容后先发系统通知横幅（内容摘要 + 目标键入），用户有 0.5s 视觉确认；
  可在设置中改为「手动确认模式」：点通知才键入（高安全场景）。
- 「暂停键入」全局开关 + 可配置快捷键（默认 ⌥⌘K）。

### 6.3 分发说明

**macOS 端走 Developer ID 签名 + 公证的直接分发**（dmg），iOS 端走 App Store。
两端 bundle ID 同为 `com.Libra.Scan`——Universal Purchase 要求两端同 ID，现在统一是为将来上
Mac App Store 留门（ASC 上两条独立记录事后不能合并）。

不上 MAS 的原因**不是技术限制**。`CGEvent.post` 依赖的是 `PostEvent` 权限，它与 App Sandbox
兼容（系统设置里显示在「辅助功能」栏下，但和 AXUIElement 那套真正的 Accessibility API 是两个
独立权限；Maccy 等沙箱应用已在 MAS 上用同样方式合成 ⌘V）。原因是 App Review 对 2.4.5 的执行
不一致：2026-03 有同类沙箱应用被以「Accessibility features should not be used for
non-accessibility purposes」拒审，而本应用的合成键入是核心功能而非附属功能，风险更高。

若将来要上 MAS：开 App Sandbox + `com.apple.security.network.client/server` entitlements；
事件投递从 `.cghidEventTap` 改为 `.cgSessionEventTap`（HID tap 在沙箱内不工作）；权限检查与
申请改用 `CGPreflightPostEventAccess` / `CGRequestPostEventAccess`。

## 7. iOS 端改动

| 改动点 | 说明 |
| --- | --- |
| 扫一扫页右上角新增「键入到 Mac」按钮（`keyboard.badge.ellipsis` 图标） | 弹出连接 sheet：附近 Mac 列表、连接状态、断开、补发开关 |
| `BridgeClient`（新增，ObservableObject） | browse / invite / 会话管理 / 心跳 / 待发队列，挂在 ScanView 环境中 |
| 扫码数据流 | `latestScan` 发布后除落库外，若桥已连接则 `BridgeClient.send(payload)`；**本地记录照常写入**，桥是旁路不是替代 |
| 横幅 | 已连接时追加状态角标：已键入 ✓ / 发送失败 ⚠（按 ack 更新） |
| 生命周期 | 进后台断开为预期行为；回前台自动重连；扫码页以外的 Tab 不维持连接要求（连接由用户显式开关） |

## 8. 异常与边界

| 场景 | 处理 |
| --- | --- |
| Mac 未授权辅助功能 | ack `typed:false` → iPhone 横幅提示；Mac 端引导授权 |
| 键入中途断开 | 当前条目完成后停止；未发内容进待发队列 |
| 两端不同网络且蓝牙关闭 | MC 的 AWDL 不可用 → 列表为空；连接 sheet 文案提示「确保两台设备开启 Wi-Fi 与蓝牙」 |
| Mac 睡眠 | 会话断开，唤醒后 iPhone 自动重连 |
| 重复消息（补发/重连） | seq 去重，重复仅 ack |
| 超长内容（>4KB） | 自动建议切换粘贴方式（ack 带 `suggest:"paste"`）|
| 多台 iPhone 抢连一台 Mac | 后到邀请直接拒绝并附原因（单会话原则） |

## 9. 安全与隐私

- 传输：MCSession `encryptionPreference: .required`，纯局域网点对点，无服务器、无互联网流量。
- 信任：首次连接必须 Mac 端人工确认；信任列表可管理；可关闭自动接受。
- 内容：Mac 端不持久化扫码内容（「最近 5 条」仅内存）；键入即焚。
- 风险提示：模拟键入会打进**当前聚焦的任何窗口**——靠通知预告 + 急停快捷键 +
  可选手动确认模式三层缓解。

## 10. 里程碑

| 阶段 | 内容 | 验收 |
| --- | --- | --- |
| M1 连接打通 | 双端 MC 发现/配对/收发 + 协议层 | iPhone 发文本，Mac 控制台打印 |
| M2 键入引擎 | CGEvent Unicode 键入 + 权限引导 + 后缀 | 扫码内容打进 TextEdit/Excel，中文 emoji 正常 |
| M3 产品化 | 菜单栏 UI、信任列表、待发队列、回执横幅 | 完整体验闭环 |
| M4 加固 | 重连/睡眠/去重/粘贴方式/急停 | 第 8 节边界全过 |

## 11. 测试要点

1. 同 Wi-Fi、仅蓝牙（无路由器）、热点三种网络形态下发现与连接；
2. 中文 / emoji / 200+ 字符长文本 / 含换行内容的键入正确性；
3. 连续 50 次扫码连发的顺序与不丢条（seq 校验）；
4. 断线补发、重连去重、Mac 睡眠唤醒；
5. 辅助功能未授权 / 中途吊销授权的降级表现；
6. 急停开关与手动确认模式；
7. Excel、Safari 表单、Terminal、IDE 四类目标的键入兼容性。

## 12. 实现状态

**Mac 端（`LibraScanMac/`）已实现**：MC 广播 / 单会话（从 accept 起跟踪、按
session 身份过滤回调、拒绝并断开孤儿会话）、CGEvent Unicode 键入（20 单元分块、清空
修饰键标志、暂停/权限在键入时复检）、菜单栏 UI、信任列表（含首配对日期）、
按连接重置的 seq 去重（重复回执回显原结果）、30s 心跳 + 2 次丢失断开、协议版本门控、
辅助功能引导。

**iOS 端（LibraScan，本仓库）已实现**：`Bridge/BridgeClient`（browse / 邀请加密会话 /
30s 心跳 + 2 次丢失断开 / 待发队列 50 条溢出丢最旧 / 重连后按序补发可关 / seq 单调递增 /
ack 驱动横幅角标 / 回前台自动重连上次 Mac、退后台断开）、扫一扫页右上角「键入到 Mac」入口
（连接 sheet：附近 Mac 列表、连接状态、断开、补发开关）、横幅回执角标（待发送 / 发送中 /
已键入 ✓ / 未授权 · 已暂停 · 失败 ⚠）、`Info.plist` 本地网络权限与 Bonjour 服务声明；
协议层 `Shared/BridgeMessage.swift` 两端共用同一文件。

**实现注记（对 §8 的从严处理）**：已发送但断线前未收到 ack 的条目**不补发**、直接标记失败——
Mac 端 seq 去重按连接重置，跨连接补发可能造成二次键入；内容本身已在本地记录，不丢数据。
待发队列只收断线期间新扫的码（与 §4.4 一致）。

**实现注记（评审驱动的偏差）**：

- **设备名**：无 user-assigned-device-name 权限时 `UIDevice.current.name` 在真机上只返回
  通用「iPhone」，而 Mac 端信任列表以设备名为键——通用名会让所有 iPhone 在 Mac 上互认
  （信任一台等于信任全部）。iOS 端检测到通用名时追加每安装持久化的 4 位后缀
  （如「iPhone (3F8A)」）。§4.2 的配对码摘要未实现（邀请 context 为空，Mac 端本就忽略）。
- **邀请失败 ≠ 掉线**：邀请被拒 / 超时视为「配对失败」而非「连接中断」——清除桥接意图、
  清空待发队列、不自动重邀（自动重邀会反复弹出 Mac 确认框）；自动重连仅用于
  曾建立连接后的掉线（退后台、Mac 休眠、心跳丢失）。
- **本地网络权限**：实现 `didNotStartBrowsingForPeers` 回调，搜索失败时连接面板给出
  「打开设置」入口；列表为空时 footer 提示检查本地网络权限。

**版本与更新（2026-08-22）**：两端**独立发版**——iOS 走 App Store（有审核延迟），
Mac 走 Developer ID 直接分发（改完即可发），锁步只会让快的那端等慢的那端。
两者的兼容契约是 `BridgeMessage.currentVersion`，与各自的营销版本号无关。
Mac 端每天最多一次拉 `https://scan.libra.wiki/appcast.json` 比对构建号，有新版在菜单栏和
设置里提示并给出下载链接，不自动下载安装；可在设置里关闭（隐私政策已披露）。
macOS 没有官方的应用外更新框架（Apple 的答案是 Mac App Store，社区标准是第三方的 Sparkle），
本项目坚持零第三方依赖，故自持这个最小实现。

**Backlog（Mac 端，后续里程碑，对抗评审标为可接受的缺口）**：
- 键入前系统通知预告 + 手动确认模式（§6.2 安全层之二、之三）
- 全局急停快捷键 ⌥⌘K（目前仅菜单内暂停开关）
- 粘贴键入方式（剪贴板 + ⌘V）与 >4KB 内容的 `suggest:"paste"` 提示（§5.2 / §8）
- 菜单栏「正在键入」闪烁态、登录时启动（§6.1）
