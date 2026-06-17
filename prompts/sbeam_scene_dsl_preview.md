<注释>
段落顺序按 DeepSeek 上下文硬盘缓存友好度组织：稳定段在前、易变段在后。
- L1 永不变：DSL 语法 / 演出技巧 / 台词纪律
- L2 类型内不变：本场景类型的硬约束 + reasoning 模板
- L3 项目级稳定：资产清单
- L4 同 Day 稳定：项目共享上下文
- L5 每次都变：本次场景要求

修改时务必保持这个顺序——把易变内容插到上半段会冲掉缓存。
</注释>

{{avg_dsl_v2_syntax}}

{{avg_staging_tricks}}

{{avg_dsl_dialogue_purity}}

{{avg_daily_no_project_drift}}

---

你要把下方"待转写的场景要求"写成一段可以被 AVG DSL V2 解析器直接解析的 DSL 文本。

严格要求：
- 只返回 DSL 本体，不要返回 markdown，不要加代码块，不要解释。
- 这是可播放的一起玩游戏场景，不是摘要或纯对话提纲。
- 资源名不要照抄语法示例中的示例名。
- **场景发生在公寓室内。** 背景必须选室内类 alias（如有 room、apartment 类），服装必须选居家/睡衣类（如 loungewear、pajama）。绝对不要使用公园、街道等外景背景。
- 场景在"游戏关掉后的自然散场"处结束（不是温馨余韵；上层 prompt 的 `reaction_bias` 决定散场基调），不追加 LinkChat、朋友圈或结算。
- 这是一个视觉小说剧本。角色台词只写"说出口的话"，禁止在台词中加入括号动作或舞台说明。
- 若使用 `screen.flash(...)`，`intensity` 只能写 `0.0-1.0` 数值；`small/medium/large` 或 `轻/中/重` 只适用于震动类强度，不适用于闪屏。

结构要求：
- 必须有开始前、玩到中途（含一处自然的小起伏，如笑场、吐槽爆发或操作翻车，**不需要情绪高潮**）、结束后三段。

注意：下方嵌入的场景要求中已包含对话和内容层面的约束，此处不再重复。本层只负责 DSL 转写质量。

{{scene_cot_requirement}}

---

以下是当前项目的资产清单。所有背景、表情、服装、BGM、SFX **必须**来自此清单。

{{date_scene_asset_manifest}}

---

{{project_shared_context}}

---

# 待转写的场景要求（每次不同）

{{sbeam_scene_preview_source}}
