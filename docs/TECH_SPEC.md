# LibraScan 技术设计文档

| 项目 | 内容 |
| --- | --- |
| 对应 PRD | [PRD.md](./PRD.md) |
| 文档日期 | 2026-06-10 |
| 部署目标 | iOS 26.0+ |
| 语言 / UI | Swift + SwiftUI |
| 持久化 | SwiftData |

> 实现备注：工程开启了 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 与 `MemberImportVisibility`，
> 所有类型默认主线程隔离；`ScannerController` 中跨 `sessionQueue` 的成员用
> `nonisolated(unsafe)` 显式标注（仅在串行会话队列上访问）。

## 1. 总体架构

采用 SwiftUI + MVVM 的轻量分层，不引入任何第三方依赖：

```
┌─────────────────────────────────────────────┐
│                  App 层                      │
│  LibraScanApp（注入 ModelContainer）          │
├─────────────────────────────────────────────┤
│                  View 层                     │
│  RootTabView                                 │
│   ├── ScanView          （Tab 1 扫一扫）      │
│   │    ├── ScannerPreview（相机预览,UIKit桥接）│
│   │    └── ScanResultSheet（结果卡片）         │
│   └── HistoryView       （Tab 2 记录）        │
│        └── HistoryDetailView（记录详情）       │
├─────────────────────────────────────────────┤
│               ViewModel / Service 层          │
│  ScannerController（AVCaptureSession 管理）   │
│  HapticFeedback（震动反馈）                    │
├─────────────────────────────────────────────┤
│                 数据层                        │
│  ScanRecord（SwiftData @Model）               │
└─────────────────────────────────────────────┘
```

## 2. 关键技术选型

### 2.1 扫码引擎：AVFoundation `AVCaptureMetadataOutput`

选择 AVFoundation 原生元数据识别，而非 VisionKit `DataScannerViewController`：

- PRD 要求的全部码制（QR、EAN、Code 128、PDF417 等）`AVMetadataObject.ObjectType` 均原生支持，可精确声明白名单。
- 对相机会话有完全控制权（暂停 / 恢复 / 手电筒），便于实现 F1.9 的 Tab 切换暂停逻辑。
- 无 UI 绑定，预览层用 `AVCaptureVideoPreviewLayer` 自由布局，扫描框样式完全自定义。

识别码制白名单：

```swift
let supportedTypes: [AVMetadataObject.ObjectType] = [
    .qr, .dataMatrix, .aztec, .pdf417,
    .ean13, .ean8, .upce,
    .code39, .code93, .code128, .itf14, .codabar
]
```

### 2.2 持久化：SwiftData

工程模板已集成 SwiftData。将模板的 `Item` 模型替换为 `ScanRecord`：

```swift
@Model
final class ScanRecord {
    var content: String        // 码内容原文
    var symbology: String      // 码制类型（如 "QR Code" / "EAN-13"）
    var scannedAt: Date        // 扫码时间
    var isURL: Bool            // 是否为可打开的链接（写入时判定，供列表/详情直接使用）

    init(content: String, symbology: String, scannedAt: Date = .now) {
        self.content = content
        self.symbology = symbology
        self.scannedAt = scannedAt
        self.isURL = Self.detectURL(content)
    }
}
```

数据量级为本地个人记录（千条以内），SwiftData `@Query` 按 `scannedAt` 倒序即可满足列表与搜索（F2.7 用 `#Predicate` 的 `localizedStandardContains`）。

## 3. 模块设计

### 3.1 文件结构

```
LibraScan/
├── LibraScanApp.swift            // App 入口，ModelContainer 注入
├── RootTabView.swift             // TabView 双 Tab 骨架（AppTab 枚举）
├── Scan/
│   ├── ScanView.swift            // 扫码页：预览 + 扫描框 + 手电筒 + 权限引导
│   ├── ScannerController.swift   // AVCaptureSession 封装（ObservableObject）
│   ├── ScannerPreview.swift      // UIViewRepresentable 桥接预览层
│   └── ScanResultSheet.swift     // 识别结果卡片（.sheet + presentationDetents）
├── History/
│   ├── HistoryView.swift         // 记录列表：@Query 倒序、搜索、左滑删除、清空
│   └── HistoryDetailView.swift   // 记录详情：完整内容 + 操作按钮
├── Models/
│   └── ScanRecord.swift
├── Shared/
│   ├── ContentClassifier.swift   // http(s) 链接判定（模型与视图共用）
│   └── HapticFeedback.swift
├── Localizable.xcstrings         // UI 文案（en 源 + zh-Hans）
└── InfoPlist.xcstrings           // 相机权限文案本地化
```

### 3.2 ScannerController（核心）

职责：管理 `AVCaptureSession` 生命周期、权限、手电筒、识别回调与去重。

```swift
@MainActor
final class ScannerController: NSObject, ObservableObject,
                               AVCaptureMetadataOutputObjectsDelegate {
    @Published var authorizationStatus: AVAuthorizationStatus
    @Published var isTorchOn = false
    @Published var latestScan: (content: String, symbology: String)?

    let session = AVCaptureSession()

    func requestPermissionAndStart() async
    func start()   // sessionQueue（后台串行队列）上 startRunning
    func stop()    // Tab 切走 / 进后台时调用
    func toggleTorch()

    // delegate 回调：主线程外解析 → 去重 → 发布 latestScan
}
```

**关键实现点：**

- `startRunning()` / `stopRunning()` 必须在专用串行队列执行，避免阻塞主线程（性能指标：冷启动 ≤ 1.5s）。
- **去重（F1.6）**：记录 `(lastContent, lastTime)`，相同内容且间隔 < 2s 的回调直接丢弃；
  结果卡片弹出期间对仍在画面中的同一码**持续滑动窗口**——关闭卡片时若镜头还对着同一个码，
  不会立即重复落库、卡片也不会秒弹回；换一个码则立即识别。
