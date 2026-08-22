# LibraScan 自动发布

| 端 | 平台 | 为什么 | tag |
| --- | --- | --- | --- |
| iOS → TestFlight | **GitHub Actions** | 签名交给 `xcodebuild -allowProvisioningUpdates` + ASC 密钥按需申请，无需自带 p12 | `ios-v*` |
| macOS → 公证 dmg → GitHub Release | **GitHub Actions** | 反正要自带 Developer ID 证书；一套脚本跑完签名、公证、打包、发布 | `mac-v*` |

GitHub Actions 做不了 macOS 那半边：它的后置脚本环境里 `security find-identity` 返回
**0 个身份**（云签名不经过构建机的钥匙串），所以 dmg 签不了、pkg 也签不了
（`productsign` 要 Developer ID **Installer** 证书）。它只能给出一个已签名已公证的
`.app`（路径见 `CI_DEVELOPER_ID_SIGNED_APP_PATH`）。


## 四、公开仓库须知

Actions 的运行记录和日志对所有人可见，产物也能下载。密钥不会泄露：注册过的 Secret
在日志里被自动遮蔽，fork 发起的 PR 拿不到 Secret。公开仓库用 GitHub 托管的
macOS runner **不计费**。
