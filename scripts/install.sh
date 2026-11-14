#!/usr/bin/env bash
#
# 一键安装 macOS 第三方键盘小键盘修复 (Karabiner-Elements 方案)
#
#   ./scripts/install.sh
#
# 作用:
#   1. 检测 / 安装 Karabiner-Elements
#   2. 检查 Karabiner 后台服务状态
#   3. 写入 12 个映射 (数字 0-9、小数点、屏蔽 Num Lock) 到 karabiner.json
#   4. 校验规则文件并输出权限 / 验证指引
#
# 兼容 Karabiner-Elements 16.3.x (旧路径) 与 16.99.x+ (Helpers 路径)。
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RULE_TEMPLATE="$PROJECT_DIR/karabiner/numpad-fix.json"

APP="/Applications/Karabiner-Elements.app"
CONFIG_DIR="$HOME/.config/karabiner"
CONFIG_FILE="$CONFIG_DIR/karabiner.json"
ASSETS_DIR="$CONFIG_DIR/assets/complex_modifications"
ASSET_FILE="$ASSETS_DIR/numpad-fix.json"

# 旧版规则描述, 安装时一并清理, 避免新旧规则叠加
LEGACY_DESC="小键盘数字键始终输出数字 (绕过 macOS NumLock 状态机)"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; RESET=$'\033[0m'
ok()   { printf "%s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
warn() { printf "%s!%s %s\n" "$YELLOW" "$RESET" "$1"; }
err()  { printf "%s✗%s %s\n" "$RED" "$RESET" "$1"; }
info() { printf "%s→%s %s\n" "$BLUE" "$RESET" "$1"; }
step() { printf "\n%s▸ %s%s\n" "$BLUE" "$1" "$RESET"; }

find_cli() {
    local p
    for p in "$APP/Contents/Helpers/karabiner_cli" \
             "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"; do
        if [ -x "$p" ]; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    return 1
}

# ── 1. Karabiner-Elements ───────────────────────────────────────────────
step "1/4  检查 Karabiner-Elements"

if [ -d "$APP" ]; then
    V=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
    ok "已安装 (版本 $V)"
else
    info "未安装, 正在获取官方最新版下载地址 ..."
    URL="$(curl -sL --max-time 30 https://api.github.com/repos/pqrs-org/Karabiner-Elements/releases/latest \
           | python3 -c "import sys,json;d=json.load(sys.stdin);print(next((a['browser_download_url'] for a in d['assets'] if a['name'].endswith('.dmg')),''))" 2>/dev/null)"
    if [ -z "$URL" ]; then
        err "无法获取下载地址, 请手动前往 https://karabiner-elements.pqrs.org/ 安装"
        exit 1
    fi
    TMP_DMG="$(mktemp -t karabiner).dmg"
    curl -L --max-time 600 -o "$TMP_DMG" "$URL" || { err "下载失败"; exit 1; }
    hdiutil attach "$TMP_DMG" -nobrowse -quiet
    VOL="$(ls -d /Volumes/Karabiner-Elements-* 2>/dev/null | head -1)"
    if [ -z "$VOL" ]; then
        err "挂载安装镜像失败"
        exit 1
    fi
    info "安装向导已打开: 请点击「继续」→「安装」并输入登录密码"
    open "$VOL/Karabiner-Elements.pkg"
    read -r -p "安装完成后按回车继续 ..." _
    hdiutil detach "$VOL" -quiet 2>/dev/null
    rm -f "$TMP_DMG"
    if [ ! -d "$APP" ]; then
        err "安装未完成: $APP 不存在"
        exit 1
    fi
    ok "安装完成"
fi

CLI="$(find_cli)" || {
    err "未找到 karabiner_cli, 请先打开一次 Karabiner-Elements"
    exit 1
}

# ── 2. 后台服务 ─────────────────────────────────────────────────────────
step "2/4  检查后台服务"

if pgrep -qf "Karabiner-Core-Service"; then
    ok "Karabiner-Core-Service 正在运行"
else
    info "后台服务未运行, 正在打开 Karabiner-Elements ..."
    open -a Karabiner-Elements
    sleep 3
    if pgrep -qf "Karabiner-Core-Service"; then
        ok "Karabiner-Core-Service 已启动"
    else
        warn "服务仍未运行: 请在 Karabiner-Elements 中允许系统扩展 / 后台项目后再运行本脚本"
    fi
fi

# ── 3. 写入规则 ─────────────────────────────────────────────────────────
step "3/4  写入映射规则"

if [ ! -f "$RULE_TEMPLATE" ]; then
    err "规则模板不存在: $RULE_TEMPLATE"
    exit 1
fi

mkdir -p "$ASSETS_DIR"
cp "$RULE_TEMPLATE" "$ASSET_FILE"
ok "导入型规则: $ASSET_FILE"

python3 - "$RULE_TEMPLATE" "$CONFIG_FILE" "$LEGACY_DESC" <<'PY'
import json, os, sys, pathlib

tpl_path, cfg_path, legacy_desc = sys.argv[1], sys.argv[2], sys.argv[3]
tpl = json.load(open(tpl_path))
rule = tpl["rules"][0]
desc = rule["description"]

p = pathlib.Path(os.path.expanduser(cfg_path))
cfg = json.loads(p.read_text()) if p.exists() else {"profiles": []}

profiles = cfg.setdefault("profiles", [])
target = next((x for x in profiles if x.get("selected")), None)
if target is None:
    target = {
        "name": "Default",
        "selected": True,
        "virtual_hid_keyboard": {"keyboard_type_v2": "ansi"},
        "complex_modifications": {"rules": []},
    }
    profiles.append(target)

target.setdefault("virtual_hid_keyboard", {}).setdefault("keyboard_type_v2", "ansi")
cm = target.setdefault("complex_modifications", {})
rules = [r for r in cm.get("rules", []) if r.get("description") not in (desc, legacy_desc)]
rules.append(rule)
cm["rules"] = rules

p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(cfg, ensure_ascii=False, indent=4) + "\n")
print(f"   已写入 profile '{target.get('name')}': 共 {len(rules)} 条规则 / {len(rule['manipulators'])} 个映射")
PY

