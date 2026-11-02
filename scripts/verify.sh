#!/usr/bin/env bash
#
# 自检脚本 —— 确认修复是否完整生效
#
#   ./scripts/verify.sh
#
# 检查项:
#   1. Karabiner-Elements 是否安装
#   2. 后台服务是否注册 (core_service 通信)
#   3. 辅助功能 / HID 监听权限
#   4. 映射规则是否已加载
#   5. 虚拟 HID 驱动是否加载
#   6. 冲突检查 (hidutil 是否有残留映射)
#
set -uo pipefail

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; DIM=$'\033[0;2m'; RESET=$'\033[0m'
PASS=0; FAIL=0; WARN=0

chk_pass() { printf "  %s✓%s %s\n" "$GREEN" "$RESET" "$1"; PASS=$((PASS+1)); }
chk_fail() { printf "  %s✗%s %s\n" "$RED" "$RESET" "$1"; FAIL=$((FAIL+1)); }
chk_warn() { printf "  %s!%s %s\n" "$YELLOW" "$RESET" "$1"; WARN=$((WARN+1)); }

echo
echo "macOS 小键盘修复 — 状态自检"
echo "─────────────────────────────────────────────"

# 1. 应用
printf "\n1. Karabiner-Elements\n"
if [ -d /Applications/Karabiner-Elements.app ]; then
    V=$(defaults read /Applications/Karabiner-Elements.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "?")
    chk_pass "已安装 (版本 $V)"
else
    chk_fail "未安装"
fi

# 2. 服务
printf "\n2. 后台服务\n"
if launchctl print system 2>/dev/null | grep -q "org.pqrs.service.daemon.Karabiner-Core-Service"; then
    chk_pass "Core-Service 已注册"
else
    chk_fail "Core-Service 未注册"
fi
if launchctl print system 2>/dev/null | grep -q "Karabiner-VirtualHIDDevice-Daemon"; then
    chk_pass "VirtualHIDDevice-Daemon 已注册"
else
    chk_fail "VirtualHIDDevice-Daemon 未注册"
fi

CLI="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
if [ -x "$CLI" ] && "$CLI" --list-system-variables >/dev/null 2>&1; then
    chk_pass "core_service 通信正常"
elif [ -x "$CLI" ]; then
    chk_fail "core_service 通信失败 (重启后重试)"
fi

# 3. 权限
printf "\n3. 权限\n"
PF="$(ls "$HOME/.local/share/karabiner/tmp/"*.json 2>/dev/null | head -1)"
if [ -n "$PF" ]; then
    case "$(cat "$PF")" in
        *'"accessibility_process_trusted":true'*) chk_pass "辅助功能权限" ;;
        *) chk_fail "辅助功能权限未授予 → 系统设置 > 隐私与安全性 > 辅助功能" ;;
    esac
    case "$(cat "$PF")" in
        *'"iohid_listen_event_allowed":true'*) chk_pass "HID 监听权限" ;;
        *) chk_fail "HID 监听权限未授予 → 系统设置 > 隐私与安全性 > 输入监控" ;;
    esac
else
    chk_warn "未找到权限状态文件 (Karabiner 可能未运行)"
fi

# 4. 规则
printf "\n4. 映射规则\n"
CFG="$HOME/.config/karabiner/karabiner.json"
if [ -f "$CFG" ]; then
    # 统计"规则条数"与"操纵器(实际映射)条数"
    COUNTS=$(python3 -c "
import json,os
try:
    d=json.load(open(os.path.expanduser('$CFG')))
    p=next((x for x in d.get('profiles',[]) if x.get('selected')),None)
    rules=p.get('complex_modifications',{}).get('rules',[]) if p else []
    print(len(rules), sum(len(r.get('manipulators',[])) for r in rules))
except Exception:
    print(0, 0)
" 2>/dev/null || echo "0 0")
    NRULES=$(echo "$COUNTS" | awk '{print $1}')
    NMAPS=$(echo "$COUNTS" | awk '{print $2}')
    if [ "${NMAPS:-0}" -ge 11 ] 2>/dev/null; then
        chk_pass "已加载 $NRULES 条规则 / $NMAPS 个映射 (预期 ≥11 个映射)"
    elif [ "${NRULES:-0}" -gt 0 ] 2>/dev/null; then
        chk_warn "映射数 $NMAPS 少于预期 11, 运行 install.sh 补齐"
    else
        chk_fail "未找到映射规则, 运行 install.sh 安装"
    fi
else
    chk_fail "配置文件不存在"
fi

# 5. 虚拟 HID
printf "\n5. 虚拟 HID 驱动\n"
if ls -d /Library/SystemExtensions/*/org.pqrs.Karabiner-DriverKit-VirtualHIDDevice.dext >/dev/null 2>&1; then
    chk_pass "DriverKit 虚拟 HID 扩展已加载"
else
    chk_fail "虚拟 HID 扩展未加载 (需重启系统)"
fi

# 6. 冲突检查
printf "\n6. 冲突检查\n"
M=$(hidutil property --get UserKeyMapping 2>/dev/null | grep -c "HIDKeyboardUsage =" || true)
if [ "${M:-0}" -eq 0 ] 2>/dev/null; then
    chk_pass "hidutil 无残留映射 (无双重映射冲突)"
else
    chk_warn "hidutil 存在 $M 条映射, 可能与 Karabiner 双重生效"
    printf "    %s清空命令: hidutil property --set '{\"UserKeyMapping\":[]}'%s\n" "$DIM" "$RESET"
fi

printf "\n─────────────────────────────────────────────\n"
printf "通过 %s%d%s  失败 %s%d%s  警告 %s%d%s\n" \
    "$GREEN" "$PASS" "$RESET" "$RED" "$FAIL" "$RESET" "$YELLOW" "$WARN" "$RESET"

if [ "$FAIL" -eq 0 ]; then
    printf "\n%s状态良好%s — 到 TextEdit 里按小键盘 1 2 3 验证实际效果\n" "$GREEN" "$RESET"
else
    printf "\n%s存在失败项%s — 运行 ./scripts/install.sh 修复\n" "$RED" "$RESET"
fi
echo
