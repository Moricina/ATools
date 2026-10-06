#!/usr/bin/env bash
set -euo pipefail

# ATools Ed25519 更新签名密钥管理工具
# 用法:
#   ./Scripts/key_manager.sh status      # 显示密钥状态
#   ./Scripts/key_manager.sh backup      # 备份密钥到多个位置
#   ./Scripts/key_manager.sh verify      # 验证密钥与 UpdateManager.swift 一致性
#   ./Scripts/key_manager.sh restore     # 从备份恢复密钥
#   ./Scripts/key_manager.sh rotate      # 轮换密钥（生成新密钥 + 更新代码）

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

KEY_PATH="${ATOOLS_UPDATE_SIGNING_KEY:-$HOME/.config/atools/update-signing.key}"
BACKUP_DIR="$HOME/.config/atools/key-backups"
SIGNATURE_TOOL="$DIR/Scripts/update_signature.swift"
UPDATE_MANAGER="$DIR/Sources/atools/System/UpdateManager.swift"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# 获取当前密钥的公钥
get_current_public_key() {
    if [ -f "$KEY_PATH" ]; then
        swift "$SIGNATURE_TOOL" public-key "$KEY_PATH" 2>/dev/null
    fi
}

# 从 UpdateManager.swift 提取所有公钥
get_manager_public_keys() {
    grep -oE '"[A-Za-z0-9+/]{43}="' "$UPDATE_MANAGER" | tr -d '"' | sort
}

# 检查公钥是否在 UpdateManager.swift 中
is_key_registered() {
    local pubkey="$1"
    get_manager_public_keys | grep -qF "$pubkey"
}

