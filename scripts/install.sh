#!/usr/bin/env bash
#
# 一键安装 macOS 第三方键盘小键盘修复 (Karabiner-Elements 方案)
#
#   ./scripts/install.sh
#
# 作用:
#   1. 检测并安装 Karabiner-Elements
#   2. 安装 Core-Service 与 VirtualHIDDevice 两个 LaunchDaemon (开机自启)
#   3. 写入 11 条小键盘重映射规则到 ~/.config/karabiner/karabiner.json
#   4. 输出权限状态与验证指引
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RULE_TEMPLATE="$PROJECT_DIR/karabiner/numpad-fix.json"

KARABINER_APP="/Applications/Karabiner-Elements.app"
KARABINER_SUPPORT="/Library/Application Support/org.pqrs/Karabiner-Elements"
KARABINER_CLI="$KARABINER_SUPPORT/bin/karabiner_cli"
KARABINER_PRIV="$KARABINER_SUPPORT/Karabiner-Elements Privileged Daemons v2.app"
KARABINER_NONPRIV="$KARABINER_SUPPORT/Karabiner-Elements Non-Privileged Agents v2.app"

CONFIG_DIR="$HOME/.config/karabiner"
CONFIG_FILE="$CONFIG_DIR/karabiner.json"
ASSETS_DIR="$CONFIG_DIR/assets/complex_modifications"
ASSET_FILE="$ASSETS_DIR/numpad-fix.json"

