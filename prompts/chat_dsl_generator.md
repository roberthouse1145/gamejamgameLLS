你要根据本次聊天目标与上下文，编写一份可直接执行的完整 Chat DSL。

{{jailbreak_prompt}}

{{dsl_generation_pacing}}

{{chat_moe_tone}}

## 即时聊天写作目标

成品是一段会逐条弹出气泡的即时聊天记录。每一行 `speaker_id: 消息正文` 就是一个独立气泡。

- 使用自然口语和短句。普通气泡以 4～24 个汉字为主，每个气泡最多 40 个汉字。
- 一个气泡只承担一个作用，例如回应、追问、补充事实、提出安排或表达态度。
- 一个人有几件事要说时，让同一 speaker 连续发送 1～2 个短气泡；只有信息确实无法合并时才使用第 3 个。
- 对话通过必要的来回发送推进，不为展示性格额外增加轮次。
- 角色口癖、语气符号和称呼作为点缀使用；同一种显眼口癖在一段对话中出现 1～2 次即可。
- `player` 的台词同样使用短消息，只表达玩家实际发送出去的话。
- 气泡内容只写角色会在聊天软件中发出的文字。剧情信息拆成对方能自然接住的若干消息。
- `CHOICE` 的选项文字保持简短明确，玩家扫一眼即可做决定。
- 使用当前上下文与聊天目标提供的事实，让角色语气和关系符合设定。
- 聊天目标给出固定轮次或顺序时严格采用该结构；没有固定结构时，完整剧本通常使用 4～8 个消息气泡。目标达成后立即 `END`。

只使用以下语法：

```text
speaker_id: 消息正文
speaker_id: [card:location|活动ID]
speaker_id: [card:file|文件标题|browser://页面地址|副标题]
speaker_id: [card:link|链接标题|browser://页面地址|说明]
speaker_id: [card:image|图片标题|res://图片资源路径|说明]
LABEL label_id
JUMP label_id
IF condition
ELIF condition
ELSE
ENDIF
CHOICE
OPTION option_id "玩家可见文字" -> label_id IF condition
OPTION option_id "玩家可见文字" -> label_id
ENDCHOICE
END result_id
```

条件可使用 `== != > >= < <= AND OR NOT ( )`，变量只从可用只读变量路径中选择。每个 `CHOICE` 至少提供一个不带条件的 `OPTION`。`LABEL` 位于顶层。`JUMP` 与 `OPTION` 指向已声明的标签。剧本至少包含一个 `END`。

地点卡片整条占用一个消息气泡，只写 `[card:location|活动ID]`，展示内容（标题、地点、价格）由系统自动填充。图片卡片只使用聊天目标或当前上下文明确提供的 `res://` 图片资源路径。

`player` 代表玩家一侧已经由剧本写定的消息，聊天界面会将其显示在右侧。其他发言者显示在左侧。玩家只观看这些消息；只有 `CHOICE` 会要求玩家选择固定选项。

短消息结构示例：

```text
LABEL start
friend: 到楼下了吗？
friend: 我在门口，等你半天啦
player: 刚下楼！马上！
friend: 慢慢来慢慢来，不催你
player: 到了到了！你在哪呢
friend: 前面树底下，举着奶茶那个就是我
friend: 给你带的，刚出的新品
player: 哇！爱了！
END viewed
```

输出前检查每条消息的长度和信息量，把超过 40 个汉字或包含多个独立意思的内容拆成连续气泡，同时删除重复作用的气泡。只输出完整 Chat DSL，不添加代码围栏或说明文字。

## 本次聊天任务

游戏时间：
{{current_game_time}}

聊天目标：
{{topic_prompt}}

可用发言者标识：
{{allowed_speakers}}

可用只读变量路径：
{{allowed_variable_paths}}

当前上下文：
{{runtime_context}}

{{chat_reasoning_requirement}}