cmd_status() {
    echo "========================================"
    echo "  ATools Ed25519 密钥状态"
    echo "========================================"
    echo ""

    # 当前密钥文件
    echo "📁 密钥文件: $KEY_PATH"
    if [ -f "$KEY_PATH" ]; then
        local perms=$(stat -f "%Lp" "$KEY_PATH" 2>/dev/null || stat -c "%a" "$KEY_PATH" 2>/dev/null)
        local pubkey=$(get_current_public_key)
        info "文件存在，权限: $perms"
        echo "   公钥: $pubkey"

        if [ "$perms" != "600" ]; then
            warn "权限不是 600，建议修复: chmod 600 $KEY_PATH"
        fi

        if is_key_registered "$pubkey"; then
            info "公钥已在 UpdateManager.swift 中注册 ✓"
        else
            error "公钥未在 UpdateManager.swift 中注册！签名的包将无法通过验证"
        fi
    else
        error "密钥文件不存在！"
    fi

    echo ""
    echo "📋 UpdateManager.swift 中的公钥:"
    get_manager_public_keys | while read -r key; do
        echo "   - $key"
    done

    echo ""
    echo "📂 备份目录: $BACKUP_DIR"
    if [ -d "$BACKUP_DIR" ]; then
        local count=$(ls -1 "$BACKUP_DIR"/*.key 2>/dev/null | wc -l | tr -d ' ')
        info "存在 $count 个备份"
        ls -lh "$BACKUP_DIR"/*.key 2>/dev/null | awk '{print "   " $NF " (" $5 ", " $6 " " $7 " " $8 ")"}'
    else
        warn "备份目录不存在"
    fi
}

cmd_backup() {
    if [ ! -f "$KEY_PATH" ]; then
        error "密钥文件不存在，无法备份: $KEY_PATH"
        exit 1
    fi

    mkdir -p "$BACKUP_DIR"

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local pubkey=$(get_current_public_key)
    local short_key="${pubkey:0:8}"
    local backup_name="update-signing_${timestamp}_${short_key}.key"
    local backup_path="$BACKUP_DIR/$backup_name"

    cp "$KEY_PATH" "$backup_path"
    chmod 600 "$backup_path"

    info "已备份到: $backup_path"

    # 验证备份完整性
    local orig_pubkey=$(swift "$SIGNATURE_TOOL" public-key "$KEY_PATH" 2>/dev/null)
    local backup_pubkey=$(swift "$SIGNATURE_TOOL" public-key "$backup_path" 2>/dev/null)

    if [ "$orig_pubkey" = "$backup_pubkey" ]; then
        info "备份验证通过 ✓ (公钥: $pubkey)"
    else
        error "备份验证失败！公钥不匹配"
        rm -f "$backup_path"
        exit 1
    fi

    # 清理超过 10 个的旧备份
    local backup_count=$(ls -1 "$BACKUP_DIR"/*.key 2>/dev/null | wc -l | tr -d ' ')
    if [ "$backup_count" -gt 10 ]; then
        local to_remove=$((backup_count - 10))
        ls -1t "$BACKUP_DIR"/*.key | tail -n "$to_remove" | xargs rm -f
        info "清理了 $to_remove 个旧备份"
    fi
}

cmd_verify() {
    echo "========================================"
    echo "  验证密钥一致性"
    echo "========================================"
    echo ""

    if [ ! -f "$KEY_PATH" ]; then
        error "密钥文件不存在: $KEY_PATH"
        echo ""
        echo "尝试从备份恢复: $0 restore"
        exit 1
    fi

    local current_pubkey=$(get_current_public_key)
    local manager_keys=$(get_manager_public_keys)

    echo "当前密钥公钥: $current_pubkey"
    echo ""
    echo "UpdateManager.swift 注册的公钥:"
    echo "$manager_keys" | while read -r key; do
        echo "  - $key"
    done
    echo ""

    if is_key_registered "$current_pubkey"; then
        info "验证通过 ✓ 当前密钥已注册"
    else
        error "验证失败 ✗ 当前密钥未注册"
        echo ""
        echo "解决方案:"
        echo "  1. 使用已注册的密钥: ./Scripts/key_manager.sh restore"
        echo "  2. 注册当前密钥: 修改 UpdateManager.swift 添加 $current_pubkey"
        exit 1
    fi
}

cmd_restore() {
    echo "========================================"
    echo "  从备份恢复密钥"
    echo "========================================"
    echo ""

    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR"/*.key 2>/dev/null)" ]; then
        error "没有可用的备份"
        exit 1
    fi

    echo "可用备份:"
    local i=1
    local backups=()
    while IFS= read -r file; do
        backups+=("$file")
        local pubkey=$(swift "$SIGNATURE_TOOL" public-key "$file" 2>/dev/null)
        local registered=""
        if is_key_registered "$pubkey"; then
            registered="${GREEN}[已注册]${NC}"
        else
            registered="${RED}[未注册]${NC}"
        fi
        echo -e "  $i) $(basename "$file") - 公钥: $pubkey $registered"
        i=$((i + 1))
    done < <(ls -1t "$BACKUP_DIR"/*.key 2>/dev/null)

    echo ""
    read -p "选择要恢复的备份编号 (1-$((i-1))): " choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -ge "$i" ]; then
        error "无效选择"
        exit 1
    fi

    local selected="${backups[$((choice-1))]}"
    local selected_pubkey=$(swift "$SIGNATURE_TOOL" public-key "$selected" 2>/dev/null)

    echo ""
    warn "将恢复以下密钥:"
    echo "  文件: $selected"
    echo "  公钥: $selected_pubkey"
    echo ""
    read -p "确认恢复? (y/N): " confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "已取消"
        exit 0
    fi

    # 备份当前密钥（如果存在）
    if [ -f "$KEY_PATH" ]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        cp "$KEY_PATH" "$BACKUP_DIR/update-signing_pre-restore_${timestamp}.key"
        info "当前密钥已备份为 pre-restore"
    fi

    cp "$selected" "$KEY_PATH"
    chmod 600 "$KEY_PATH"

    info "密钥已恢复 ✓"
    echo "  公钥: $selected_pubkey"
}

cmd_rotate() {
    echo "========================================"
    echo "  轮换 Ed25519 签名密钥"
    echo "========================================"
    echo ""

    warn "轮换密钥将:"
    echo "  1. 生成新的 Ed25519 密钥对"
    echo "  2. 将新公钥添加到 UpdateManager.swift（与旧公钥并存）"
    echo "  3. 备份当前密钥"
    echo ""
    echo "  后续步骤（需手动完成）:"
    echo "  - 用新密钥签名发布包"
    echo "  - 发布新版本"
    echo "  - 确认用户已升级后，移除旧公钥"
    echo ""
    read -p "确认继续? (y/N): " confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "已取消"
        exit 0
    fi

    # 备份当前密钥
    if [ -f "$KEY_PATH" ]; then
        cmd_backup
    fi

    # 生成新密钥
    mkdir -p "$(dirname "$KEY_PATH")"
    local new_pubkey=$(swift "$SIGNATURE_TOOL" keygen "$KEY_PATH")
    chmod 600 "$KEY_PATH"

    info "新密钥已生成"
    echo "  公钥: $new_pubkey"
    echo ""
    echo "请手动完成以下步骤:"
    echo "  1. 在 UpdateManager.swift 的 updateSigningPublicKeys 数组开头添加新公钥:"
    echo "     \"$new_pubkey\","
    echo "  2. 提交代码并发布新版本"
    echo "  3. 确认所有用户已升级后，移除旧公钥"
}

# 主入口
case "${1:-status}" in
    status)   cmd_status ;;
    backup)   cmd_backup ;;
    verify)   cmd_verify ;;
    restore)  cmd_restore ;;
    rotate)   cmd_rotate ;;
    *)
        echo "用法: $0 {status|backup|verify|restore|rotate}"
        exit 1
        ;;
esac