# ── 4. 校验与权限 ───────────────────────────────────────────────────────
step "4/4  校验与权限"

if "$CLI" --lint-complex-modifications "$RULE_TEMPLATE" >/dev/null 2>&1; then
    ok "规则文件通过 karabiner_cli 校验"
else
    warn "karabiner_cli 校验失败或当前版本不支持 --lint-complex-modifications"
fi

GUIDANCE="$("$CLI" --show-settings-window-guidance 2>/dev/null || true)"
if [ -n "$GUIDANCE" ]; then
    grep -Eq '"karabiner_json_parse_error_message"[[:space:]]*:[[:space:]]*""' <<<"$GUIDANCE" \
        && ok "karabiner.json 解析无错误" \
        || warn "karabiner.json 解析报错, 请检查配置"

    grep -Eq '"driver_connected"[[:space:]]*:[[:space:]]*true' <<<"$GUIDANCE" \
        && ok "虚拟 HID 驱动已连接" \
        || warn "虚拟 HID 驱动未连接: 重启系统后重试"

    grep -Eq '"accessibility_process_trusted"[[:space:]]*:[[:space:]]*true' <<<"$GUIDANCE" \
        && ok "辅助功能权限已授予" \
        || warn "辅助功能权限未授予 → 系统设置 > 隐私与安全性 > 辅助功能 > 勾选 Karabiner-Elements"

    grep -Eq '"iohid_listen_event_allowed"[[:space:]]*:[[:space:]]*true' <<<"$GUIDANCE" \
        && ok "输入监控权限已授予" \
        || warn "输入监控权限未授予 → 系统设置 > 隐私与安全性 > 输入监控 > 勾选 Karabiner-Elements"
else
    warn "无法读取 Karabiner 状态 (服务未就绪), 请打开 Karabiner-Elements 后重试"
fi

printf "\n%s安装完成%s\n" "$GREEN" "$RESET"
cat <<EOF

验证步骤:
  1. 打开 TextEdit, 新建文档 (英文输入法)
  2. 按小键盘 1 2 3 . 4 5 —— 应输出 123.45
  3. 按 Num Lock —— 应无反应 (该键已屏蔽)
  4. 小键盘 Enter / + / - / * / / 保持原生行为

说明:
  - 规则同时写入 karabiner.json 与 assets/complex_modifications/numpad-fix.json
  - Num Lock 键被映射为 vk_none; 如你需要它 (虚拟机/远程桌面), 删除该条 manipulator 即可
  - 配置保存后 Karabiner 会自动重载, 无需重启

自检脚本:
  $SCRIPT_DIR/verify.sh

EOF
