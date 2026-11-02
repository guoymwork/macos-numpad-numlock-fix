# macOS 第三方键盘小键盘失效 —— AI 协作提示词

> **本文件用途**：把这个文件的内容完整粘贴给 AI，即可让 AI 快速接手同类问题，**避免走已验证无效的弯路**。
>
> **适用症状**：macOS 上外接 Windows 布局机械键盘，**解锁/登录界面小键盘正常**，但**登录进入桌面后小键盘数字键完全无反应**（或表现为方向键导航）。

---

## 角色设定

你是一位 macOS 输入系统（IOKit / IOHIDEventSystem / Quartz Event Services）方向的资深工程师。
用户有一台 Mac mini，接入了罗技 G610 全尺寸机械键盘，小键盘数字键在桌面会话中完全失效。

---

## 已确认的根因（不必重新推导，但需理解才能正确决策）

**macOS 从未支持第三方键盘的 Num Lock 状态机。**

- 桌面会话由用户空间 `IOHIDEventSystem` 接管输入。对非 Apple 键盘，Num Lock 状态**默认为 OFF**，
  且收到小键盘按键时会**主动复位**该状态（实测：置 ON 后 65 毫秒即回落 OFF）。
  处于 OFF 时，`Keypad 1..9` 被解释为 `Home / ↑ / PageUp / ← / → / End / ↓ / PageDown`，`.` → `Delete`。
- 解锁界面由 `loginwindow` 直接处理输入，**强制打开 Num Lock**，所以解锁界面一切正常。
  登录后输入权移交用户空间，Num Lock 随之 OFF，小键盘随即失效。

### 关键机制澄清（极易误判，务必理解）

**键盘上的 Num Lock 指示灯，与 macOS 的实际行为，是两套独立机制：**

| | 驱动来源 | 影响 |
|---|---|---|
| 键盘指示灯 | HID **输出报告（LED 状态）** | 宿主写什么，灯就亮什么 |
| macOS 行为 | macOS **自己维护的 Num Lock 状态机** | 决定小键盘是数字还是导航键 |

两者**完全解耦**。**直接向键盘写 LED 报告可以让灯亮起来，但 macOS 的行为不会改变。**
看到灯亮 ≠ Num Lock 生效 —— 这是本问题最大的误判陷阱。

---

## 已验证无效的方向（不要再尝试浪费时间）

以下路径**均已在真实环境中验证无效**，除非有明确的新证据，请直接跳到「推荐方案」。

### ❌ 1. 用软件点亮 Num Lock 灯

```swift
// 无效。灯会亮，行为不变。
var led = [UInt8]([0x01])   // bit0 = NumLock ON
IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, &led, 1)
```

同样无效的变体：写 `0x03`（NumLock+CapsLock）、写 `0x07`（全开）、或起一个守护进程每 2 秒写一次。
**灯亮 ≠ 生效**，这条路的本质缺陷是改错了对象（改硬件灯，而不是改系统状态机）。

### ❌ 2. `hidutil` 用户键位映射

```bash
# 无效。设置成功、条目可正常读回，但按键行为完全不变。
hidutil property --set '{"UserKeyMapping":[{"HIDKeyboardUsagePage":7,"HIDKeyboardUsage":89,"HIDKeyboardUsagePage2":7,"HIDKeyboardUsage2":30}]}'
```

HID usage 编号本身是**正确的**（`0x59`=Keypad 1、`0x1E`='1'），映射条目也能写入并读回，
但该机制对本机这台键盘固件不生效。走虚拟 HID 设备路径的方案更可靠。

> 附注：`hidutil` 的 JSON 必须是**单个参数**传入。
> `hidutil property --set UserKeyMapping '<json>'` 会报 `NSJSONSerialization Error 3840`，
> 必须写成 `hidutil property --set '<json>'`。

### ❌ 3. 调整 macOS 辅助功能设置

本环境中以下项**本就已经关闭**，无需再查：

- Mouse Keys（`com.apple.universalaccess` → `mouseKey`）
- Slow Keys（`slowKey`）
- Sticky Keys（`stickyKey`）
- `hidutil` 残留映射（`UserKeyMapping` 原本为空）

### ❌ 4. 期待手动按物理 Num Lock 键能解决

按下后**键盘灯会亮**（证明固件正常接收并上报），但 **macOS 行为不变**。
这恰好是最有说服力的根因证据：macOS 收到了该键，却拒绝改变自身状态机。

### ❌ 5. 依赖 `keyboardGetUnicodeString()` 判断是否修复

```swift
// 这个 API 是静态查表，对 keyCode 83 恒返回 '1'，与真实 Num Lock 状态无关。
event.keyboardGetUnicodeString(maxStringLength: 8, actualStringLength: &len, unicodeString: buf)
```

**用它做「是否已修复」的验证会得到假阳性结论。**

