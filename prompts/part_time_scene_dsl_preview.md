你要把下方"待转写的场景要求"写成一段可以被 AVG DSL V2 解析器直接解析的 DSL 文本。

严格要求：
- 只返回 DSL 本体，不要返回 markdown，不要加代码块，不要解释。
- 这是可播放的打工场景，不是摘要或纯对话提纲。
- 资源名不要照抄语法示例中的示例名。
- 场景在"下班收尾"处结束，不追加 LinkChat、朋友圈或结算。
- 如果场景里需要店员、顾客、路人、老人、小孩等陪衬角色，直接用 `TextBlock(speaker="店员")` 写对话即可，不需要 `stage.enter` / `stage.exit`。
- 这是一个视觉小说剧本。角色台词只写“说出口的话”，禁止在台词中加入括号动作或舞台说明。
- 若使用 `screen.flash(...)`，`intensity` 只能写 `0.0-1.0` 数值；`small/medium/large` 或 `轻/中/重` 只适用于震动类强度，不适用于闪屏。

{{avg_dsl_v2_syntax}}

{{avg_staging_tricks}}

结构要求：
- 必须有到岗、一起干活（含一处自然的小起伏，**不需要情绪高潮**）、下班收尾三段。

注意：下方嵌入的场景要求中已包含对话和内容层面的约束，此处不再重复。本层只负责 DSL 转写质量。

以下是当前项目的资产清单。所有背景、表情、服装、BGM、SFX **必须**来自此清单。

{{date_scene_asset_manifest}}

---

# 待转写的场景要求（每次不同）

{{part_time_scene_preview_source}}

{{scene_cot_requirement}}
