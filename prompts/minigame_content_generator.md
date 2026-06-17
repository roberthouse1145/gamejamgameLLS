## 当前开发工单
标题：{{task_title}}
描述：{{task_description}}
目标场景：{{task_scene_target}}
演出约束：{{task_performance_context}}

## 当前小游戏类型
{{minigame_type}}

## 项目背景（知识库摘要 / 索引）
{{kb_context}}

## 生成要求
为这个小游戏生成可直接加载的结构化素材。
素材必须贴合当前开发工单和知识库摘要，但不要越权替玩家或系统决定高层设定。
如果需要确认 KB 全文，可以调用 `kb_read`；但最终回复不要提工具调用过程，只输出下方要求的 DSL。

{{type_specific_instructions}}

## 输出 DSL 模板
{{output_schema}}