### ❌ 6. 用合成 CGEvent 验证硬件路径

```swift
// 无效：合成事件不经过 session event tap，无法验证真实硬件路径的转换结果。
CGEvent(keyboardEventSource: nil, virtualKey: 83, keyDown: true)!.post(tap: .cghidEventTap)
```

合成事件投递到 `.cghidEventTap` / `.cgSessionEventTap` 都不会被 `.cgSessionEventTap` 位置的
`CGEventTap` 捕获到，因此无法用「合成 → tap 捕获」的方式做端到端对照。

---

## 可靠的验证方法（只认这几种）

### ✅ 唯一可信的证据：keyCode 本身

用 `CGEventTap`（位置 `.cgSessionEventTap`、`.headInsertEventTap`）监听**真实硬件按键**，
观察到达应用层的 keyCode：

| 观测到的 keyCode | 结论 |
|---|---|
| `83`（`kVK_ANSI_Keypad1`） | 未被转成导航键，映射生效 |
| `115`（Home）/ `119`（End）/ `116`（PageUp） | 被 Num Lock 状态机转成了导航键 |

**注意：`CGEventTap` 必须让 run loop 转起来才会收到事件。**

```swift
let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                       options: .defaultTap, eventsOfInterest: mask, callback: cb, userInfo: ...)
src = CFMachPortCreateRunLoopSource(nil, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .defaultMode)
CGEvent.tapEnable(tap: tap, enable: true)
CFRunLoopRunInMode(.defaultMode, 7200, false)   // ← 必须有这行，否则收不到事件
```

### ✅ 轮询 Num Lock 状态

```swift
CGEventSource.keyState(.hidSystemState, key: CGKeyCode(71))   // 71 = kVK_ANSI_NumLock
```

用它观测「系统是否主动复位」——这是判定根因的直接证据。

### ✅ 读键盘固件上报的原始 usage

```swift
// 注册 IOHIDDeviceRegisterInputValueCallback，监听 UsagePage 0x07 的事件。
// 若能抓到 usage 89/90/91…，说明键盘固件上报正常，问题在系统侧。
```

> 注意：G610 有两个 HID 集合 —— 65 字节的是标准 boot keyboard（LED 输出报告 Report ID 0、
> 1 字节、usage 1/2/3），119 字节的是 Logitech 厂商集合。写 LED 要找前者。

### ✅ 写日志文件时注意缓冲

用 Swift `print()` 写到非 TTY 会缓冲，日志迟迟不出现。改为显式写文件：

```swift
let d = (s + "\n").data(using: .utf8)!
if let fh = FileHandle(forWritingAtPath: path) {
    fh.seekToEndOfFile(); fh.write(d); try? fh.close()
} else {
    FileManager.default.createFile(atPath: path, contents: d)
}
```

---

## 推荐方案（已验证有效，直接执行）

### 方案 A：Karabiner-Elements（推荐，开机自生效）

在虚拟 HID 键盘层把小数键盘数字键改写为主键盘数字键，**在 Num Lock 判定之前**完成改写。

规则（11 条）：

```json
{
  "description": "小键盘数字键始终输出数字 (绕过 macOS NumLock 状态机)",
  "manipulators": [
    { "type": "basic", "from": { "key_code": "keypad_1",       "modifiers": { "optional": ["any"] } }, "to": [ { "key_code": "1" } ] },
    { "type": "basic", "from": { "key_code": "keypad_2",       "modifiers": { "optional": ["any"] } }, "to": [ { "key_code": "2" } ] },
    { "type": "basic", "from": { "key_code": "keypad_3",       "modifiers": { "optional": ["any"] } }, "to": [ { "key_code": "3" } ] },
    { "type": "basic", "from": { "key_code": "keypad_4",       "modifiers": { "optional": ["any"] } }, "to": [ { "key_code": "4" } ] },
    { "type": "basic", "from": { "key_code": "keypad_5",       "modifiers": { "optional": ["any"] } }, "to": [ { "key_code": "5" } ] },
    { "type": "basic", "from": { "key_code": "keypad_6",       "modifiers": { "optional": ["any"] } }, "to": [ { "key_code": "6" } ] },
    { "type": "basic", "from": { "key_code": "keypad_7",       "modifiers": { "optional": ["any"] } }, "to": [ { "key_code": "7" } ] },
    { "type": "basic", "from": { "key_code": "keypad_8",       "modifiers": { "optional": ["any"] } }, "to": [ { "key_code": "8" } ] },
    { "type": "basic", "from": { "key_code": "keypad_9",       "modifiers": { "optional": ["any"] } }, "to": [ { "key_code": "9" } ] },
    { "type": "basic", "from": { "key_code": "keypad_0",       "modifiers": { "optional": ["any"] } }, "to": [ { "key_code": "0" } ] },
    { "type": "basic", "from": { "key_code": "keypad_decimal", "modifiers": { "optional": ["any"] } }, "to": [ { "key_code": "period" } ] }
  ]
}
```

