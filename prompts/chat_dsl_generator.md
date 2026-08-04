你要根据本次聊天目标与上下文，编写一份可直接执行的完整 Chat DSL。

聊天目标：
{{topic_prompt}}

可用发言者标识：
{{allowed_speakers}}

可用只读变量路径：
{{allowed_variable_paths}}

当前上下文：
{{runtime_context}}

只使用以下语法：

```text
speaker_id: 消息正文
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

`player` 代表玩家一侧已经由剧本写定的消息，聊天界面会将其显示在右侧。其他发言者显示在左侧。玩家只观看这些消息；只有 `CHOICE` 会要求玩家选择固定选项。

输出一份完整 Chat DSL。最小结构示例：

```text
LABEL start
friend: 在吗？
player: 在。
END viewed
```
