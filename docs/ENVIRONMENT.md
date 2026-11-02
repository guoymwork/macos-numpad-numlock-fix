# 环境条件

本问题在以下环境中复现并验证修复有效。**根因是 macOS 的通用行为，与具体硬件无关**，
但不同固件对各类方案的兼容性可能有差异，因此记录在此供参考。

## 验证环境

| 类别 | 项目 | 规格 |
|---|---|---|
| **主机** | 机型 | Mac mini (Macmini9,1) |
| | 芯片 | Apple M1 |
| | CPU / 内存 | 8 核 / 16 GB |
| **系统** | 版本 | macOS 26.7.2 (Build 25G332) |
| | 内核 | Darwin 25.6.0 |
| | 架构 | arm64 |
| **键盘** | 型号 | 罗技 G610 (Gaming Keyboard G610) |
| | 轴体 | Cherry MX 茶轴 |
| | 布局 | 全尺寸，带小键盘，独立 Num Lock 键 |
| | 连接方式 | USB 有线（经 GenesysLogic USB 3.2 Hub） |
| | 序列号 | `1869315E3932` |
| | locationID | `0x2120000` (34734080) |
| **鼠标** | 型号 | 罗技 G502 HERO |
| **扩展坞** | 芯片 | GenesysLogic USB 3.2 Hub |
| **软件** | 输入法 | 简体拼音（SCIM Shuangpin） |
| | 第三方键盘软件 | 无 |
| | 辅助功能 | Mouse Keys / Slow Keys / Sticky Keys 均关闭 |
| **Karabiner** | 版本 | 16.3.0 |

## 键盘 HID 结构

G610 暴露两个 HID 集合，这点在排查时很关键：

### 集合 #1 — 厂商自定义（119 字节描述符）

```
Usage Page 0xFF43 (Logitech vendor)
用途: 媒体键 / G 键 / 游戏模式 / 背光
```

### 集合 #2 — 标准 boot keyboard（65 字节描述符）

```
Usage Page 0x06 (Generic Desktop) / Usage 0x06 (Keyboard)
Usage Page 0x07 (Keyboard)      Usage Min 0x00, Usage Max 0xFF
Usage Page 0x08 (LED)           Usage 1/2/3, Report ID 0, 1 byte, Output
Input:  6 bytes (Report Size 8, Report Count 6)
```

- 键位 usage 范围 `0x00–0xFF`，**完整包含小键盘区与 NumLock**，固件无键位缺失
- LED 输出报告：Report ID `0`，1 字节 bitmask
  - bit0 = NumLock
  - bit1 = CapsLock
  - bit2 = ScrollLock

> 排查时的实用结论：读取键盘 LED 状态、或往键盘写 LED 报告，都必须找 **65 字节的那个集合**。
> 119 字节的厂商集合不承载标准键盘功能。

### HID usage 编号速查（Keyboard/Keypad Page 0x07）

| Usage | 键 | Usage | 键 |
|---|---|---|---|
| `0x1E` / 30 | `1` | `0x59` / 89 | Keypad 1 |
| `0x1F` / 31 | `2` | `0x5A` / 90 | Keypad 2 |
| `0x20` / 32 | `3` | `0x5B` / 91 | Keypad 3 |
| `0x21` / 33 | `4` | `0x5C` / 92 | Keypad 4 |
| `0x22` / 34 | `5` | `0x5D` / 93 | Keypad 5 |
| `0x23` / 35 | `6` | `0x5E` / 94 | Keypad 6 |
| `0x24` / 36 | `7` | `0x5F` / 95 | Keypad 7 |
| `0x25` / 37 | `8` | `0x60` / 96 | Keypad 8 |
| `0x26` / 38 | `9` | `0x61` / 97 | Keypad 9 |
| `0x27` / 39 | `0` | `0x62` / 98 | Keypad 0 |
| `0x37` / 55 | `.` | `0x63` / 99 | Keypad `.` |
| `0x53` / 83 | NumLock | `0x35` / 53 | Keypad Enter |

### macOS Virtual KeyCode（CGEvent 层）

与上表的 HID usage **是两套独立编号**，注意不要混用：

| KeyCode | 常量 | KeyCode | 常量 |
|---|---|---|---|
| 18 | `kVK_ANSI_1` | 83 | `kVK_ANSI_Keypad1` |
| 19 | `kVK_ANSI_2` | 84 | `kVK_ANSI_Keypad2` |
| 20 | `kVK_ANSI_3` | 85 | `kVK_ANSI_Keypad3` |
| 21 | `kVK_ANSI_4` | 86 | `kVK_ANSI_Keypad4` |
| 22 | `kVK_ANSI_5` | 87 | `kVK_ANSI_Keypad5` |
| 23 | `kVK_ANSI_6` | 88 | `kVK_ANSI_Keypad6` |
| 24 | `kVK_ANSI_7` | 89 | `kVK_ANSI_Keypad7` |
| 25 | `kVK_ANSI_8` | 91 | `kVK_ANSI_Keypad8` |
| 26 | `kVK_ANSI_9` | 92 | `kVK_ANSI_Keypad9` |
| 29 | `kVK_ANSI_0` | 82 | `kVK_ANSI_Keypad0` |
| 47 | `kVK_ANSI_Period` | 65 | `kVK_ANSI_KeypadDecimal` |
| 71 | `kVK_ANSI_NumLock` | 76 | `kVK_ANSI_KeypadEnter` |

## 兼容性说明

**Karabiner-Elements 方案不依赖具体键盘型号** —— 它创建虚拟 HID 设备，在事件流最前端改写 keycode，
对所有能上报标准小键盘 usage 的设备都适用。

若你的键盘不是标准 PC 布局，请用 `scripts/diagnose.sh` 采集 `hidutil list` 输出，
确认小键盘区的 usage 后再编写规则。

其他第三方键盘可参考：

| 键盘 | 已知情况 |
|---|---|
| 罗技 G610 / G810 / G910 | ✅ 本仓库验证环境 |
| 任意带独立 Num Lock 键的 USB 机械键盘 | 预期同样适用 |
| 苹果妙控键盘（带数字键盘） | ❌ 不适用 —— 该键盘小键盘恒为数字模式，无此问题 |

---

返回 [README](../README.md)