**刻意不映射** `keypad_enter` / `keypad_plus` / `keypad_minus` / `keypad_multiply` / `keypad_divide`
—— Excel 等表格软件依赖小键盘回车。

写入位置（两个都写，UI 可见且实际生效）：

- `~/.config/karabiner/karabiner.json` → `profiles[0].complex_modifications.rules`
- `~/.config/karabiner/assets/complex_modifications/numpad-fix.json`

### 方案 B：自建 CGEventTap 拦截器（零第三方依赖的备选）

在 `.cgSessionEventTap` 拦截并改写 keyCode：

```swift
// 小键盘 keyCode -> 主键盘 keyCode
let map: [Int: Int] = [
    83: 18, 84: 19, 85: 20, 86: 21, 87: 22, 88: 23, 89: 24,
    91: 25, 92: 26, 82: 29, 65: 47
]
// 命中后改写 keyCode 并清除 maskNumericPad 标志
event.setIntegerValueField(CGEventField(rawValue: 30)!, value: Int64(target))
event.flags = event.flags.remove(.maskNumericPad)
```

**前提**：该程序必须在「系统设置 → 隐私与安全性 → 辅助功能」中被授权，否则 `CGEvent.tapCreate` 直接返回 nil。

---

## 执行环境注意事项（沙箱/权限受限场景）

在 AI 助手或自动化环境中操作时，以下方式可用：

| 需求 | 可行做法 | 不可行 |
|---|---|---|
| 安装 GUI 应用 | `curl` 下载官方 DMG → `hdiutil attach` → `open xxx.pkg` 走图形安装向导 | `brew install --cask`（可能被沙箱拦） |
| 提权操作 | `osascript -e 'do shell script "..." with administrator privileges'` 触发系统密码弹窗 | `sudo`（沙箱内 `operation not permitted`） |
| 加载系统服务 | 同上，通过提权的 `do shell script` 执行 `launchctl bootstrap system` | `launchctl bootstrap` 直接调用（`Bootstrap failed: 5`） |
| 写用户级配置 | 直接文件操作 | — |

### Karabiner 特有的坑

1. **LaunchDaemon plist 的真实文件名带 `-Daemon` 后缀**：
   `org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon.plist`
   （不是 `...Karabiner-VirtualHIDDevice.plist`）

2. **必须先装守护进程，Karabiner 才能工作**。只装 App 不装 LaunchDaemon 时，
   `karabiner_cli --list-system-variables` 会报 `asio.system:13`，
   日志里满是 `core_service_daemon_client connect_failed`。

3. **权限状态校验文件**：`~/.local/share/karabiner/tmp/*.json`

   ```json
   {"accessibility_process_trusted":true,"iohid_listen_event_allowed":true}
   ```

   两个字段都必须为 `true`。

4. **虚拟 HID 驱动是 DriverKit 扩展**：
   `/Library/SystemExtensions/*/org.pqrs.Karabiner-DriverKit-VirtualHIDDevice.dext`

5. **配置写入后需重载**：

   ```bash
   launchctl kickstart -k system/org.pqrs.service.daemon.Karabiner-Core-Service
   ```

---

## 建议的执行顺序

1. **先做 30 秒确认**（避免在错误前提上耗时）：
   - 问用户：主键盘 A 键正常吗？→ 正常则基本可锁定为小键盘专属问题
   - 问用户：按物理 Num Lock 键，灯亮吗？亮但小键盘仍无反应 → 根因确认，无需再排查
2. **直接上 Karabiner**（本仓库 `scripts/install.sh` 已封装全部步骤）
3. **验证**：用 `CGEventTap` 确认应用层收到 `keyCode=83`；或直接在 TextEdit 里试按
4. **确认无冲突**：清空 `hidutil` 映射后复测，若仍正常 → 确认 Karabiner 是唯一生效路径

---

## 交付要求（若用户要求产出仓库）

一个可复用项目应包含：

| 文件 | 内容 |
|---|---|
| `README.md` | 现象、环境、根因、方案、取舍、排查、卸载 |
| `docs/AI-PROMPT.md` | 本文件，供其它 AI 复用 |
| `karabiner/` | Karabiner 规则模板（`numpad-fix.json`） |
| `scripts/install.sh` | 一键安装（含提权、守护进程、规则写入） |
| `scripts/uninstall.sh` | 一键卸载 |
| `scripts/verify.sh` | 状态自检（进程 / 权限 / 规则 / 服务） |
| `scripts/diagnose.sh` | 环境信息采集，便于复现与上报 |
| `LICENSE` | MIT |

**写 README 时不要罗列失败尝试的过程** —— 只写现象、根因、最终方案。
把弯路统一收进 `docs/AI-PROMPT.md` 的「已验证无效的方向」，供 AI 查阅即可。
