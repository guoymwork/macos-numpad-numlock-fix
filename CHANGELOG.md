# 更新记录

## 2026-11-14

### 修复

- **无效键名修正**：`karabiner/numpad-fix.json` 中小数点映射的 `key_code` 由 `keypad_decimal`
  改为 `keypad_period`。`keypad_decimal` 不是 Karabiner 的合法 `key_code`，导入/校验时会报
  `unknown key_code`，导致小数点映射静默失效。
- **新增 Num Lock 屏蔽**：`keypad_num_lock` → `vk_none`，避免该键在虚拟机、远程桌面等应用里
  触发意外的 NumLock 状态切换。规则共 12 个映射。
- **规则文件格式**：`karabiner/numpad-fix.json` 改为标准可导入格式（`title` + `rules`），
  `assets/complex_modifications/numpad-fix.json` 现在可直接在 Karabiner UI 中启用/禁用。

### 脚本

- 适配 Karabiner-Elements 16.99+：
  - CLI 路径改为 `Contents/Helpers/karabiner_cli`，并保留旧版 `bin/` 回退
  - 不再手工复制 LaunchDaemon plist（v3 后台服务由官方 pkg 注册）
  - 使用 `--show-settings-window-guidance` 检查权限 / 驱动状态
- `install.sh` / `uninstall.sh` 按描述清理旧版规则，避免新旧规则叠加。
- `verify.sh` 预期映射数改为 12，并改用 CLI 状态接口。
- `diagnose.sh` 修正 Mouse Keys 的 preference key（`mouseDriver`）。

### 文档

- README 与 `docs/AI-PROMPT.md` 同步更新映射表、计数与校验方法。
- 增加 `karabiner_cli --lint-complex-modifications` 校验步骤。
- 修正失效的文档链接与不存在的 `scripts/install-hidutil.sh` 引用。

## 2026-11-02

- 初始版本：根因分析、Karabiner 方案、安装/卸载/自检脚本。
