# macOS 第三方键盘小键盘失效修复

在 macOS 上，外接 Windows 布局机械键盘的**小键盘数字键完全无法输入数字**，但在解锁/登录界面却一切正常。

本仓库记录这一问题的完整根因分析、经过验证的解决方案，以及可复用的安装脚本与 AI 协作提示词。

---

## 目录

- [问题现象](#问题现象)
- [环境条件](#环境条件)
- [根因分析](#根因分析)
- [解决方案](#解决方案)
- [快速开始](#快速开始)
- [工作原理](#工作原理)
- [设计取舍](#设计取舍)
- [故障排查](#故障排查)
- [卸载](#卸载)
- [参考资料](#参考资料)

---

## 问题现象

| 场景 | 小键盘表现 |
|---|---|
| 解锁 / 登录界面（`loginwindow`） | ✅ 正常，可输入数字 |
| 桌面会话（登录后的用户环境） | ❌ 数字键完全无反应 |
| 同一键盘的主键盘区域 | ✅ 正常 |

其他特征：

- 按下键盘上的**物理 Num Lock 键**，键盘上的 Num Lock 指示灯会亮，但小键盘仍然无反应
- 无任何第三方键盘管理软件介入
- 输入法为中文双拼，不是全角/半角干扰

---

## 环境条件

**这是问题复现与验证的具体环境**，其他环境可能存在差异，但根因一致。

### 硬件

| 项目 | 规格 |
|---|---|
| 主机 | Mac mini (Macmini9,1)，Apple M1，8 核，16 GB 内存 |
| 键盘 | 罗技 G610（Gaming Keyboard G610），Cherry MX 茶轴，全尺寸带小键盘，**USB 有线** |
| 鼠标 | 罗技 G502 HERO |
| 扩展坞 | GenesysLogic USB 3.2 Hub（键盘经此接入） |
| 键盘连接 | USB，`locationID 0x2120000`，序列号 `1869315E3932` |

### 软件

| 项目 | 版本 |
|---|---|
| 操作系统 | macOS 26.7.2 (Build 25G332)，Darwin 内核 25.6.0，arm64 |
| 输入法 | 简体拼音（SCIM Shuangpin） |
| 第三方键盘软件 | 无（Karabiner / BetterTouchTool / Logi Options 均未安装） |
| 辅助功能 | Mouse Keys / Slow Keys / Sticky Keys 全部关闭 |

### 键盘 HID 描述符要点

G610 暴露两个 HID 集合：

| 集合 | 描述符长度 | 性质 |
|---|---|---|
| #1 | 119 字节 | Logitech 厂商自定义集合（`Usage Page 0xFF43`），媒体键 / G 键 / 游戏模式 |
| #2 | **65 字节** | **标准 boot keyboard 集合**，LED 输出报告 Report ID 0、1 字节、usage 1/2/3（NumLock / CapsLock / ScrollLock） |

boot keyboard 集合的键位 usage 范围为 `0x00–0xFF`，包含完整的小键盘区（`0x59–0x63`）与 NumLock（`0x53`），**固件上报完整、无键位缺失**。

---

## 根因分析

### 结论

**macOS 从未支持第三方键盘的 Num Lock 状态机。**

macOS 对非 Apple 键盘的 Num Lock 处理与 Windows 有本质差异：

- **Windows**：Num Lock 是键盘固件内的状态，宿主系统读取键盘上报的 LED 状态位，据此把小键盘 usage 解释为「数字」或「导航键」。
- **macOS**：桌面会话由用户空间的 HID 事件系统（`IOHIDEventSystem`）接管。对第三方键盘，**Num Lock 状态默认置为 OFF**，且在收到小键盘按键时会主动复位该状态。此时小键盘的 `Keypad 1..9` 被解释为 `Home / ↑ / PageUp / ← / → / End / ↓ / PageDown`，`.` 被解释为 `Delete`。

### 为什么解锁界面能用

`loginwindow` 由系统直接处理键盘输入，**会强制打开 Num Lock**（以便用户能用数字键盘输入密码）。登录完成后输入处理权移交给用户空间的 HID 事件系统，Num Lock 随之被置为 OFF，小键盘随即失效。

### 决定性证据

1. **状态复位观测**：连续轮询 `CGEventSource.keyState(.hidSystemState, key: 71)`，捕获到 Num Lock 由 OFF 变为 ON 后**仅 65 毫秒即被系统自动复位为 OFF**。该复位由系统发起，与用户操作无关。
2. **物理 Num Lock 键测试**：按下键盘上的 Num Lock 键，**键盘指示灯会亮**（证明键盘固件正常接收并上报了该键），但 macOS 的行为完全不变——说明 macOS 收到了该键，却拒绝改变自身状态机。
3. **区域对照测试**：同一键盘的主键盘 A 键正常工作，仅小键盘区域失效，排除输入法、辅助功能、第三方软件等全局性因素。

### 一个必须澄清的机制

**键盘上的 Num Lock 指示灯，与 macOS 的实际行为，是两套独立机制。**

- 指示灯由 HID **输出报告（LED 状态）**驱动 —— 宿主写什么，灯就亮什么
- macOS 判断小键盘是数字还是导航键，用的是**它自己维护的 Num Lock 状态机**

两者完全解耦。**直接向键盘写 LED 报告可以让灯亮起来，但 macOS 的行为不会改变。** 这是本问题最容易误判的地方：看到灯亮了，容易误以为「Num Lock 已开启」，实际上系统侧仍处于 OFF 状态。

---

## 解决方案

用 **Karabiner-Elements** 在虚拟 HID 键盘层，把小键盘数字键改写为主键盘数字键，**完全绕开 macOS 的 Num Lock 状态机**。

```
keypad_1 … keypad_9  →  1 … 9
keypad_0             →  0
keypad_decimal       →  period
```

共 11 条规则。

**刻意不映射** `keypad_enter` / `keypad_plus` / `keypad_minus` / `keypad_multiply` / `keypad_divide` —— 保留小键盘语义，Excel 等表格软件依赖小键盘回车。

### 为什么是 Karabiner 而不是别的方案

| 方案 | 结果 | 原因 |
|---|---|---|
| 手动按物理 Num Lock 键 | ❌ 无效 | 键盘灯会亮，但 macOS 状态机仍为 OFF |
| 软件周期写 LED 报告点灯 | ❌ 无效 | 灯亮 ≠ 行为改变，两套机制解耦 |
| `hidutil` 用户键位映射 | ❌ 无效 | 设置成功、条目可读回，但按键行为不变 |
| 禁用 Mouse Keys 等辅助功能 | ❌ 无效 | 这些功能本就未启用 |
| **Karabiner-Elements 虚拟 HID 重映射** | ✅ **有效** | 在事件流最前端改写 keycode，不经过 Num Lock 判定逻辑 |

---

## 快速开始

```bash
# 1. 克隆本仓库
git clone https://github.com/guoymwork/macos-numpad-numlock-fix.git
cd macos-numpad-numlock-fix

# 2. 一键安装（自动处理 Karabiner 安装、权限、守护进程、规则写入）
./scripts/install.sh

# 3. 验证
./scripts/verify.sh
```

安装脚本会：

1. 检测并安装 Karabiner-Elements（若未安装，自动下载官方 DMG 并引导安装）
2. 安装 Core-Service 与 VirtualHIDDevice 两个 LaunchDaemon
3. 写入 11 条重映射规则到 `~/.config/karabiner/karabiner.json`
4. 检查辅助功能与 HID 监听权限状态
5. 输出验证指引

---

## 工作原理

```
物理按键 (G610 小键盘 1)
    │
    ▼
HID 报告 ──► G610 固件 (NumLock=OFF) ──► usage 0x59 (Keypad 1)
    │                                              │
    │                                              ▼
    │                                    ┌─────────────────────┐
    │                                    │  Karabiner 虚拟 HID  │  ← 在此改写
    │                                    │  Keypad 1 → '1'     │
    │                                    └─────────┬───────────┘
    │                                              │
    │                        macOS HID 事件系统    │  ← Num Lock 状态机
    │                        (此处会做 NumLock 判定)│     状态仍为 OFF，
    │                                              │     但已无 Keypad usage 可判定
    ▼                                              ▼
应用层 ◄───────────────────────────────────────────  keycode 18 ('1') + 数字字符
```

关键点：改写发生在 **Num Lock 判定之前**，因此 macOS 的状态机是 ON 还是 OFF 都无关紧要。

---

## 设计取舍

### 为什么不用 `hidutil`

`hidutil property --set UserKeyMapping` 理论上也能做 HID 层重映射，且零依赖、无需管理员权限。但在本次环境中实测**设置成功、条目可正常读回、按键行为却无变化** —— 该机制对部分键盘固件不生效。

Karabiner 走的是**虚拟 HID 设备**路径（创建虚拟键盘并在最前端拦截改写），与真实设备解耦，对固件差异不敏感，因此更可靠。

> 如果你的环境中 `hidutil` 有效，也可以只用它，无需安装 Karabiner。本仓库的 `scripts/install-hidutil.sh` 提供了这条路径。

### 规则文件的位置

规则写在两个位置，作用不同：

| 文件 | 作用 |
|---|---|
| `~/.config/karabiner/karabiner.json` | **实际生效**的规则（profile: Default） |
| `~/.config/karabiner/assets/complex_modifications/numpad-fix.json` | 导入型规则文件，可在 Karabiner UI 中勾选启用/禁用 |

两者都写入，确保 UI 中可见可管理，同时保证实际生效。

---

## 故障排查

### 小键盘仍无反应

按顺序检查：

```bash
# 1. Karabiner 是否在运行
pgrep -fl Karabiner

# 2. 权限是否授予（两个都必须是 true）
cat ~/.local/share/karabiner/tmp/*json

# 3. 规则是否已加载
python3 -c "import json;print(len(json.load(open('$HOME/.config/karabiner/karabiner.json'))['profiles'][0]['complex_modifications']['rules']))"

# 4. 后台服务是否注册
launchctl print system | grep -i karabiner
```

### 修改规则

编辑 `~/.config/karabiner/karabiner.json` 中的 `rules` 数组，保存后 Karabiner 会自动重载。也可以直接用 UI：

```bash
open -a Karabiner-Elements
```

### 保留小键盘语义

若希望小键盘数字键仍被识别为「小键盘」（部分 Excel 场景需要），改用 `to` 中带 `key_code` + 保留原始 usage 的写法，或只对小键盘**运算符**做扩展映射，数字键交由系统处理。

---

## 卸载

```bash
./scripts/uninstall.sh
```

或手动：

```bash
# 移除规则
python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.path.expanduser("~/.config/karabiner/karabiner.json"))
d = json.loads(p.read_text())
for prof in d.get("profiles", []):
    prof.get("complex_modifications", {}).pop("rules", None)
p.write_text(json.dumps(d, ensure_ascii=False, indent=2))
PY

# 移除守护进程（需管理员权限）
sudo rm -f /Library/LaunchDaemons/org.pqrs.service.daemon.Karabiner-Core-Service.plist \
           /Library/LaunchDaemons/org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon.plist
sudo launchctl bootout system/org.pqrs.service.daemon.Karabiner-Core-Service 2>/dev/null
```

---

## 参考资料

- [Karabiner-Elements 官网](https://karabiner-elements.pqrs.org/)
- [Karabiner-Elements 复杂修饰键文档](https://karabiner-elements.pqrs.org/document/complex_modifications)
- [Apple 官方：若数字小键盘不工作](https://support.apple.com/guide/mac-help/if-a-numeric-keypad-doesnt-work-mchlp2366/mac)
- [USB HID Usage Tables](https://usb.org/document-library/hid-usage-tables-1-6) — Keyboard/Keypad Page (0x07) usage 编号
- [Apple 开源：HIDEventSystem](https://github.com/apple-oss-distributions/hid)

---

## 许可

MIT