- **会话生命周期（F1.9）**：以 `selectedTab` 变化驱动 `start()/stop()`；同时监听 `scenePhase`，
  进后台 `stop()`、回前台且当前 Tab 为扫码页时 `start()`。
- **中断恢复**：控制器维护 `wantsRunning` 意图标志（`start()` 置 true、`stop()` 置 false），
  `interruptionEnded` 通知只在 `wantsRunning` 时恢复会话；`stop()` 无条件调用 `stopRunning()`
  ——被中断的会话已被系统自动停止（`isRunning == false`），只有显式 `stopRunning()` 才能取消
  AVFoundation 保留的启动请求，否则中断结束后相机会在「记录」Tab 下自行复活。
- **手电筒**：`isTorchOn` 在主线程乐观更新（连点不丢切换），硬件设置失败时回滚。
- **变焦（F1.10）**：`ScanView` 上挂 `MagnifyGesture`，以手势起始时的 `zoomFactor` 为锚点
  乘以捏合倍率；`setZoom` 钳制到 `[minAvailableVideoZoomFactor, min(maxAvailable, 8)]`
  （数码变焦超过 8x 对识别没有意义），主线程乐观更新、会话队列写硬件；
  画面上显示当前倍率角标（>1.0 时）。
- 识别成功后通过 `latestScan != nil` 抑制新结果发布，待结果卡片关闭后恢复。

### 3.3 扫码到落库的数据流

```
AVCaptureMetadataOutput delegate
        │  (sessionQueue)
        ▼
 去重检查（2s 窗口）
        │ 通过
        ▼
 MainActor: latestScan 更新
        │
        ├──► HapticFeedback.success()        // 震动
        ├──► ScanResultSheet 弹出             // sheet(item:)
        └──► modelContext.insert(ScanRecord)  // 立即落库，与 UI 展示解耦
```

记录写入不依赖用户对结果卡片的操作——识别成功即落库（F1.5），保证「记录写入成功率 100%」。

### 3.4 RootTabView

```swift
TabView(selection: $selectedTab) {
    ScanView()
        .tabItem { Label("扫一扫", systemImage: "qrcode.viewfinder") }
        .tag(Tab.scan)
    HistoryView()
        .tabItem { Label("记录", systemImage: "clock.arrow.circlepath") }
        .tag(Tab.history)
}
```

`selectedTab` 下发给 `ScanView`，配合 `onChange` 控制相机会话启停。

### 3.5 权限处理（F1.8）

- `Info.plist` 增加 `NSCameraUsageDescription`：「LibraScan 需要使用相机来扫描二维码和条形码，画面不会被保存或上传。」
- `ScanView` 按 `authorizationStatus` 分支渲染：
  - `.notDetermined` → 触发系统弹窗
  - `.denied / .restricted` → 引导视图 + 按钮跳转 `UIApplication.openSettingsURLString`
  - `.authorized` → 相机预览

### 3.6 结果卡片（ScanResultSheet）

- `.sheet(item:)` + `presentationDetents([.height(360)])`，不打断取景视觉。
- URL 判定：`URL(string:)` 解析成功且 scheme 为 `http/https` 视为链接；主按钮 `openURL` 环境值打开。
- 复制用 `UIPasteboard.general.string`；分享用 `ShareLink`。

## 4. 异常与边界

| 场景 | 处理 |
| --- | --- |
| 相机权限被拒 | 引导页 + 跳系统设置（F1.8） |
| 设备无后置摄像头 / 模拟器 | 预览区显示占位提示「当前设备不支持相机」 |
| 设备不支持手电筒 | 隐藏手电筒按钮（`device.hasTorch` 判断） |
| 码内容超长（>10KB 文本） | 列表只渲染摘要；详情页可滚动展示全文 |
| SwiftData 写入失败 | 本地容器写入基本不失败；保留 `try?` 并打 os_log，不阻断扫码流程 |
| 来电 / 中断（`AVCaptureSession` interruption 通知） | 监听并在中断结束后恢复会话（仅当 `wantsRunning`，即扫码页仍是活跃界面） |
| 横竖屏 | 锁定竖屏、仅 iPhone（`TARGETED_DEVICE_FAMILY = 1`）；预览层不做旋转适配，避免横屏画面横躺 |

## 5. 测试要点

- **单元测试**：去重窗口逻辑、URL 判定、`ScanRecord` 初始化字段。
- **真机手测清单**（相机无法在模拟器验证）：
  1. 各码制各扫一次，验证类型标签正确；
  2. 同一码连续对准 5 秒，记录里只出现一条；
  3. 扫码 → 切记录 Tab → 切回，相机恢复正常；
  4. 退后台 / 回前台、来电中断恢复；
  5. 拒绝权限后的引导页与设置跳转；
  6. 弱光下手电筒开关。

## 6. 工程改造步骤（基于当前模板）

1. 删除模板 `Item.swift` 与 `ContentView.swift`，新建 `ScanRecord` 并更新 `LibraScanApp` 的 Schema。
2. 搭建 `RootTabView` 双 Tab 骨架与空白 `HistoryView`。
3. 实现 `ScannerController` + `ScannerPreview`，跑通真机识别回调。
4. 实现结果卡片、震动、落库与去重。
5. 实现记录列表 / 详情 / 删除 / 清空。
6. 权限引导、手电筒、中断恢复等边界处理。
7. 本地化（zh-Hans / en）与无障碍标签收尾。
