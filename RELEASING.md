# ATools 发布流程

当前发布版本：**1.3.6 (build 29)**

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

---

## 🔐 Ed25519 更新签名密钥管理（重要）

### 密钥位置

```text
~/.config/atools/update-signing.key
```

### 密钥管理工具

使用 `key_manager.sh` 管理密钥：

```bash
./Scripts/key_manager.sh status    # 查看密钥状态
./Scripts/key_manager.sh backup    # 备份密钥
./Scripts/key_manager.sh verify    # 验证密钥与代码一致性
./Scripts/key_manager.sh restore   # 从备份恢复密钥
./Scripts/key_manager.sh rotate    # 轮换密钥
```

### 🔴 密钥丢失预防（必读）

**问题**：如果签名密钥丢失，将无法发布自动更新包，用户必须手动下载覆盖安装。

**预防措施**：

1. **每次发布前验证**
   ```bash
   ./Scripts/key_manager.sh verify
   ```

2. **定期备份**（至少在每次发布后）
   ```bash
   ./Scripts/key_manager.sh backup
   ```
   备份存储在 `~/.config/atools/key-backups/`，自动保留最近 10 个。

3. **离线备份**（推荐）
   ```bash
   # 备份到外部存储
   cp ~/.config/atools/update-signing.key /path/to/secure/backup/
   
   # 或加密备份
   gpg -c ~/.config/atools/update-signing.key
   ```

4. **发布脚本自动校验**
   - `package_app.sh` 会在签名前自动验证密钥是否在 `UpdateManager.swift` 中注册
   - 如果密钥不匹配，构建会失败并提示修复方法

### 密钥轮换流程

如果需要轮换密钥（例如密钥泄露或计划性更换）：

1. **生成新密钥**
   ```bash
   ./Scripts/key_manager.sh rotate
   ```

2. **更新代码**
   - 在 `UpdateManager.swift` 的 `updateSigningPublicKeys` 数组**开头**添加新公钥
   - 旧公钥保留在数组中（支持双密钥过渡）

3. **发布新版本**
   - 用新密钥签名发布包
   - 用户更新后，新版客户端同时接受新旧密钥

4. **清理旧密钥**（确认所有用户已升级后）
   - 从 `updateSigningPublicKeys` 数组移除旧公钥
   - 发布最终版本

---

## macOS 代码签名证书

### 证书位置

- 钥匙串中的 `ATools Sign` 自签名证书
- 有效期至 2036-09-26
- P12 备份：`~/Documents/ATools证书.p12`

### 签名策略

- `package_app.sh` 默认自动使用钥匙串里的 `ATools Sign`（不存在则回退 ad-hoc）
- 指纹 pinning：`e27bee7aa3e27e544d365c8042723d2c6624fbdb`（已入 `expectedSigningLeafHashes`）
- 换证书流程：新版同时 pin [旧, 新] 双指纹 → 下一版收敛为 [新]

---

## 发布前核对清单

1. **运行诊断测试**
   ```bash
   ./Scripts/build.sh --test
   ```
   确认全部通过（或仅有已知的环境相关失败）

2. **验证签名密钥**
   ```bash
   ./Scripts/key_manager.sh verify
   ```
   确认当前密钥已在 `UpdateManager.swift` 中注册

3. **备份签名密钥**
   ```bash
   ./Scripts/key_manager.sh backup
   ```

4. **检查版本号**
   ```bash
   plutil -p ATools.app/Contents/Info.plist | grep -E "Version|Build"
   ```

5. **打包发布**
   ```bash
   ATOOLS_SIGNING_IDENTITY="-" ./Scripts/package_app.sh  # ad-hoc
   # 或使用证书签名
   ./Scripts/package_app.sh
   ```

6. **验证签名**
   ```bash
   # 使用当前密钥验证
   ./Scripts/update_signature.swift verify <当前公钥> ATools.dmg ATools.dmg.sig
   
   # 使用 UpdateManager.swift 中的所有公钥验证
   for key in $(grep -oE '"[A-Za-z0-9+/]{43}=" Sources/atools/System/UpdateManager.swift | tr -d '"'); do
       echo "验证公钥: $key"
       ./Scripts/update_signature.swift verify "$key" ATools.dmg ATools.dmg.sig && echo "✓ 通过" || echo "✗ 失败"
   done
   ```

7. **创建 GitHub Release**
   ```bash
   ~/bin/gh release create v<VERSION> \
     --title "ATools v<VERSION>" \
     --notes "..." \
     ATools.dmg ATools.zip ATools.dmg.sig ATools.zip.sig
   ```

8. **验证 Release**
   ```bash
   curl -s "https://api.github.com/repos/Moricina/ATools/releases/latest" | grep tag_name
   ```

---

## 常见问题

### Q: 密钥丢失了怎么办？

A: 
1. 检查备份：`./Scripts/key_manager.sh restore`
2. 如果没有备份，需要生成新密钥并做双公钥迁移
3. 发布新版本后，旧版用户需要手动下载更新

### Q: 如何确认 v1.2.8 用户能自动更新到新版本？

A: v1.2.8 只接受公钥 `HbGQoLgpZ8MVghAQOJIR79JC7YvkRQmzimfO2OuFE34=`。如果新版本用其他密钥签名，v1.2.8 用户必须手动下载。双公钥迁移只能保证 v1.2.9+ 用户的后续更新。

### Q: 签名验证失败怎么办？

A: 
1. 检查密钥：`./Scripts/key_manager.sh status`
2. 验证一致性：`./Scripts/key_manager.sh verify`
3. 如果密钥不匹配，恢复备份或重新生成

---

## 目录结构

```
~/.config/atools/
├── update-signing.key          # 当前签名密钥（权限 600）
└── key-backups/                # 自动备份目录
    ├── update-signing_20261006_082050_V+7AgVQr.key
    ├── update-signing_20261006_081500_HbGQoLgp.key
    └── ...
```

---

## 安全注意事项

- ⚠️ **私钥不能进入 Git、GitHub Release 或任何发布压缩包**
- ⚠️ **密钥文件权限必须保持 `0600`**
- ✅ 公钥可以公开（已硬编码在 `UpdateManager.swift` 中）
- ✅ 建议使用 `gpg` 或硬件密钥进行离线备份