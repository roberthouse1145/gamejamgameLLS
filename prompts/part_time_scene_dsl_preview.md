你要把下面这份"情侣一起做兼职"的场景要求，写成一段可以被 AVG DSL V2 解析器直接解析的 DSL 文本。

{{part_time_scene_preview_source}}

严格要求：
- 只返回 DSL 本体，不要返回 markdown，不要加代码块，不要解释。
- 这是一次兼职共同行动，不是正式职场剧，不是工作总结，也不是告白剧情。
- 必须保留 AVG 表现信息，不要只写纯对白提纲。
- 这是可播放的场景，不是摘要。
- 场景必须停在"下班收尾"处，不要把回家后的 LinkChat、手机震动、朋友圈或结算写进 DSL。

你必须使用的 DSL V2 语法：
- 背景：`bg.show("bg_park_grass", fade_duration=0.4)`
- 普通图片（可选）：`image.show("photo_001", position="center", size="medium")`
- 全屏 CG（可选）：`cg.show("cg_event_001")` / `cg.hide()`
- 角色出场：`char_001.show(position="center", outfit="casual", emotion="happy")`
- 表情变化：`char_001.expression = "happy"`
- 换装：
  `char_001.outfit = "maid"`
  或 `char_001.change_outfit(outfit="loungewear", emotion="happy", transition="instant")`
- 淡入淡出：`screen.fade(direction="in", duration=0.35)`
- 改变光照分布（时间）：`screen.time_of_day("dusk", duration=0.6)` # 可选值: day / dusk / night
- 停顿：`time.wait(0.25)`
- 角色动作特效：
  `char_001.effect("jump")` — 角色跳起（开心、惊喜）
  `char_001.effect("bounce")` — 角色弹跳（兴奋、得意）
  `char_001.effect("shake", intensity="small")` — 角色颤抖（害羞、紧张、震惊）
  `char_001.effect("nod")` — 角色点头（认同、温柔回应）
  intensity 可选值：small / medium / large，默认 medium。
- 镜头震动：`camera.shake()`
- 对话块：
  `# => TextBlock(speaker="char_001", expression="happy")`
  `> 对话内容`
- 旁白块：
  `# => TextBlock()`
  `> 旁白内容`

{{date_scene_asset_manifest}}

结构要求：
- 必须有到岗、一起干活（含互动高潮点）、下班收尾三段。
- **不允许使用 ChoiceBlock**，整段场景是线性叙事。
- 至少有 1 次背景设定。
- 至少有 1 次角色出场。
- 至少 2 次表情变化。
- 至少 1 次角色动作特效（effect）。
- 至少 1 次停顿（time.wait），用于互动高潮点的氛围留白。

关键执行规则：
- 角色 position 必须使用 "center"，这是单角色场景。
- 第一条出现 `char_001` 对白之前，必须先写 `char_001.show(...)`。
- 不允许让 `char_001` 在未出场时直接说话。
- 第一屏推荐顺序是：`screen.fade(...)` -> `bg.show(...)` -> `char_001.show(...)` -> 第一段对白/旁白。
- 若场景里出现 `char_001.expression = ...`、`char_001.outfit = ...` 或 `char_001.effect(...)`，该角色必须已经先出场。
- 结尾必须是"下班收尾"，不要再追加手机、聊天、朋友圈内容。

写作要求：
- 这是共同打工的日常互动，不是正式职场剧。
- 角色表现、表情、服装变化和停顿要和语气一致。
- 不要编造不存在的角色、背景、音频、服装名。
- 若使用 `image.show(...)` 或 `cg.show(...)`，图片名也必须来自上面的资产清单，且不要把角色立绘当作普通图片/CG 使用。
