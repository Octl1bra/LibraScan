# LibraScan 自动发布

| 端 | 平台 | 为什么 | tag |
| --- | --- | --- | --- |
| iOS → TestFlight | **Xcode Cloud** | 云签名，一张证书都不用配，密钥为零 | `ios-v*` |
| macOS → 公证 dmg → 官网 | **GitHub Actions** | 反正要自带 Developer ID 证书；一套脚本跑完签名、公证、打包、上线 | `mac-v*` |

Xcode Cloud 做不了 macOS 那半边：它的后置脚本环境里 `security find-identity` 返回
**0 个身份**（云签名不经过构建机的钥匙串），所以 dmg 签不了、pkg 也签不了
（`productsign` 要 Developer ID **Installer** 证书）。它只能给出一个已签名已公证的
`.app`（路径见 `CI_DEVELOPER_ID_SIGNED_APP_PATH`）。

## 一、iOS：Xcode Cloud

仓库里只需要 [`ci_scripts/ci_pre_xcodebuild.sh`](../ci_scripts/ci_pre_xcodebuild.sh)——
它把 `CI_BUILD_NUMBER` 刷进工程的 `CURRENT_PROJECT_VERSION`（TestFlight 不接受重复的构建号）。
其余全在界面里配，一次性：

1. Xcode 打开工程 → Product → Xcode Cloud → Create Workflow → 选 **LibraScan** scheme。
2. 授权访问 GitHub 仓库（会装一个 Xcode Cloud 的 GitHub App）。
3. Start Conditions：`Tag Changes`，模式 `ios-v*`。
4. Actions：**Archive**，Platform **iOS**，Distribution **TestFlight (Internal Testing Only)**。
5. Post-Actions：**TestFlight Internal Testing** → 选测试组。

`MARKETING_VERSION` 仍然在工程里手改，构建号由 Xcode Cloud 递增。
免费额度是每月 25 compute 小时，一次 iOS 归档几分钟，够用。

## 二、macOS：GitHub Actions

[`.github/workflows/release-macos.yml`](../.github/workflows/release-macos.yml)：
打 `v*` tag 或手动触发 → 归档 → Developer ID 签名 → 公证 → staple →
打 dmg（dmg 本身也签名、公证、staple）→ 上传 artifact → 发布到 scan.libra.wiki。

[`.github/workflows/ci.yml`](../.github/workflows/ci.yml)：push / PR 时无签名编译两端，
不碰任何密钥，只保证代码没坏。

### 需要的凭据

仓库里只有**一个** GitHub Secret：`OP_SERVICE_ACCOUNT_TOKEN`——1Password 服务账号
`librascan-ci` 的令牌，只读 `gh-action` 保管库。其余全部按名字从 1Password 取：

同一个令牌另存于 `op://Agents/gh-action-sa/credential`，这样本地脚本也能**无人值守**
读到 gh-action：`opsa` 只能读 Agents，先从那里取到令牌，再用它读 gh-action
（`site/deploy.sh` 就是这么做的）。轮换时两处一起换。

| 保管库条目 | 字段 | 内容 | 状态 |
| --- | --- | --- | --- |
| `apple-dev-id-cert` | `p12_base64` | Developer ID Application 证书 + 私钥 | ✅ 2026-08-22 建好 |
| | `password` | p12 密码 | ✅ |
| | `identity` | `Developer ID Application: Jinrui Hu (6NK6HJKB8Z)` | ✅ |
| | `private_key` / `csr` | 原始私钥与 CSR，续期时可复用 | ✅ |
| `apple-asc-api-key` | `key_id` / `issuer_id` / `p8` | ASC 团队密钥（Admin），notarytool 用 | ✅ 2026-08-22 建好 |
| `cloudflare-libra` | `credential` / `account_id` | 个人 Cloudflare token | ✅ 2026-08-22 建好 |

证书有效期到 **2031-08-23**；ASC 的 `.p8` 只能下载一次，1Password 里是唯一副本。

### 关键：证书必须是 CSR 手动创建的，不能用云托管的

Xcode 自动建的 Developer ID Application 证书是**云托管**的——私钥在 Apple 服务器上，
本机没有。`xcodebuild -exportArchive` 能签（它把待签数据发给 Apple 的签名服务），
但 `codesign` 只认本地钥匙串里的完整身份，签 dmg 会报 `no identity found`。

正确做法（2026-08-22 已按此建好，续期时照做）：

