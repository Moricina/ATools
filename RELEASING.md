# ATools 发布流程

当前发布版本：**1.2.4 (build 11)**

## 一次完整构建

```bash
./Scripts/build.sh --test
./Scripts/package_app.sh
```

发布脚本会生成：

- `ATools.app`
- `ATools.zip`
- `ATools.dmg`
- `ATools.zip.sig`
- `ATools.dmg.sig`

`.sig` 是对安装包 SHA-256 摘要进行 Ed25519 签名后的 Base64 文本。GitHub Release 必须同时上传安装包和对应的 `.sig`，否则新版 ATools 会拒绝自动更新。

## 更新签名私钥

私钥默认保存在：

```text
~/.config/atools/update-signing.key
```

该文件权限必须保持 `0600`，并应离线备份。私钥不能进入 Git、GitHub Release 或任何发布压缩包。公钥已固定在 `Sources/atools/System/UpdateManager.swift`，轮换密钥时必须同步修改该文件并发布新的应用版本。

如需使用其他位置：

```bash
ATOOLS_UPDATE_SIGNING_KEY=/secure/path/update-signing.key ./Scripts/package_app.sh
```

## 发布前核对

1. `./Scripts/build.sh --test` 全部通过。
2. `plutil -p ATools.app/Contents/Info.plist` 中版本为 `1.2.4`，构建号为 `11`。
3. `./Scripts/update_signature.swift verify <公钥 Base64> ATools.dmg ATools.dmg.sig` 输出 `OK`。
4. GitHub Release 的标签为 `v1.2.4`。
5. Release 同时包含 `ATools.dmg`、`ATools.zip` 及各自的 `.sig`。

## 签名策略

- 更新器会拒绝没有 `.sig` 的安装包，并校验包版本、Bundle ID、可执行文件和代码签名。
- 更新器在结构校验之外校验 `codesign` designated requirement；使用 Developer ID 时还要求新旧包的 Team ID 一致。ad-hoc 构建只能更新同为 ad-hoc 的包。
- 自动更新不再清除 `com.apple.quarantine`，不会绕过 Gatekeeper。
- 当前打包默认仍使用 ad-hoc App 签名。配置 `ATOOLS_SIGNING_IDENTITY` 为 Apple Developer ID 后可生成正式签名应用：

```bash
ATOOLS_SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" ./Scripts/package_app.sh
```
