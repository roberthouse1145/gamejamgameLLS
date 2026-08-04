# Chat DSL v0.1 设计草案

状态：v0.1 核心语法、校验器、执行器和 TopicManager 接入已实现。

## 1. 定位

一个 `ChatTopic` 是一段有开始、流程和结束结果的聊天剧本，不是自由聊天会话。

LOCAL 与 LLM 使用同一种 Chat DSL：

```text
LOCAL
local_script → 解析与校验 → Chat Runner

LLM
prompt → PromptManager 装配 → LLM 生成 Chat DSL → 解析与校验 → Chat Runner
```

玩家默认观看剧本。只有剧本显式声明 `CHOICE` 时，玩家才会看到预先写好的固定选项。Chat DSL 不提供自由文本输入。

游戏数值、关系和剧情变量是只读条件来源。Chat DSL 通过结束结果把演出结论交回 `StoryDirector`，不直接修改核心状态。

## 2. ChatTopic 字段

```gdscript
class_name ChatTopic extends Resource

enum Mode {
	LOCAL,
	LLM,
}

@export var topic_id: String = ""
@export var channel_id: String = ""
@export var mode: Mode = Mode.LOCAL

@export_multiline var local_script: String = ""
@export_multiline var prompt: String = ""
```

字段职责：

- `topic_id`：供剧情等待、存档和结果关联使用。
- `channel_id`：决定剧本在哪个聊天频道播放。
- `mode`：选择本次运行使用 LOCAL 还是 LLM 管线。
- `local_script`：作者直接书写的完整 Chat DSL。
- `prompt`：由 `PromptManager` 装配的模板，LLM 输出必须是完整 Chat DSL。

切换 `mode` 不清空另一个文本字段。运行时只执行当前模式对应的字段。

## 3. v0.1 指令

DSL 按行解析。控制指令使用大写关键字；缩进只用于提高可读性，不参与语义。

### 3.1 角色消息

```text
lu_yuanyuan: 柚柚，在吗？
player: ……在。
```

冒号左侧使用稳定的角色标识。聊天 UI 根据角色标识解析显示名称、头像和消息样式。

`player` 是保留标识，代表玩家一侧已经由剧本写定的消息。聊天 UI 将 `player` 显示在右侧；其他发言者显示在左侧。它不代表自由输入入口。

### 3.2 标签与跳转

```text
LABEL opening
JUMP ending

LABEL ending
END viewed
```

- `LABEL <label_id>` 声明跳转目标。
- `JUMP <label_id>` 从当前位置跳转到目标标签。
- 标签在一个 ChatTopic 内唯一。
- 标签只出现在顶层，避免跳入未完成的条件块或选项块。

### 3.3 条件分支

```text
IF state.stress >= 80
	lu_yuanyuan: 你今天是不是又在硬撑？
ELIF relationship.lu_yuanyuan.trust >= 60
	lu_yuanyuan: 有事就告诉我，别一个人扛着。
ELSE
	lu_yuanyuan: 今天过得怎么样？
ENDIF
```

执行器在播放到 `IF` 时读取当前状态并选择一个分支。未进入的分支不会产生消息。

### 3.4 固定选项

```text
CHOICE
	OPTION confess "说实话" -> confess IF relationship.lu_yuanyuan.trust >= 30
	OPTION avoid "先敷衍过去" -> avoid
ENDCHOICE
```

`OPTION` 的结构为：

```text
OPTION <option_id> "<玩家可见文字>" -> <label_id> [IF <condition>]
```

- 条件成立的选项才会显示。
- 每个 `CHOICE` 至少包含一个不带条件的选项，保证始终存在可选分支。
- 玩家选择后，执行器跳转到对应标签，并记录 `option_id`。
- 选项只决定剧本流程，不直接修改游戏数值。

### 3.5 结束

```text
END confessed
```

`END <result_id>` 结束当前 ChatTopic。TopicManager 至少返回：

