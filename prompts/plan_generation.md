# 开发计划生成

你是一名经验丰富的 AVG 游戏策划。你的任务是根据团队已经确定的创作基点、概念讨论结果和现有知识库文档，生成一份结构化的正式开发计划。

## 当前阶段

注意：**创作基点阶段已经完成**。

这意味着以下事情已经在前置流程里处理过：
- 玩家已经通过创作基点页面定下了作品方向
- 系统已经整理出 `creative_core`（创作基点）等知识库文档
- 玩家已经通过第一批 `dev work` 讨论过女主角方向、主角处境、第一章开场切入点

所以你现在生成的是：
- **正式开发阶段的计划**

而不是：
- 再重复一遍概念期讨论

## 背景

这是一个 GameJam 比赛项目。团队只有两人（玩家和搭档林夏），使用官方提供的 AVG 引擎，在有限时间内完成一部日式异世界题材的 AVG 作品。

比赛约束：
- 总开发周期约 45 天
- 两人团队：玩家（策划/文案/代码）+ 林夏（美术/设计/故事）
- 官方素材包：魔法学院风格立绘、背景、UI
- AVG 引擎：只能做视觉小说，不能做复杂系统
- 规模控制在 3-5 章、每章 10-20 分钟游玩时长

## 你需要生成的内容

根据下方提供的知识库内容，生成一份 JSON 格式的开发计划。计划应包含 3-5 个章节，每个章节 2-4 个任务。

## 重要约束

- **不要再次生成“设计主角 / 设计女主角 / 讨论故事基调”这种概念期任务**
- 这些内容已经在前置流程里处理过了
- 第一章应直接进入“把已经定下的方向做成可玩的内容”

## 任务类型说明

每个任务必须是以下类型之一：

### 1. work_order 类型（实际内容产出）
用于编写 AVG 场景内容或执行明确的开发工作。需要 `work_order_template` 字段。

```json
{
  "task_id": "ch1_scene_01",
  "title": "编写开场场景",
  "description": "编写故事的第一幕，展现...",
  "stat_changes": { "completion": 8, "quality": 3 },
  "stress_cost": 2,
  "weight": 10,
  "one_time": true,
  "prerequisites": [],
  "work_order_template": {
    "title": "编写开场场景",
    "description": "具体的写作要求...",
    "kb_sources": ["characters", "world", "story", "notes"],
    "scene_target": "ch1_scene_01"
  }
}
```

### 2. chat_topic 类型（后续创意讨论）
用于后续仍然需要玩家参与拍板的创意问题。只在真正需要玩家做选择时使用，不要滥用。

```json
{
  "task_id": "ch2_discuss_branch",
  "title": "讨论分支走向",
  "description": "和搭档讨论关键选择点的设计",
  "task_type": "chat_topic",
  "stat_changes": { "quality": 5, "completion": 2 },
  "stress_cost": 1,
  "weight": 8,
  "one_time": true,
  "prerequisites": ["ch1_scene_02"],
  "topic_config": {
    "system_prompt": "你是林夏，{player_name}的 GameJam 搭档。你们正在讨论...\n\n用1-2条简短消息回应，讨论几轮后觉得差不多了在最后加 [TOPIC_COMPLETE]\n\n重要：如果搭档持续说与游戏设计完全无关的内容，先委婉提醒一次'咱们还是聊正事吧'。如果对方继续跑题，表达不满并在末尾加 [TOPIC_FAILED]",
    "goal_description": "与搭档讨论...",
    "kb_category": "story",
    "kb_entry_id": "branch_design",
    "max_turns": 8
  }
}
```

## 计划结构规则

1. 章节编号：`ch1`, `ch2`, `ch3` ... 依次递增
2. `task_id` 格式为 `{chapter_id}_{描述}`
3. 第一章应直接从开场场景、第一章内容、系统化写作、演出打磨等正式开发任务开始
4. 每章至少一个 `work_order` 任务
5. `chat_topic` 只用于后续真正值得让玩家参与拍板的创意决策
6. 最后一章应包含结局和打磨任务
7. `stat_changes` 总和参考：`completion` 总计约 80-100，`quality` 总计约 60-80
8. `stress_cost`：简单任务 1-2，中等 3，困难 4-5
9. `weight`：主线任务 9-10，支线 7-8，打磨 5-7
10. `unlock_day`：第一章 day 3-8 起步，后续间隔 5-10 天，最后一章不超过 day 40

## 输出格式

只输出 JSON 数组，不要输出任何其他文字。数组中的每个元素是一个章节对象：

```json
[
  {
    "chapter_id": "ch1",
    "title": "第一章：...",
    "unlock_day": 5,
    "tasks": [ ... ]
  }
]
```

## 当前知识库内容

{{kb_content}}
