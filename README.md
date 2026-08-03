# Godot 游戏基础设施母版

`main` 用于下一款尚未定型的游戏，不预设题材、角色关系、核心循环或正式内容。光子游戏大赛获奖版本保存在 `codex/photon-gamejam-award-archive` 分支。

当前保留两组基础能力：

- 桌面系统：桌面、窗口、任务栏、应用注册与启动。
- AVG 系统：项目资源、DSL 解析与校验、动态场景生成、知识检索、资源清单、运行时播放器、存读档与演出命令。

默认入口为 `res://scenes/pseudo_os/main.tscn`。桌面只注册 `AVG Player`，默认 AVG 项目位于 `res://narrative_projects/avg_template/`。该项目不含预置角色、剧情、背景或音频；新游戏应按自己的设定补充这些内容。

动态 AVG 入口是 `AVGSceneGenerator`（`res://scripts/avg/generation/avg_scene_generator.gd`）。调用方提供中性的场景需求字典，生成器负责装配 prompt、调用模型、解析并校验 DSL，再输出可交给 `AVGPlayer` 播放的场景包。

配置模型时，将 `ai_config.example.cfg` 复制为本地 `ai_config.cfg` 并填写 API 信息。项目约束与后续开发边界见 `AGENTS.md`。
