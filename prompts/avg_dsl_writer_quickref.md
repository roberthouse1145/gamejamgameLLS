你必须使用 DSL V2 的**标准写法**，但这里只保留 Writer 最常用、最容易写错的子集。

## 基本顺序

新建或明显重写场景时，第一屏默认顺序：

`screen.fade(...)` -> `bg.show(...)` -> `bgm.play(...)` -> 角色出场 -> 第一段对白/旁白

## 角色引用

- 角色必须使用 `character_name`，例如 `LinXia`
- 禁止使用 `char_001`
- 角色首次说话前，必须先 `角色.show(...)`、`stage.set(...)` 或 `stage.enter(...)`

## 常用演出

- 背景：`bg.show("bg_alias", fade_duration=0.4)`
- BGM：`bgm.play("BGM_alias")`
- 停止 BGM：`bgm.stop()`
- 音效：`sfx.play("sfx_alias")`
- 淡入：`screen.fade(direction="in", duration=0.35)`
- 闪屏：`screen.flash(color="#FFFFFF", duration=0.15, intensity=0.8)`，注意 `intensity` 只能写 `0.0-1.0` 数值，不能写 `small/medium/large` 或 `轻/中/重`
- 镜头推近：`camera.zoom(1.2, duration=0.4, focus="LinXia")`
- 镜头复位：`camera.reset(duration=0.4)`

## 角色与舞台

- 单角色出场：`LinXia.show(position="center", outfit="casual", emotion="happy")`
- 角色退场：`LinXia.hide(fade_duration=0.3, exit_effect="fade")`
- 表情：`LinXia.expression = "happy"`
- 换装：`LinXia.outfit = "uniform"`
- 移动：`LinXia.move(target="left", duration=0.4)`
- 翻转：`LinXia.flip()`
- 特效：`LinXia.effect("shake", intensity="small")`

优先使用舞台快捷指令处理多角色：

- `stage.set("LinXia", "SuYuqing")`
- `stage.enter("Teacher", emotions="serious")`
- `stage.exit("Teacher")`
- `stage.clear()`

注意：

- `stage.*` 只用于已注册且可登台的角色
- 纯文本 NPC 如“店员”“教授”“路人”不要写进 `stage.*`

## 对话与旁白

角色台词：

```dsl
# => TextBlock(speaker="LinXia", expression="happy")
> 今天来得很早啊。
```

旁白：

```dsl
# => TextBlock()
> 午后的风从走廊尽头吹进来。
```

纯文本 NPC：

```dsl
# => TextBlock(speaker="店员")
> 欢迎光临。
```

**配对铁律**：每个 `>` 行必须紧邻自己的 `# => TextBlock(...)`，一对一。多句连续对话必须为每句单独写一组 `# =>` + `>`。未紧邻 `# =>` 的 `>` 行会被自动视为旁白（speaker 为空），不会沿用上一行的 speaker。

错误（连续 `>` 想全归同一个 speaker）：

```dsl
# => TextBlock(speaker="LinXia")
> 我也不想告诉你。
> 他没有告诉林夏。
```

正确（每句独立配对、旁白显式声明）：

```dsl
# => TextBlock(speaker="LinXia")
> 我也不想告诉你。
# => TextBlock()
> 他没有告诉林夏。
```

## 变量与条件

- 变量必须使用语义化 key：`var[linxia_affection] += 1`
- 不要使用数字索引
- 当前变量系统只允许 `int / string`
- 布尔语义用 `0/1`，float 会被截断成 `int`
- 路线/结局/flag 既可以继续用整数编码，也可以使用字符串语义值
- 混用 `string` 和 `int` 做比较时，运行时会把空字符串视为 `0`、非空字符串视为 `1`
- 不要写 `var[x] = ""`、`var[x] = "ending_a"`、`var[x] == true`、`var[x] == false`
- 复合条件可以直接写：`if var[a] >= 2 and (var[b] == 1 or var[c] >= 1):`

示例：

```dsl
if var[linxia_trust] >= 2:
	# => TextBlock(speaker="LinXia", expression="shy")
	> 那我就只告诉你一个人。
else:
	# => TextBlock(speaker="LinXia", expression="neutral")
	> 这件事以后再说吧。
```

## 选择与跳转

只有 Planner 明确要求分支时才使用 `ChoiceBlock`：

```dsl
# => ChoiceBlock()
- 认真回答
	var[linxia_affection] += 1
- 故意岔开话题
	var[suyuqing_affection] += 1
```

场景跳转统一使用：

`scene.jump("scene_id")`

## 绝对规则

- 所有背景、BGM、SFX、表情、服装名只能来自 `list_assets`
- 不要写 `res://...`
- 不要写旧写法或自创写法
- 需要补丁修复时，优先维持现有结构，只改出错片段