RULE_DESC="小键盘数字键始终输出数字 (绕过 macOS NumLock 状态机)"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; DIM=$'\033[0;2m'; RESET=$'\033[0m'
ok()   { printf "%s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
warn() { printf "%s!%s %s\n" "$YELLOW" "$RESET" "$1"; }
err()  { printf "%s✗%s %s\n" "$RED" "$RESET" "$1"; }
info() { printf "%s→%s %s\n" "$BLUE" "$RESET" "$1"; }
step() { printf "\n%s▸ %s%s\n" "$BLUE" "$1" "$RESET"; }

# ── 提权执行 ────────────────────────────────────────────────────────────
# 优先用 osascript 触发系统密码弹窗; 若不可用则回退到 sudo。
run_privileged() {
    local script="$1"
    if osascript -e "do shell script \"$script\" with administrator privileges" >/dev/null 2>&1; then
        return 0
    fi
    sudo -v 2>/dev/null && sudo sh -c "$script"
}

# ── 1. Karabiner-Elements ───────────────────────────────────────────────
step "1/4  检查 Karabiner-Elements"

if [ -d "$KARABINER_APP" ]; then
    ok "已安装: $KARABINER_APP"
else
    info "未安装, 正在下载官方 DMG ..."
    TMP_DMG="$(mktemp -t karabiner).dmg"
    URL="$(curl -sL --max-time 30 https://api.github.com/repos/pqrs-org/Karabiner-Elements/releases/latest \
           | python3 -c "import sys,json;d=json.load(sys.stdin);print(next((a['browser_download_url'] for a in d['assets'] if a['name'].endswith('.dmg')),''))" 2>/dev/null)"
    if [ -z "$URL" ]; then
        err "无法获取下载地址, 请手动前往 https://karabiner-elements.pqrs.org/ 安装"
        exit 1
    fi
    curl -L --max-time 300 -o "$TMP_DMG" "$URL" || { err "下载失败"; exit 1; }
    hdiutil attach "$TMP_DMG" -nobrowse -quiet
    VOL="$(ls -d /Volumes/Karabiner-Elements-* 2>/dev/null | head -1)"
    info "安装向导已打开, 请在窗口中点击「继续」→「安装」并输入登录密码"
    open "$VOL/Karabiner-Elements.pkg"
    read -r -p "安装完成后按回车继续 ..." _
    hdiutil detach "$VOL" -quiet 2>/dev/null
    rm -f "$TMP_DMG"
    [ -d "$KARABINER_APP" ] && ok "安装完成" || { err "安装未完成"; exit 1; }
fi

# ── 2. 守护进程 ─────────────────────────────────────────────────────────
step "2/4  安装后台服务 (开机自启)"

DAEMON_CORE="org.pqrs.service.daemon.Karabiner-Core-Service.plist"
DAEMON_VHID="org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon.plist"

if [ -f "/Library/LaunchDaemons/$DAEMON_CORE" ] && [ -f "/Library/LaunchDaemons/$DAEMON_VHID" ]; then
    ok "LaunchDaemon 已就位"
else
    info "复制 plist 到 /Library/LaunchDaemons (需要管理员权限) ..."
    run_privileged "cp '$KARABINER_PRIV/Contents/Library/LaunchDaemons/'*.plist /Library/LaunchDaemons/ && \
                    cp '$KARABINER_NONPRIV/Contents/Library/LaunchAgents/'*.plist /Library/LaunchAgents/" \
        && ok "plist 已复制" || warn "复制失败, 可手动执行"
fi

info "加载系统服务 ..."
run_privileged "launchctl bootstrap system /Library/LaunchDaemons/$DAEMON_CORE 2>/dev/null; \
                launchctl bootstrap system /Library/LaunchDaemons/$DAEMON_VHID 2>/dev/null; \
                launchctl kickstart -k system/org.pqrs.service.daemon.Karabiner-Core-Service 2>/dev/null"
sleep 3

if launchctl print system 2>/dev/null | grep -q "org.pqrs.service.daemon.Karabiner-Core-Service"; then
    ok "Core-Service 已注册"
else
    warn "Core-Service 未注册, 建议重启后重试"
fi

# ── 3. 写入规则 ─────────────────────────────────────────────────────────
step "3/4  写入映射规则"

mkdir -p "$ASSETS_DIR"
cp "$RULE_TEMPLATE" "$ASSET_FILE"
ok "导入型规则: $ASSET_FILE"

python3 - "$RULE_TEMPLATE" "$CONFIG_FILE" "$RULE_DESC" <<'PY'
import json, os, sys, pathlib

template_path, config_path, desc = sys.argv[1], sys.argv[2], sys.argv[3]
rule = json.load(open(template_path))

p = pathlib.Path(os.path.expanduser(config_path))
if p.exists():
    cfg = json.loads(p.read_text())
else:
    cfg = {"global": {}, "profiles": []}

cfg.setdefault("global", {})
cfg["global"].setdefault("check_for_updates_on_startup", True)
cfg["global"].setdefault("show_in_menu_bar", True)

profiles = cfg.setdefault("profiles", [])
target = next((x for x in profiles if x.get("selected")), None)
if target is None:
    target = {"name": "Default", "selected": True, "virtual_hid_keyboard": {"keyboard_type_v2": "ansi"},
              "complex_modifications": {"rules": []}, "devices": [], "device_open_delay": 100}
    profiles.append(target)

target.setdefault("virtual_hid_keyboard", {}).setdefault("keyboard_type_v2", "ansi")
cm = target.setdefault("complex_modifications", {"rules": []})
cm["rules"] = [r for r in cm.get("rules", []) if r.get("description") != desc]
cm["rules"].append(rule)

p.parent.mkdir(parents=True, exist_ok=True)
p.write_text(json.dumps(cfg, ensure_ascii=False, indent=2))
print(f"   已写入 {len(cm['rules'])} 条规则到 profile '{target['name']}'")
PY

# ── 4. 权限与验证 ───────────────────────────────────────────────────────
step "4/4  权限与状态检查"

if [ -x "$KARABINER_CLI" ]; then
    if "$KARABINER_CLI" --list-system-variables >/dev/null 2>&1; then
        ok "core_service 通信正常"
    else
        warn "core_service 未就绪, 尝试重启 ..."
        run_privileged "launchctl kickstart -k system/org.pqrs.service.daemon.Karabiner-Core-Service 2>/dev/null"
        sleep 3
        "$KARABINER_CLI" --list-system-variables >/dev/null 2>&1 \
            && ok "core_service 已恢复" || warn "core_service 仍未就绪, 重启后应自动恢复"
    fi
fi

PERM_FILE="$(ls "$HOME/.local/share/karabiner/tmp/"*.json 2>/dev/null | head -1)"
if [ -n "$PERM_FILE" ]; then
    PERM="$(cat "$PERM_FILE")"
    case "$PERM" in
        *'"accessibility_process_trusted":true'*) ok "辅助功能权限已授予" ;;
        *) warn "辅助功能权限未授予 → 系统设置 > 隐私与安全性 > 辅助功能 > 添加 Karabiner-Elements" ;;
    esac
    case "$PERM" in
        *'"iohid_listen_event_allowed":true'*) ok "HID 监听权限已授予" ;;
        *) warn "HID 监听权限未授予 → 系统设置 > 隐私与安全性 > 输入监控 > 添加 Karabiner-Elements" ;;
    esac
fi

printf "\n%s安装完成%s\n" "$GREEN" "$RESET"
cat <<EOF

验证步骤:
  1. 打开 TextEdit, 新建文档
  2. 按小键盘的 1 2 3 —— 应正常输出数字

如需打开配置界面:
  open -a Karabiner-Elements

自检脚本:
  $SCRIPT_DIR/verify.sh

EOF
