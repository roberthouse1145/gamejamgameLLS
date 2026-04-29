DSL V2 语法。所有角色引用必须使用 `character_name`（如 `LinXia`），禁止使用 `character_id`（如 `char_001`）。

背景/环境：
- `bg.show("bg_park_grass", fade_duration=0.4)`
- `screen.time_of_day("dusk", duration=0.6)`，值：day / dusk / night

角色管理：
- `stage.set(...)`、`stage.enter(...)`、`stage.exit(...)` 只用于已注册且有立绘/可登台资源的角色。
- 纯文本 NPC（店员/老板娘/路人/同学等）不要写进 `stage.*`；直接用 `TextBlock(speaker="店员")`，说完也不要 `stage.exit("店员")`。
- 多角色自动排位：`stage.set("LinXia", "Shopkeeper")`；1 人 center，2 人 left/right，3 人 left/center/right，4~5 人均匀摊开；不在名单里的当前角色会离场。
- 可选表情/服装：`stage.set("LinXia", "Shopkeeper", emotions="happy,neutral", outfits="casual,_")`；顺序一一对应，`_` 表示保持当前值或默认值。
- 入场：`stage.enter("Shopkeeper", emotions="neutral")`，可多角色：`stage.enter("Shopkeeper", "Professor", emotions="neutral,serious")`。
- 离场：`stage.exit("Shopkeeper")`，可多角色：`stage.exit("Shopkeeper", "Professor")`。
- 清场：`stage.clear()`，用于切 CG、纯旁白段、换景前清空立绘。
- 单角色出场：`LinXia.show(position="center", outfit="casual", emotion="happy")`。
- position：left / center / right / far_left / far_right。
- enter_effect：fade / slide_from_left / slide_from_right / slide_from_top / slide_from_bottom / pop_in / none。
- 退场：`LinXia.hide(fade_duration=0.3, exit_effect="fade")`；exit_effect：fade / slide_to_left / slide_to_right / slide_to_top / slide_to_bottom / pop_out / none。
- 移动/翻转：`LinXia.move(target="left", duration=0.4)`；`LinXia.flip()`。

表情/服装：
- `LinXia.expression = "happy"`
- `LinXia.outfit = "maid"` 或 `LinXia.change_outfit(outfit="loungewear", emotion="happy")`
- emotion 和 outfit 是枚举，只能用资产清单中该角色的可用值。

动作特效：
- `LinXia.effect("jump")`：开心/惊喜
- `LinXia.effect("bounce")`：兴奋/得意
- `LinXia.effect("shake", intensity="small")`：害羞/紧张/震惊
- `LinXia.effect("nod")`：认同/温柔回应
- intensity：small / medium / large，默认 medium

镜头：
- `camera.shake()`
- `camera.zoom(1.3, duration=0.5)`；可加 `focus="LinXia"` 或 `focus="between"`；不写 focus 时自动推断。
- `camera.pan(target="right", duration=0.6)`
- `camera.reset(duration=0.4)`

屏幕特效：
- `screen.fade(direction="in", duration=0.35)`；transition：fade / dissolve / wipe_left / wipe_right / wipe_up / wipe_down。
- `screen.flash(color="#FFFFFF", duration=0.15, intensity=0.8)`；`intensity` 必须是 `0.0-1.0` 数值，禁止写 small/medium/large 或 轻/中/重。

音频：
- `bgm.play("bgm_alias_name")`
- `bgm.stop()`
- `sfx.play("sfx_alias_name")`
- BGM/SFX alias 必须来自资产清单；没有合适音效就省略，不要编造。

图片/CG：
- `image.show("photo_001", position="center", size="medium", transition="fade")`
- `cg.show("cg_event_001")` / `cg.hide()`
- CG 默认：`cg.show` 使用 `transition="crossfade"`、`fade_duration=0.25`；`cg.hide` 默认 `fade_duration=0.2`。
- transition：fade / crossfade / fade_through_black / instant。
- 图片/CG 名必须来自资产清单，不能把角色立绘当普通图片/CG。

等待：
- `time.wait(0.3)` 只用于真正的静默留白。
- `wait.click()` 一般不需要额外添加，对话块自带等待。

对话/旁白：
- `# =>` 只用于 `TextBlock(...)` 和 `ChoiceBlock(...)`，不能给普通命令加前缀。
- 普通命令直接顶格写：`screen.*`、`bg.*`、`bgm.*`、`sfx.*`、`stage.*`、`camera.*`、`cg.*`、`image.*`、`time.wait`、角色 show/hide/move/effect/expression/outfit、`var[...]`、`if ...:`、`scene.jump(...)`。
- 角色台词：
  `# => TextBlock(speaker="LinXia", expression="happy")`
  `> 对话内容`
- 旁白：
  `# => TextBlock()`
  `> 旁白内容`
- NPC 台词：
  `# => TextBlock(speaker="店员", expression="neutral")`
  `> 欢迎光临！请问想喝点什么？`
- speaker：已注册角色用 `character_name`，纯文本 NPC 直接写中文身份，禁止用 `"Stranger"` 等英文通称。
- 台词只写角色说出口的话，禁止括号动作或舞台说明，如 `> 芜湖！（笑）`。

分支选项：
仅当导演指导明确要求生成分支时使用。
```
# => ChoiceBlock()
- 选项文本1
	LinXia.expression = "happy"
	# => TextBlock(speaker="LinXia", expression="happy")
	> 选项1后的对话
- 选项文本2
	LinXia.expression = "surprised"
	# => TextBlock(speaker="LinXia", expression="surprised")
	> 选项2后的对话
- 选项文本3 [if var[linxia_affection] > 5]
	> 满足条件才显示的选项
```
选项以 `- ` 开头；选项下方内容缩进 4 个空格；`[if ...]` 可选。

变量/跳转：
- 变量必须用语义化 key：`var[linxia_affection] += 1`，禁止 `var[1]`。
- 写入 DSL 时，未定义变量会自动创建并初始化为 `0`。
- 变量只允许 int / string；布尔语义用 `0/1`；float 会截断成 int。
- 混用 string 和 int 比较会 warning，运行时空字符串视为 `0`、非空字符串视为 `1`。
- 路线/结局/flag 也用整数编码，例如 `var[ending_flag] = 0`。
- 不要写 `var[x] = ""`、`var[x] = "route_a"`、`var[x] == true`、`var[x] == false`。
- 条件支持 `and` / `or` / 括号：`if var[a] >= 3 and (var[b] == 1 or var[c] >= 5):`
- 跳转：`scene.jump("scene_002")`。

执行规则：
- 已注册且有立绘的角色，第一次说话前必须先 `角色名.show(...)`、`stage.set(...)` 或 `stage.enter(...)`。
- 2 个以上角色同时在场时，优先用 `stage.set/enter/exit` 自动排位。
- 全员退场优先 `stage.clear()`，不要逐个 hide。
- 第一屏推荐顺序：`screen.fade(...)` -> `bg.show(...)` -> `bgm.play(...)` -> 角色出场 -> 第一段对白/旁白。
- `角色名.expression/outfit/effect(...)` 只能用于已出场角色。
- 默认线性叙事，不用 ChoiceBlock；若场景要求明确要分支，则生成 2~3 个选项。
- 背景、服装、表情、角色、BGM、SFX、图片、CG 都只能来自资产清单，禁止编造，禁止写 `res://...`。