```gdscript
{
	"result_id": "confessed",
	"choice_id": "confess",
}
```

没有经过 `CHOICE` 时，`choice_id` 为空。`StoryDirector` 根据 `result_id` 或 `choice_id` 继续剧情、捕获变量或执行游戏侧效果。

## 4. 条件表达式

条件读取运行时提供的只读变量路径，例如：

```text
state.stress
state.money
relationship.lu_yuanyuan.favor
relationship.lu_yuanyuan.trust
story.contract_signed
```

v0.1 支持：

```text
==  !=  >  >=  <  <=
AND  OR  NOT
(  )
```

字面量支持整数、浮点数、布尔值和带引号字符串。

```text
IF state.stress >= 60 AND relationship.lu_yuanyuan.trust >= 30
	lu_yuanyuan: 你可以跟我说实话。
ENDIF
```

解析器只负责表达式语法；变量路径是否存在由当前游戏提供的状态清单校验。LLM 模式的 prompt 会收到同一份可用变量清单。

## 5. 完整 LOCAL 示例

```text
LABEL start
lu_yuanyuan: 柚柚，在吗？

IF state.stress >= 80
	lu_yuanyuan: 你今天是不是又在硬撑？
ELSE
	lu_yuanyuan: 今天过得怎么样？
ENDIF

CHOICE
	OPTION confess "说实话" -> confess IF relationship.lu_yuanyuan.trust >= 30
	OPTION avoid "先敷衍过去" -> avoid
ENDCHOICE

LABEL confess
player: ……其实今天不太好。
lu_yuanyuan: 那就别装没事。
END confessed

LABEL avoid
player: 没什么，和平时一样。
lu_yuanyuan: 是吗？
END avoided
```

同一份剧本同时展示了自动状态分支和一个明确的固定选择点。没有 `CHOICE` 的 ChatTopic 会从头播放到 `END`，玩家只观看。

## 6. LLM 模式约束

LLM 模式生成的是完整 Chat DSL，不与玩家进行逐轮自由对话。

PromptManager 负责装配：

- Chat DSL 允许语法。
- 本次允许使用的角色标识。
- 本次允许读取的状态变量路径。
- 人物卡、关系上下文和剧情目标。
- 最小的合法输出示例。

LLM 输出经过与 LOCAL 相同的解析和校验，再交给同一个 Chat Runner。核心结果仍由代码和 `StoryDirector` 决定。

运行时由 `TopicManager.topic_generation_requested(topic, resolved_prompt)` 发出已经装配好的生成请求，并默认使用现有 `chat_default` AI 配置请求完整 DSL。模型返回后会进入 `submit_generated_script(channel_id, generated_script)`；该文本不会写回或覆盖 `local_script`。没有可用 AI 配置时，Topic 会保留在生成状态，供其它 LLM 调用层通过同一提交入口接管。

## 7. 校验要求

解析成功后至少检查：

- 存在 `END`。
- `LABEL` 不重复。
- 每个 `JUMP` 和 `OPTION` 的目标标签存在。
- `IF / ELIF / ELSE / ENDIF` 结构完整。
- `CHOICE / OPTION / ENDCHOICE` 结构完整。
- 每个 `CHOICE` 至少有一个无条件选项。
- 角色标识与变量路径来自本次运行提供的清单。
- 执行器具有循环保护，避免标签跳转永久循环。

## 8. 与 StoryDirector 的边界

Chat DSL 负责：

- 播放聊天消息。
- 根据只读状态选择演出分支。
- 展示少量固定选项。
- 产生 `result_id` 与可选的 `choice_id`。

StoryDirector 负责：

- 决定何时激活 ChatTopic。
- 等待 Topic 完成。
- 根据 Topic 结果推进大剧情。
- 修改游戏数值、关系与其它核心状态。

v0.1 不在 Chat DSL 中加入直接修改核心状态的指令。
