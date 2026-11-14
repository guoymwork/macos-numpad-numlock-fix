#!/usr/bin/env bash
#
# 自检脚本 —— 确认修复是否完整生效
#
#   ./scripts/verify.sh
#
# 检查项:
#   1. Karabiner-Elements 是否安装
#   2. 后台服务 / 虚拟 HID 驱动
#   3. 辅助功能 / 输入监控权限
#   4. 映射规则是否已加载
#   5. 导入型规则文件
#   6. 冲突检查 (hidutil 是否有残留映射)
#
set -uo pipefail

APP="/Applications/Karabiner-Elements.app"
CFG="$HOME/.config/karabiner/karabiner.json"
ASSET="$HOME/.config/karabiner/assets/complex_modifications/numpad-fix.json"
EXPECTED_MAPS=12

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; DIM=$'\033[0;2m'; RESET=$'\033[0m'
PASS=0; FAIL=0; WARN=0

chk_pass() { printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$1"; PASS=$((PASS+1)); }
chk_fail() { printf "  %s✗%s %s\n" "$RED" "$RESET" "$1"; FAIL=$((FAIL+1)); }
chk_warn() { printf "  %s!%s %s\n" "$YELLOW" "$RESET" "$1"; WARN=$((WARN+1)); }

find_cli() {
    local p
    for p in "$APP/Contents/Helpers/karabiner_cli" \
             "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"; do
        [ -x "$p" ] && { printf '%s\n' "$p"; return 0; }
    done
    return 1
}

echo
echo "macOS 小键盘修复 — 状态自检"
echo "─────────────────────────────────────────────"

# 1. 应用
printf "\n1. Karabiner-Elements\n"
if [ -d "$APP" ]; then
    V=$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")
    chk_pass "已安装 (版本 $V)"
else
    chk_fail "未安装"
fi

CLI="$(find_cli)" || CLI=""
if [ -n "$CLI" ]; then
    chk_pass "karabiner_cli: $CLI"
else
    chk_fail "未找到 karabiner_cli"
fi

# 2. 服务
printf "\n2. 后台服务\n"
if pgrep -qf "Karabiner-Core-Service"; then
    chk_pass "Core-Service 正在运行"
else
    chk_fail "Core-Service 未运行 (打开 Karabiner-Elements)"
fi

if ls -d /Library/SystemExtensions/*/org.pqrs.Karabiner-DriverKit-VirtualHIDDevice.dext >/dev/null 2>&1; then
    chk_pass "DriverKit 虚拟 HID 扩展已加载"
else
    chk_fail "虚拟 HID 扩展未加载 (安装后需重启系统)"
fi

# 3. 权限
printf "\n3. 权限\n"
if [ -n "$CLI" ]; then
    G="$("$CLI" --show-settings-window-guidance 2>/dev/null || true)"
    if [ -n "$G" ]; then
        grep -Eq '"accessibility_process_trusted"[[:space:]]*:[[:space:]]*true' <<<"$G" \
            && chk_pass "辅助功能权限" \
            || chk_fail "辅助功能权限未授予 → 系统设置 > 隐私与安全性 > 辅助功能"
        grep -Eq '"iohid_listen_event_allowed"[[:space:]]*:[[:space:]]*true' <<<"$G" \
            && chk_pass "输入监控权限" \
            || chk_fail "输入监控权限未授予 → 系统设置 > 隐私与安全性 > 输入监控"
        grep -Eq '"driver_connected"[[:space:]]*:[[:space:]]*true' <<<"$G" \
            && chk_pass "虚拟 HID 驱动已连接" \
            || chk_fail "虚拟 HID 驱动未连接"
        grep -Eq '"karabiner_json_parse_error_message"[[:space:]]*:[[:space:]]*""' <<<"$G" \
            && chk_pass "karabiner.json 解析无错误" \
            || chk_fail "karabiner.json 解析报错"
    else
        chk_warn "无法读取 Karabiner 状态 (服务未就绪)"
    fi
else
    chk_warn "缺少 karabiner_cli, 跳过权限检查"
fi

# 4. 规则
printf "\n4. 映射规则\n"
if [ -f "$CFG" ]; then
    COUNTS="0 0"
    COUNTS=$(python3 - "$CFG" 2>/dev/null <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
p = next((x for x in d.get("profiles", []) if x.get("selected")), None)
rules = p.get("complex_modifications", {}).get("rules", []) if p else []
print(len(rules), sum(len(r.get("manipulators", [])) for r in rules))
PY
) || COUNTS="0 0"
    NRULES=$(awk '{print $1}' <<<"$COUNTS")
    NMAPS=$(awk '{print $2}' <<<"$COUNTS")
    if [ "${NMAPS:-0}" -ge "$EXPECTED_MAPS" ] 2>/dev/null; then
        chk_pass "已加载 $NRULES 条规则 / $NMAPS 个映射 (预期 ≥$EXPECTED_MAPS)"
    elif [ "${NRULES:-0}" -gt 0 ] 2>/dev/null; then
        chk_warn "映射数 $NMAPS 少于预期 $EXPECTED_MAPS, 运行 install.sh 补齐"
    else
        chk_fail "未找到映射规则, 运行 install.sh 安装"
    fi
else
    chk_fail "配置文件不存在: $CFG"
fi

# 5. 导入型规则
printf "\n5. 导入型规则文件\n"
if [ -f "$ASSET" ]; then
    chk_pass "存在: $ASSET"
else
    chk_warn "不存在 (不影响实际生效, 重跑 install.sh 可生成)"
fi

# 6. 冲突检查
printf "\n6. 冲突检查\n"
M=$(hidutil property --get UserKeyMapping 2>/dev/null | grep -c "HIDKeyboardUsage =" || true)
if [ "${M:-0}" -eq 0 ] 2>/dev/null; then
    chk_pass "hidutil 无残留映射"
else
    chk_warn "hidutil 存在 $M 条映射, 可能与 Karabiner 双重生效"
    printf "    %s清空命令: hidutil property --set '{\"UserKeyMapping\":[]}'%s\n" "$DIM" "$RESET"
fi

printf "\n─────────────────────────────────────────────\n"
printf "通过 %s%d%s  失败 %s%d%s  警告 %s%d%s\n" \
    "$GREEN" "$PASS" "$RESET" "$RED" "$FAIL" "$RESET" "$YELLOW" "$WARN" "$RESET"

if [ "$FAIL" -eq 0 ]; then
    printf "\n%s状态良好%s — 到 TextEdit 里按小键盘 1 2 3 . 4 5 验证\n" "$GREEN" "$RESET"
else
    printf "\n%s存在失败项%s — 运行 ./scripts/install.sh 或按提示修复\n" "$RED" "$RESET"
fi
echo
