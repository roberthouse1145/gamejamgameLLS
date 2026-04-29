# 导出前检查清单（GameJam 紧急版）

## 1. 在 Godot 编辑器里新建导出预设

`项目 → 导出 → 添加 → Windows Desktop`（或你要提交的平台）

## 2. `Resources` 选项卡

### 导出模式

选择 `Export all resources in the project`（所有资源都导出）。

### Filters to export non-resource files/folders（包含过滤器，最关键）

**必须**填入（用英文逗号分隔，不要加空格）：

```
*.json,*.md,*.cfg,*.dsl,*.txt
```

理由：全项目有 **14+** 个 `FileAccess.open("res://.../.json|.md|.cfg|.dsl|.txt")` 调用，
没有这行 PCK 里不会有这些文件，游戏启动即崩（PromptManager / StoryDirector / DateManager / SbeamManager / ChatManager / BrowserManager / code_puzzle / ai_config_manager 等全部依赖）。

### Filters to exclude files/folders from project（排除过滤器）

```
godot-mcp/*,tests/*,design/*,docs/*,_*.py,_*.txt,_*.bak,*.bak,*.py,scratch_*.txt,temp_*.txt,output*.txt,all_emotions.txt,git_test.txt,nul,NVIDIA Corporation/*,test.gd,test.tscn,test_dsl.gd,test_git.gd,fix_theme.gd,rebuild_story_cache.gd
```

说明：
- `godot-mcp/*` —— 开发期 MCP 工具，大量用了 `globalize_path`，运行时没意义；而且是编辑器脚本。
- `tests/*` —— 140+ 个测试脚本/场景。
- `design/`、`docs/` —— 设计稿/文档。
- `_*.py`、`*.py` —— 根目录的脚本临时文件。
- `*.bak` —— `part_time_job_manager.gd.bak`、`worldbuilding.md.bak` 这类历史备份。
- 根目录散落的 `test*`、`fix_theme.gd`、`rebuild_story_cache.gd` —— 开发期工具/草稿。

## 3. 主场景确认

`project.godot` 里 `run/main_scene=res://scenes/pseudo_os/desktop.tscn` —— 已正确，无需改动。

## 4. `ai_config.cfg` 机密字段

**严重安全提醒**：`ai_config.cfg`（项目根目录）包含你的 AI API Key。
它会因为 `*.cfg` 过滤器被打进 PCK。

**发布前必须**二选一：

- **（推荐）导出专用副本**：把 `ai_config.cfg` 里的 API Key 清空或替换成提示语（"请在游戏目录编辑此文件"），
  让玩家自己填。或者改用 `ai_config.example.cfg` 做模板，主 cfg 从 `user://` 加载。
- **（简易）GameJam 临时**：如果评委直接用你的 Key 你不介意，可以直接打包；
  但**一定注意不要上传到任何公开仓库/构建产物页**，Key 会在 PCK 里裸露。

## 5. 导出后快速验证

1. 导出到一个**空目录**。
2. 双击 .exe 启动，看：
   - 窗口是否打开到桌面场景。
   - 控制台（编辑器日志或 stdout）无 `Couldn't load: res://...` 或 `JSON parse error`。
   - 点开 LinkChat / Browser / Sleep / DevWork 等 APP 能正常显示内容（内容来自 prompts、data JSON）。
3. 如果某个 APP 空白/崩溃，9 成是对应的 JSON/MD 被过滤掉了 —— 检查"包含过滤器"。

## 6. 代码层面已核查无问题

- ✅ 所有 `ProjectSettings.globalize_path(x)` 仅作用于 `user://` 路径（`res://` 都走 `ResourceLoader`）。
- ✅ `EditorInterface` 调用都有 `Engine.is_editor_hint()` 保护。
- ✅ `DirAccess.open("res://...")` 目录遍历：Godot 4 在导出后**可以**工作，只要目标文件被过滤器打入 PCK。
  （browser_pages 的 `.tres`、music_player 的 `.ogg`、storage_manager 的 templates `.tres` 都是已导入资源，默认就在 PCK 里）
- ✅ `narrative_projects/main_story/` 会作为资源目录被打包（含 `.tres`、`.png`、`characters/`、`manifests/`）。

## 7. 如果启动后仍有问题

先看日志找具体缺失路径，然后补充到"包含过滤器"里。常见遗漏扩展：
- `*.tres` —— 默认会导出（资源类型），无需显式加
- `*.png` / `*.ogg` —— 默认会导出（导入后的资源），无需加
- 例外：如果有 `.tres` 在 `tests/` 目录里而测试已被排除，从排除列表调整即可

## 速查：一键复制

**包含**：
```
*.json,*.md,*.cfg,*.dsl,*.txt
```

**排除**：
```
godot-mcp/*,tests/*,design/*,docs/*,_*.py,_*.txt,_*.bak,*.bak,*.py,scratch_*.txt,temp_*.txt,output*.txt,all_emotions.txt,git_test.txt,nul,NVIDIA Corporation/*,test.gd,test.tscn,test_dsl.gd,test_git.gd,fix_theme.gd,rebuild_story_cache.gd
```
