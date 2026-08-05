# 未命名游戏

`main` 就是新游戏本体。游戏题材、角色关系和核心循环尚未确定；光子游戏大赛获奖版本保存在 `codex/photon-gamejam-award-archive` 分支。

当前保留两组基础能力：

- 桌面系统：桌面、窗口、任务栏、应用注册与启动。
- AVG 系统：游戏数据、DSL 解析与校验、动态场景生成、知识检索、资源清单、运行时播放器、存读档与演出命令。

游戏唯一入口为 `res://scenes/game/main.tscn`；桌面基础设施场景为 `res://scenes/pseudo_os/desktop.tscn`。游戏唯一的 AVG 数据位于 `res://resources/avg/game_data.tres`，素材别名位于 `res://resources/avg/asset_aliases.json`，剧情知识位于 `res://resources/avg/knowledge_base.json`。仓库不提供项目切换、项目模板或 `narrative_projects/` 目录。

动态 AVG 入口是 `AVGSceneGenerator`（`res://scripts/avg/generation/avg_scene_generator.gd`）。调用方提供中性的场景需求字典，生成器负责装配 prompt、调用模型、解析并校验 DSL，再输出可交给 `AVGPlayer` 播放的场景包。

配置模型时，将 `ai_config.example.cfg` 复制为本地 `ai_config.cfg` 并填写 API 信息。项目约束与后续开发边界见 `AGENTS.md`。
