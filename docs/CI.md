# LibraScan 自动发布

| 端 | 平台 | 为什么 |
| --- | --- | --- |
| iOS → TestFlight | **Xcode Cloud** | 云签名，一张证书都不用配，密钥为零 |
| macOS → 公证 dmg → 官网 | **GitHub Actions** | 反正要自带 Developer ID 证书；一套脚本跑完签名、公证、打包、上线 |

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
3. Start Conditions：`Tag Changes`，模式 `v*`（和 macOS 那边同一个 tag 触发）。
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

仓库里只有**一个** GitHub Secret：`OP_SERVICE_ACCOUNT_TOKEN`（已配好，是
1Password 服务账号 `gh-action-librascan` 的令牌，只读 `gh-action` 保管库）。
其余全部按名字从 1Password 取：

| 保管库条目 | 字段 | 内容 |
| --- | --- | --- |
| `apple-dev-id-cert` | `p12_base64` | Developer ID Application 证书 + 私钥，`base64 -i cert.p12` |
| | `password` | 导出 p12 时设的密码 |
| | `identity` | 完整身份名，如 `Developer ID Application: Jinrui Hu (6NK6HJKB8Z)` |
| `apple-asc-api-key` | `key_id` / `issuer_id` | ASC API 密钥的两个 ID |
| | `p8` | `.p8` 文件的**全文**（含 BEGIN/END 行） |
| `cloudflare-libra` | `credential` / `account_id` | 个人 Cloudflare token（Agents 保管库里那份复制过来） |

### 关键：证书必须是 CSR 手动创建的，不能用云托管的

Xcode 自动建的 Developer ID Application 证书是**云托管**的——私钥在 Apple 服务器上，
本机没有。`xcodebuild -exportArchive` 能签（它把待签数据发给 Apple 的签名服务），
但 `codesign` 只认本地钥匙串里的完整身份，签 dmg 会报 `no identity found`。

正确做法，一次性：

1. 钥匙串访问 → 证书助理 → **从证书颁发机构请求证书**：邮箱填你的，选「存储到磁盘」
   ——私钥这一刻生成并留在本机。
2. developer.apple.com → Certificates → **+** → **Developer ID Application** →
   选**手动创建**（不要云托管）→ 上传刚才的 CSR → 下载 `.cer` → 双击安装。
3. 钥匙串里找到它，右键导出为 `.p12`，设密码。
4. `base64 -i cert.p12 | pbcopy`，连同密码和身份全名存进 `apple-dev-id-cert`。

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

1. 改 `LibraScan.xcodeproj` 里的 `MARKETING_VERSION`（两端共用一处），提交。
2. `git tag v1.1 && git push origin v1.1`
3. 两条流水线同时开跑：Xcode Cloud 把 iOS 送进 TestFlight，Actions 出公证 dmg 并更新官网。
4. App Store 那一步仍然手动：在 App Store Connect 里选构建、填文案、提审。

手动重跑 macOS 那半边：Actions 页面 → Release macOS → Run workflow，填版本号，
`deploy_site` 可关掉（只出包不动官网）。

## 四、公开仓库须知

Actions 的运行记录和日志对所有人可见，产物也能下载。密钥不会泄露：注册过的 Secret
在日志里被自动遮蔽，fork 发起的 PR 拿不到 Secret。公开仓库用 GitHub 托管的
macOS runner **不计费**。
