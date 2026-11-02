#!/usr/bin/env bash
#
# 环境信息采集 —— 用于复现问题与向上游/社区求助时提供完整上下文
#
#   ./scripts/diagnose.sh > diagnose-report.txt
#
set -uo pipefail

BAR="────────────────────────────────────────────────────────"

echo "macOS 小键盘问题诊断信息"
echo "采集时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "$BAR"

echo
echo "【系统】"
echo "  产品名称 : $(sw_vers -productName)"
echo "  系统版本 : $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
echo "  内核版本 : $(uname -r)"
echo "  架构     : $(uname -m)"
echo "  运行时长 : $(uptime | sed 's/.*up //;s/,.*users.*//')"

echo
echo "【硬件】"
echo "  机型     : $(sysctl -n hw.model)"
echo "  芯片     : $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Apple Silicon')"
echo "  CPU 核心 : $(sysctl -n hw.ncpu)"
echo "  内存     : $(( $(sysctl -n hw.memsize) / 1073741824 )) GB"

echo
echo "【输入设备】"
hidutil list 2>/dev/null | awk 'NR==1 || /Keyboard|keyboard/' | sed 's/^/  /'
echo
echo "  USB 设备:"
ioreg -l -w0 -r -c IOUSBDevice 2>/dev/null \
  | grep -E '"USB Product Name"|"USB Vendor Name"|"locationID"' \
  | grep -E 'Keyboard|Logitech|Hub|locationID' | sort -u | sed 's/^/    /'

echo
echo "【辅助功能 / 输入相关设置】"
for k in mouseKey slowKey stickyKey; do
    V=$(defaults read com.apple.universalaccess "$k" 2>/dev/null)
    [ -n "$V" ] && echo "  $k = $V" || echo "  $k = (未设置, 默认关闭)"
done
echo "  useMouseKeysShortcutKeys = $(defaults read com.apple.universalaccess useMouseKeysShortcutKeys 2>/dev/null || echo '(未设置)')"

echo
echo "【Num Lock 状态】"
if command -v python3 >/dev/null 2>&1; then
    cat > /tmp/_nlchk.swift <<'SWIFT'
import Cocoa
print("  macOS 视角 NumLock = \(CGEventSource.keyState(.hidSystemState, key: CGKeyCode(71)) ? "ON" : "OFF")")
SWIFT
    if swiftc -O /tmp/_nlchk.swift -o /tmp/_nlchk 2>/dev/null; then
        /tmp/_nlchk
    else
        echo "  (无法编译探测程序)"
    fi
    rm -f /tmp/_nlchk /tmp/_nlchk.swift
fi

echo
echo "【hidutil 键位映射】"
hidutil property --get UserKeyMapping 2>/dev/null | sed 's/^/  /' || echo "  (读取失败)"

echo
echo "【Karabiner-Elements】"
if [ -d /Applications/Karabiner-Elements.app ]; then
    echo "  版本     : $(defaults read /Applications/Karabiner-Elements.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null)"
    echo "  进程     : $(pgrep -fl Karabiner 2>/dev/null | wc -l | tr -d ' ') 个"
    echo "  权限状态 : $(cat "$HOME/.local/share/karabiner/tmp/"*.json 2>/dev/null || echo '(无)')"
    echo "  规则数   : $(python3 -c "
import json,os
p=os.path.expanduser('~/.config/karabiner/karabiner.json')
try:
    d=json.load(open(p)); prof=next((x for x in d.get('profiles',[]) if x.get('selected')),None)
    rules=prof.get('complex_modifications',{}).get('rules',[]) if prof else []
    print(f'{len(rules)} 条规则 / {sum(len(r.get("manipulators",[])) for r in rules)} 个映射')
except Exception: print('(读取失败)')" 2>/dev/null)"
else
    echo "  未安装"
fi

echo
echo "【第三方键盘软件】"
for app in "Karabiner-Elements" "BetterTouchTool" "Logi Options+" "Logitech Options" "Hammerspoon" "Keyboard Maestro"; do
    if [ -d "/Applications/$app.app" ]; then echo "  已安装: $app"; fi
done
echo "  (以上为空表示未检测到)"

echo
echo "【输入法】"
defaults read com.apple.HIToolbox AppleSelectedInputSources 2>/dev/null | sed 's/^/  /'

echo
echo "$BAR"
echo "采集完成"
