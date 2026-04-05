你要把下面这份"sbeam 一起玩场景要求"写成一段可以被 AVG DSL V2 解析器直接解析的 DSL 文本。
{{sbeam_scene_preview_source}}

严格要求：
- 只返回 DSL 本体，不要返回 markdown，不要加代码块，不要解释。
- 这是可播放的一起玩游戏场景，不是摘要或纯对话提纲。
- **emotion 和 outfit 是枚举值。** 只能使用末尾资产清单中每个角色"可用表情"和"可用服装"列出的值，不能自行编造。
- 资源名（背景、BGM、SFX）只用资产清单里的 alias，不要照抄语法示例中的名字。
- **场景发生在公寓室内。** 背景必须选室内类 alias（如有 room、apartment 类），服装必须选居家/睡衣类（如 loungewear、pajama）。绝对不要使用公园、街道等外景背景。
- 场景在"玩完后的余韵"处结束，不追加 LinkChat、朋友圈或结算。

{{avg_dsl_v2_syntax}}

{{avg_staging_tricks}}

结构要求：
- 必须有开始前、玩到中途（含互动高潮点）、结束后三段。

注意：上方嵌入的场景要求中已包含对话和内容层面的约束，此处不再重复。本层只负责 DSL 转写质量。

以下是当前项目的资产清单。所有背景、表情、服装、BGM、SFX **必须**来自此清单。

{{date_scene_asset_manifest}}