# AVG DSL V2 可用语法

输出一段可直接解析和播放的 AVG DSL。所有角色、背景、图片、音乐和音效标识都来自本次提供的资产清单；角色使用清单中的 `character_name`。

## 推荐开场

```text
screen.fade(direction="in", duration=0.35)
bg.show("background_primary", fade_duration=0.4)
stage.set("CharacterA", emotions="neutral", outfits="default")
# => TextBlock(speaker="CharacterA", expression="neutral")
> 第一段台词。
```

资产清单为空时，可以省略背景、角色和音频命令，仅使用旁白、台词和选择块完成场景。

## 背景与屏幕

- `bg.show("background_primary", fade_duration=0.4)`
- `screen.time_of_day("dusk", duration=0.6)`，时间值为 `day`、`dusk`、`night`
- `screen.fade(direction="in", duration=0.35)`：从黑屏显示画面
- `screen.fade(direction="out", duration=0.35)`：从画面进入黑屏
- `screen.flash(color="#FFFFFF", duration=0.15, intensity=0.8)`

场景中段的强转场使用完整配对：

```text
screen.fade(direction="out", duration=0.4)
bg.show("background_secondary")
screen.fade(direction="in", duration=0.4)
```

## 角色与舞台

- `stage.set("CharacterA", "CharacterB")`：设置当前登台角色并自动排位
- `stage.set("CharacterA", emotions="happy", outfits="default")`
- `stage.enter("CharacterB", emotions="neutral")`
- `stage.exit("CharacterB")`
- `stage.clear()`
- `CharacterA.show(position="center", outfit="default", emotion="neutral", enter_effect="fade")`
- `CharacterA.hide(fade_duration=0.3, exit_effect="fade")`
- `CharacterA.move(target="left", duration=0.4)`
- `CharacterA.flip()`
- `CharacterA.expression = "happy"`
- `CharacterA.outfit = "alternate"`
- `CharacterA.change_outfit(outfit="alternate", emotion="happy")`
- `CharacterA.effect("jump")`
- `CharacterA.effect("bounce")`
- `CharacterA.effect("shake", intensity="small")`
- `CharacterA.effect("nod")`

位置值为 `left`、`center`、`right`、`far_left`、`far_right`。入场效果为 `fade`、`slide_from_left`、`slide_from_right`、`slide_from_top`、`slide_from_bottom`、`pop_in`、`none`。退场效果使用对应的 `slide_to_*`、`fade`、`pop_out` 或 `none`。

没有立绘资源的说话者只使用 `TextBlock(speaker="TextSpeaker")`，不加入 `stage.*`。

## 镜头

- `camera.shake()`
- `camera.zoom(1.3, duration=0.5, focus="CharacterA")`
- `camera.zoom(1.2, duration=0.5, focus="between")`
- `camera.pan(target="right", duration=0.6)`
- `camera.reset(duration=0.4)`

## 图片与音频

- `image.show("image_primary", position="center", size="medium", transition="fade")`
- `cg.show("cg_primary")`
- `cg.hide()`
- `bgm.play("bgm_primary")`
- `bgm.stop()`
- `sfx.play("sfx_primary")`

只在相应标识出现在资产清单中时使用这些命令。

## 对话与旁白

角色台词：

```text
# => TextBlock(speaker="CharacterA", expression="happy")
> 第一行台词。
> 同一说话者的第二行台词。
```

旁白：

```text
# => TextBlock()
> 一段旁白。
```

每次切换说话者、表情或旁白时，新建一个 `TextBlock`。连续的 `>` 行属于同一个块。

## 选择、变量与跳转

```text
# => ChoiceBlock()
- 选项一
    var[path_a] = 1
    # => TextBlock()
    > 选项一的结果。
- 选项二 [if var[route_open] == 1]
    scene.jump("scene_secondary")
```

- 变量写法：`var[meaningful_key] = 0`、`var[meaningful_key] += 1`
- 变量值使用整数或字符串；布尔状态使用 `0` 和 `1`
- 条件支持 `and`、`or` 和括号
- 跳转写法：`scene.jump("scene_secondary")`
- 静默留白写法：`time.wait(0.3)`

## 输出检查

生成结果满足以下条件：

1. 只包含本文列出的 DSL 语法。
2. 所有资源标识来自资产清单。
3. 已注册角色在说话前已经通过 `stage.*` 或角色 `show()` 登台。
4. 每个中途淡出都有后续淡入；场景末尾可以用淡出收尾。
5. 默认使用线性叙事；场景需求明确包含分支时再使用 `ChoiceBlock`。
