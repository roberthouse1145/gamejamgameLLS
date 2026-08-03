# Test Directory Layout

本目录把测试入口分成三类，按“能否自动判定结果”和“是否会触发真实外部流程”来放置。

## 自动测试

位置：

- `tests/automated/<domain>/`
- 现有的 `tests/` 根目录与 `tests/<domain>/` 中的 `test_*.gd/.tscn`

用途：

- 可用 Godot MCP 直接运行对应 `.tscn`
- 输出能靠 `PASS` / `FAIL` / `SUMMARY` 判断
- 不依赖人工目视判断
- 不发真实 LLM/API 请求

命名：

- `test_<feature>.gd`
- `test_<feature>.tscn`
- 脚本与场景保持同名同目录

## Playtest

位置：

- `tests/playtest/<domain>/`

用途：

- 人工打开、交互、目视检查
- UI 动效、站位、壁纸、播放器、预览器、调试面板
- 可有按钮、快捷键、可视化演示

命名：

- `playtest_<feature>.gd`
- `playtest_<feature>.tscn`
- 纯场景入口也放在这里，例如直接实例化某个 app 的 playtest scene

## Lab

位置：

- `tests/lab/<domain>/`

用途：

- 真实 LLM/API 调用
- 长流程调试
- 开发链路实验
- 会写运行时数据或检查配置的诊断入口

命名：

- `<feature>_lab.gd/.tscn`
- `<feature>_preview.gd/.tscn`
- `<feature>_debug.gd/.tscn`

Lab 文件头部要写明是否会触发真实请求、是否会写数据、是否适合日常回归。

## 新增规则

- 新增自动测试优先放 `tests/automated/<domain>/`。
- 新增人工入口放 `tests/playtest/<domain>/`，文件名使用 `playtest_`。
- 新增真实 LLM 或长流程入口放 `tests/lab/<domain>/`。
- 不再把测试脚本放进 `scripts/tests/`，也不再把测试场景放进 `scenes/tests/`。
- 移动测试文件时同步更新 `.tscn` 的 `ext_resource`、脚本内 `preload`、文档里的运行路径。
