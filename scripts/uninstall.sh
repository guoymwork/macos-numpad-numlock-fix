#!/usr/bin/env bash
#
# 卸载小键盘修复方案
#
#   ./scripts/uninstall.sh
#
# 默认只移除映射规则; 传 --full 可一并移除 Karabiner-Elements 本体与守护进程。
#
set -uo pipefail

CONFIG_FILE="$HOME/.config/karabiner/karabiner.json"
ASSET_FILE="$HOME/.config/karabiner/assets/complex_modifications/numpad-fix.json"
RULE_DESC="小键盘数字键始终输出数字 (绕过 macOS NumLock 状态机)"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; RESET=$'\033[0m'
ok()   { printf "%s✓%s %s\n" "$GREEN" "$RESET" "$1"; }
warn() { printf "%s!%s %s\n" "$YELLOW" "$RESET" "$1"; }
info() { printf "%s→%s %s\n" "$BLUE" "$RESET" "$1"; }
step() { printf "\n%s▸ %s%s\n" "$BLUE" "$1" "$RESET"; }

run_privileged() {
    local script="$1"
    if osascript -e "do shell script \"$script\" with administrator privileges" >/dev/null 2>&1; then
        return 0
    fi
    sudo -v 2>/dev/null && sudo sh -c "$script"
}

step "移除映射规则"

python3 - "$CONFIG_FILE" "$RULE_DESC" <<'PY'
import json, os, sys, pathlib
config_path, desc = sys.argv[1], sys.argv[2]
p = pathlib.Path(os.path.expanduser(config_path))
if not p.exists():
    print("   配置文件不存在, 跳过")
    sys.exit(0)
cfg = json.loads(p.read_text())
n = 0
for prof in cfg.get("profiles", []):
    rules = prof.get("complex_modifications", {}).get("rules", [])
    keep = [r for r in rules if r.get("description") != desc]
    n += len(rules) - len(keep)
    prof["complex_modifications"]["rules"] = keep
p.write_text(json.dumps(cfg, ensure_ascii=False, indent=2))
print(f"   已移除 {n} 条规则")
PY

if [ -f "$ASSET_FILE" ]; then
    rm -f "$ASSET_FILE"
    ok "导入型规则文件已删除"
fi

info "重载 Karabiner 配置 ..."
run_privileged "launchctl kickstart -k system/org.pqrs.service.daemon.Karabiner-Core-Service 2>/dev/null"

if [ "${1:-}" = "--full" ]; then
    step "移除 Karabiner-Elements 本体"
    run_privileged "launchctl bootout system/org.pqrs.service.daemon.Karabiner-Core-Service 2>/dev/null; \
                    launchctl bootout system/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon 2>/dev/null; \
                    rm -f /Library/LaunchDaemons/org.pqrs.service.daemon.Karabiner-*.plist; \
                    rm -rf '/Library/Application Support/org.pqrs/Karabiner-Elements'; \
                    rm -rf '/Applications/Karabiner-Elements.app'"
    ok "已移除"
fi

printf "\n%s卸载完成%s\n" "$GREEN" "$RESET"