1. 生成私钥与 CSR。钥匙串访问 → 证书助理 → 从证书颁发机构请求证书，或等价的命令行：
   ```bash
   openssl genrsa -out private.key 2048
   openssl req -new -key private.key -out req.certSigningRequest \
     -subj "/emailAddress=me@libra.wiki/CN=Jinrui Hu/C=CN"
   ```
2. developer.apple.com → Certificates → **+** → Software → **Developer ID Application**
   → Profile Type 选 **G2 Sub-CA** → 上传 CSR → Download `.cer`。
   （**必须在网页上传 CSR**。在 Xcode 里让它自动管理，建出来的是云托管证书，签不了 dmg。）
3. 合成 p12 并导入钥匙串：
   ```bash
   openssl x509 -inform DER -in developerID_application.cer -out cert.pem
   openssl pkcs12 -export -inkey private.key -in cert.pem -out cert.p12 -passout pass:<密码>
   security import cert.p12 -k ~/Library/Keychains/login.keychain-db -P <密码> \
     -T /usr/bin/codesign -T /usr/bin/productsign
   ```
4. `base64 -i cert.p12`，连同密码、身份全名存进 `apple-dev-id-cert`，删掉磁盘上的明文。

另外账号里还有一张 Xcode 自动创建的 **Developer ID Application Managed**（云托管、私钥在
Apple、自动续期），`xcodebuild -exportArchive` 用它签 `.app`。两张并存互不影响，别吊销。

Developer ID 证书每个账号有数量上限、有效期五年，**私钥丢了不能找回**——p12 存好。

验证是否已经拿到本地身份：

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 为什么 dmg 也必须签名并公证

Gatekeeper 评估的是磁盘映像本身，不只是里面的 app。用 Apple 自带的工具核实：

```bash
syspolicy_check distribution build/release-1.0/LibraScan-1.0.dmg
```

未签名的 dmg 会报两条 **Fatal**（`File is not signed at all`、
`A Notarization ticket is not stapled`），用户下载后打开就会被拦——即便里面的 app
已经公证并 staple。[`scripts/make-dmg.sh`](../scripts/make-dmg.sh) 在
`DEVELOPER_ID_IDENTITY` 与 `NOTARY_*` 存在时会自动补上这两步，缺凭据时会打印警告。

## 三、发一个版本

**两端版本独立**：`MARKETING_VERSION` 定义在各自 target 上，各发各的。iOS 有审核延迟，
Mac 改完就能发，锁步只会让快的等慢的。两者的兼容契约是 `BridgeMessage.currentVersion`，
与营销版本号无关。

1. 改对应 target 的 `MARKETING_VERSION`，提交。
   构建号不用管：两条流水线都取 `git rev-list --count HEAD`（提交数）。**不用
   `github.run_number` / `CI_BUILD_NUMBER`**——那两个计数器按 workflow 各自从 1 开始，
   首次运行会给出比已发布版本更低的构建号，Mac 端 appcast 会倒退、TestFlight 会以
   重复构建号拒收。两处都设了下限 `BUILD_FLOOR=4`（高于 2026-08-22 已发布的一切），
   浅克隆导致计数异常时直接失败而不是发出坏包。
2. 打对应前缀的 tag：

   ```bash
   git tag ios-v1.1 && git push origin ios-v1.1   # → Xcode Cloud → TestFlight
   git tag mac-v1.1 && git push origin mac-v1.1   # → Actions → 公证 dmg → 官网
   ```

   两个都打就是两端一起发；只打一个就只发那一端。
3. 对应的流水线开跑。
4. App Store 那一步仍然手动：在 App Store Connect 里选构建、填文案、提审。

手动重跑 macOS 那半边：Actions 页面 → Release macOS → Run workflow，填版本号，
`deploy_site` 可关掉（只出包不动官网）。

**重推 tag 的规矩**：流水线失败而代码没改 → 直接 rerun，别动 tag。加了修复 commit 想
重发同一个版本号 → 删 tag 重推（构建号取提交数，会自然变大，TestFlight 不会撞号）。
**已经交付出去的 tag 不要动**：TestFlight 收过的构建号不能复用，官网上的同名 dmg 会被
悄悄覆盖成不同字节——这种情况打新版本号。

## 四、公开仓库须知

Actions 的运行记录和日志对所有人可见，产物也能下载。密钥不会泄露：注册过的 Secret
在日志里被自动遮蔽，fork 发起的 PR 拿不到 Secret。公开仓库用 GitHub 托管的
macOS runner **不计费**。
