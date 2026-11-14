#!/usr/bin/env bash
#
# 卸载小键盘修复方案
#
#   ./scripts/uninstall.sh          仅移除映射规则
#   ./scripts/uninstall.sh --full   同时引导卸载 Karabiner-Elements 本体
#
set -uo pipefail

APP="/Applications/Karabiner-Elements.app"
CONFIG_FILE="$HOME/.config/karabiner/karabiner.json"
ASSET_FILE="$HOME/.config/karabiner/assets/complex_modifications/numpad-fix.json"

NEW_DESC="小键盘：数字与小数点直通，Num Lock 键不干扰"
LEGACY_DESC="小键盘数字键始终输出数字 (绕过 macOS NumLock 状态机)"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; RESET=$'\033[0m'
ok()   { printf "%s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
warn() { printf "%s!%s %s\n" "$YELLOW" "$RESET" "$1"; }
info() { printf "%s→%s %s\n" "$BLUE" "$RESET" "$1"; }
step() { printf "\n%s▸ %s%s\n" "$BLUE" "$1" "$RESET"; }

step "移除映射规则"

python3 - "$CONFIG_FILE" "$NEW_DESC" "$LEGACY_DESC" <<'PY'
import json, os, sys, pathlib

config_path, new_desc, legacy_desc = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(os.path.expanduser(config_path))
if not p.exists():
    print("   配置文件不存在, 跳过")
    sys.exit(0)

cfg = json.loads(p.read_text())
removed = 0
for prof in cfg.get("profiles", []):
    cm = prof.get("complex_modifications", {})
    rules = cm.get("rules", [])
    keep = [r for r in rules if r.get("description") not in (new_desc, legacy_desc)]
    removed += len(rules) - len(keep)
    cm["rules"] = keep

p.write_text(json.dumps(cfg, ensure_ascii=False, indent=4) + "\n")
print(f"   已移除 {removed} 条规则")
PY

if [ -f "$ASSET_FILE" ]; then
    rm -f "$ASSET_FILE"
    ok "导入型规则文件已删除"
fi

info "Karabiner 会自动重载配置, 无需重启"

if [ "${1:-}" = "--full" ]; then
    step "卸载 Karabiner-Elements 本体"
    if [ -x "$APP/Contents/Resources/uninstall.sh" ]; then
        cat <<EOF

请执行以下命令完成彻底卸载 (会要求输入管理员密码):

  sudo "$APP/Contents/Resources/uninstall.sh"

或打开 Karabiner-Elements → Settings → Misc → Uninstall Karabiner-Elements。

EOF
    else
        warn "未找到应用内卸载脚本, 请手动删除 $APP 及 /Library/Application Support/org.pqrs"
    fi
fi

printf "\n%s卸载完成%s\n" "$GREEN" "$RESET"
