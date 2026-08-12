# AVG 演出原则

演出服务于角色对话，让玩家始终看清当前是谁在说话、看向谁、做出什么反应。

## 登台与站位

- 单角色通常位于 `center`。
- `stage.set` 按参数顺序从左到右安排角色；双人场景的第一个角色位于左侧，第二个角色位于右侧。
- 当前角色立绘默认朝左。双人相对构图完成后，左侧角色使用 `角色名.flip(flip="on")` 朝右，右侧角色使用 `角色名.flip(flip="off")` 保持朝左。
- 画面角色构成发生变化时，先用 `stage.set`、`stage.enter` 或 `stage.exit` 完成站位，再按最终位置明确设置朝向。
- 角色离开当前地点时使用 `stage.exit` 或角色 `hide()`。

```text
stage.set("CharacterA", "CharacterB")
CharacterA.flip(flip="on")
CharacterB.flip(flip="off")
```

## 表情、动作与镜头

- 台词附近使用角色现有表情表现当下反应。
- 点头、跳起、轻微摇晃等可见动作使用角色 `effect(...)`。
- 关键台词可用 `camera.zoom(...)` 引导注意力，随后用 `camera.reset()` 恢复。
- 地点或时间明确变化时，使用淡出、切换背景、淡入的完整转场。
- `time.wait` 用于角色停顿或需要留出反应时间的瞬间。

角色反应优先成为可见演出：突然受惊使用惊讶表情配合 `jump` 或 `shake`，赞同与确认使用 `nod`，轻快兴奋使用 `bounce`，迟疑使用表情变化与短暂停顿。强烈瞬间可以配合一次聚焦、闪白或轻微镜头震动，随后恢复常规构图。

```text
CharacterA.effect("shake", intensity="small", duration=0.25)
camera.zoom(1.2, duration=0.25, focus="CharacterA")
# => TextBlock(speaker="CharacterA", expression="shocked")
> 刚、刚才那是什么？
camera.reset(duration=0.25)
```

## 镜头节拍

- 用少量清楚的镜头节拍完成小事件；每一拍形成一次有意义的视觉状态，例如登场、反应动作、站位变化、镜头聚焦、环境变化或转场。
- 同一视觉状态下让对话自然完成；只有剧情焦点实际变化时才进入下一拍。
- 走向别处、抵达新位置、暂时离场、重新会合等空间变化由舞台与屏幕命令直接演出，让对白承载人物交流。
- 表情变化负责持续情绪，`effect(...)` 负责瞬时身体反应；同一关键反应可以组合二者。
- 只为最有辨识度的瞬时反应使用 `effect(...)`，其余情绪变化由文本块表情承担，让动作之间保留清楚的对话节奏。

## 空间互动编排

- 把靠近、递物、躲避、整理衣物、合照等空间互动拆成：标准构图、临时移动、动作完成、互动反应、离开临时构图、恢复标准构图。
- `move(target="x,y")` 形成持续的临时位置；`jump`、`shake`、`nod`、`bounce` 会在动作结束时回到动作开始的位置。
- 不同角色的移动与动作可以连续发出，再用一条 `time.wait(...)` 等待其中最长的时长。一个角色先移动再播放动作时，先等待移动完成，再开始该角色的动作。
- 临时构图根据剧情自行选择坐标：X 表示左右关系，Y 增大表示下沉。角色靠近时仍保留可辨认的左右顺序与朝向。
- 临时互动结束后，用一条相同角色顺序的 `stage.set(..., enter_effect="none", exit_effect="none")` 同时完成所有在场角色的标准站位复位，随后重新设置双方朝向并等待复位完成。
- 临时镜头聚焦与空间互动同步，互动结束后使用 `camera.reset(...)` 恢复常规镜头。

```text
CharacterA.move(target="0.48,0.58", duration=0.35)
CharacterB.effect("bounce", intensity="small", duration=0.3)
time.wait(0.35)
# => TextBlock(speaker="CharacterA", expression="smile")
> 互动中的台词。
stage.set("CharacterA", "CharacterB", duration=0.35, enter_effect="none", exit_effect="none")
CharacterA.flip(flip="on")
CharacterB.flip(flip="off")
time.wait(0.35)
```

同一背景内移动到另一段步道、座位或区域时，可以用一组短转场表达经过的路程：

```text
stage.exit("CharacterA", "CharacterB", duration=0.3, exit_effect="slide_to_right")
time.wait(0.3)
screen.fade(direction="out", duration=0.25)
screen.fade(direction="in", duration=0.25)
stage.set("CharacterA", "CharacterB", duration=0.3, enter_effect="slide_from_left")
CharacterA.flip(flip="on")
CharacterB.flip(flip="off")
time.wait(0.3)
```

地点改变时，在淡出与淡入之间加入新背景：

```text
stage.exit("CharacterA", "CharacterB", duration=0.3, exit_effect="fade")
time.wait(0.3)
screen.fade(direction="out", duration=0.3)
bg.show("background_secondary", fade_duration=0.3, transition="dissolve")
screen.fade(direction="in", duration=0.3)
stage.set("CharacterA", "CharacterB", duration=0.3, enter_effect="fade")
CharacterA.flip(flip="on")
CharacterB.flip(flip="off")
time.wait(0.3)
```

## 资源边界

- 有立绘的在场角色使用舞台、表情、服装和动作命令。
- 只有文本身份的临时说话者直接使用 `TextBlock(speaker="...")`。
- 背景、图像和音频只选用资产清单中的标识。
