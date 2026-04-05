你必须使用的 DSL V2 语法：

**角色引用规则：DSL 中必须使用 `character_name`（如 `LinXia`）引用角色，禁止使用 `character_id`（如 `char_001`）。通过 `db_list(type="characters")` 查询角色的 `character_name`。**

## 背景与环境

- 背景：`bg.show("bg_park_grass", fade_duration=0.4)`
- 改变光照/时间氛围：`screen.time_of_day("dusk", duration=0.6)` — 可选值: day / dusk / night

## 角色管理

- 多角色自动排位：`stage.set("LinXia", "Shopkeeper")`
  - 1 人时自动站 `center`
  - 2 人时自动排成左/右
  - 3 人时自动排成左/中/右
  - 4~5 人时自动均匀摊开，避免明显空位
  - 已经在场的角色会自动补位；不在名单里的角色会自动离场
  - 可选表情列表：`stage.set("LinXia", "Shopkeeper", emotions="happy,neutral")`
  - 可选服装列表：`stage.set("LinXia", "Shopkeeper", outfits="casual,_")`
  - `emotions` 和 `outfits` 按角色顺序一一对应，`_` 表示保持当前状态或使用默认值
- 角色出场：`LinXia.show(position="center", outfit="casual", emotion="happy")`
  - position 可选值：`left` / `center` / `right` / `far_left` / `far_right`
  - 入场动画（可选）：`LinXia.show(position="right", emotion="happy", enter_effect="slide_from_right")`
    可选值：fade / slide_from_left / slide_from_right / slide_from_top / slide_from_bottom / pop_in / none
- 角色退场：`LinXia.hide(fade_duration=0.3, exit_effect="fade")`
  - exit_effect 可选值：fade / slide_to_left / slide_to_right / slide_to_top / slide_to_bottom / pop_out / none
- 角色移动：`LinXia.move(target="left", duration=0.4)` — 将角色平滑移动到新位置
- 角色翻转：`LinXia.flip()` — 水平镜像翻转

## 表情与服装

- 表情变化：`LinXia.expression = "happy"`
- 换装：`LinXia.outfit = "maid"` 或 `LinXia.change_outfit(outfit="loungewear", emotion="happy")`

**⚠ emotion 和 outfit 是枚举值，不是自由文本。** 你只能使用资产清单中该角色"可用表情"列出的值。

## 角色动作特效

- `LinXia.effect("jump")` — 开心、惊喜时跳起
- `LinXia.effect("bounce")` — 兴奋、得意时弹跳
- `LinXia.effect("shake", intensity="small")` — 害羞、紧张、震惊时颤抖
- `LinXia.effect("nod")` — 认同、温柔回应时点头
- intensity 可选值：small / medium / large，默认 medium

## 镜头控制

- 镜头震动：`camera.shake()`
- 镜头推近：`camera.zoom(1.3, duration=0.5)` — 特写、强调情绪
  - 聚焦角色：`camera.zoom(1.3, focus="LinXia")` — 自动聚焦到该角色当前位置
  - 聚焦两人之间：`camera.zoom(1.2, focus="between")` — 聚焦所有可见角色的中点
  - 不指定 focus 时，系统自动推断：单角色在场则聚焦该角色，否则聚焦画面中心
- 镜头平移：`camera.pan(target="right", duration=0.6)` — 视线引导
- 镜头复位：`camera.reset(duration=0.4)` — 回到默认视角

## 屏幕特效

- 淡入淡出：`screen.fade(direction="in", duration=0.35)`
  - transition 可选值：fade / dissolve / wipe_left / wipe_right / wipe_up / wipe_down
- 闪屏：`screen.flash(color="#FFFFFF", duration=0.15)` — 冲击、震惊、闪光灯

## 音频

- 播放 BGM：`bgm.play("bgm_alias_name")` — alias 必须来自资产清单
- 停止 BGM：`bgm.stop()`
- 播放音效：`sfx.play("sfx_alias_name")` — alias 必须来自资产清单。如果清单中没有合适的音效，不要编造，直接省略

## 图片与 CG

- 普通图片（可选）：`image.show("photo_001", position="center", size="medium")`
- 全屏 CG（可选）：`cg.show("cg_event_001")` / `cg.hide()`

## 等待与节奏

- 停顿：`time.wait(0.3)` — 仅在需要真正的静默留白时使用（如对视、震惊后的空白）
- 等待点击：`wait.click()` — 等待玩家点击继续（对话块自带，一般不需要额外添加）

## 对话与旁白

- 对话块（角色台词）：
  `# => TextBlock(speaker="LinXia", expression="happy")`
  `> 对话内容`

- 旁白块（叙述、环境描述、内心独白）：
  `# => TextBlock()`
  `> 旁白内容`

- NPC / 第三方人物对话：
  `# => TextBlock(speaker="店员", expression="neutral")`
  `> 欢迎光临！请问想喝点什么？`
  speaker 规则：已注册角色用 ID（如 `"LinXia"`），路人/NPC 直接写中文身份（如 `"店员"`、`"路人"`、`"教授"`），**禁止使用英文通称如 "Stranger"**。
  注意：NPC 如果在资产清单中有立绘，可以用 `NPC名.show(...)` 出场；如果没有立绘，可以只写对话块不出场（表现为无立绘的语音气泡），或用旁白描述。

## 分支选项块

仅当导演指导明确要求生成分支时才使用：
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
- 选项文本3 [if var[1] > 5]
    > 满足条件才显示的选项
```
注意：每个选项以 `- ` 开头，选项下方的执行内容必须缩进 4 个空格。`[if ...]` 是可选的条件过滤。

---

## 关键执行规则

- 角色第一次说话之前，必须先写 `角色名.show(...)` 或 `stage.set(...)`。不允许让角色在未出场时直接说话。
- 如果场景里有 2 个或更多角色同时在场，优先使用 `stage.set(...)` 来交给系统自动排位。
- 第一屏推荐顺序：`screen.fade(...)` → `bg.show(...)` → `bgm.play(...)` → `角色名.show(...)` → 第一段对白/旁白。
- 若场景里出现 `角色名.expression = ...`、`角色名.outfit = ...` 或 `角色名.effect(...)`，该角色必须已经先出场。
- 默认情况下整段场景是线性叙事，**不使用 ChoiceBlock**。但如果上方的场景要求中明确要求"生成分支选项"，则必须使用 `# => ChoiceBlock()` 语法生成选项，且选项数量为 2~3 个。
- 背景、服装、表情名只能从资产清单里选，禁止编造新名字。
- 不要编造不存在的角色、背景、音频、服装名。BGM 和 SFX 的 alias 也必须来自资产清单，不要编造不存在的 alias。
- 若使用 `image.show(...)` 或 `cg.show(...)`，图片名也必须来自资产清单，且不要把角色立绘当作普通图片/CG 使用。
