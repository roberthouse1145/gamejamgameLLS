# 开发规范
Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

Tradeoff: These guidelines bias toward caution over speed. For trivial tasks, use judgment.

1. Think Before Coding
Don't assume. Don't hide confusion. Surface tradeoffs.

Before implementing:

State your assumptions explicitly. If uncertain, ask.
If multiple interpretations exist, present them - don't pick silently.
If a simpler approach exists, say so. Push back when warranted.
If something is unclear, stop. Name what's confusing. Ask.
2. Simplicity First
Minimum code that solves the problem. Nothing speculative.

No features beyond what was asked.
No abstractions for single-use code.
No "flexibility" or "configurability" that wasn't requested.
No error handling for impossible scenarios.
If you write 200 lines and it could be 50, rewrite it.
Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

3. Surgical Changes
Touch only what you must. Clean up only your own mess.

When editing existing code:

Don't "improve" adjacent code, comments, or formatting.
Don't refactor things that aren't broken.
Match existing style, even if you'd do it differently.
If you notice unrelated dead code, mention it - don't delete it.
When your changes create orphans:

Remove imports/variables/functions that YOUR changes made unused.
Don't remove pre-existing dead code unless asked.
The test: Every changed line should trace directly to the user's request.

4. Goal-Driven Execution
Define success criteria. Loop until verified.

Transform tasks into verifiable goals:

"Add validation" → "Write tests for invalid inputs, then make them pass"
"Fix the bug" → "Write a test that reproduces it, then make it pass"
"Refactor X" → "Ensure tests pass before and after"
For multi-step tasks, state a brief plan:

1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

These guidelines are working if: fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

# Prompt 编写规范

编写给下游 LLM 使用的 prompt 时，优先提供正向的输出目标、允许语法、字段来源和最小示例。不要把 prompt 当前没有引入的错误形式、旧语法、其它语言/API、无关参数名写进提示词里做“勘误式否定”。

写 prompt 前先检查：

- 这个错误形式是否已经出现在当前 prompt、上下文材料、示例或资产清单里。
- 如果没有出现，不要为了“防错”把它加入 prompt。
- 能用“只使用以下语法 / 字段 / 来源”表达时，就用正向约束。
- 只有当输入材料已经包含某种干扰源，或验证器真实返回了该错误，才在局部修复 prompt 中提到它。
- 修复 prompt 尽量描述允许的替代形态；只有定位具体行号或字段时，才引用错误原文。
- 新增或修改 prompt 后，用搜索检查新增文本里是否引入了无来源的旧语法、错误参数、反例表或“不要写某错法”的内容。

面向解析器、测试、开发者文档的错误用例可以保留；面向生成模型的 prompt 要保持上下文干净。

# 游戏项目改动规范

游戏项目处在快速迭代期。已经确认要替换或废弃的功能、DSL、数据格式、入口和 UI，不默认保留兼容层。

实现改动前先判断：

- 这是正式玩家存档/线上内容必须读取的旧数据，还是开发期临时内容。
- 用户是否明确要求保留旧行为、迁移旧数据或兼容旧脚本。
- 兼容代码是否会增加新系统的复杂度、测试成本或 prompt 干扰。

默认做法：

- 已废弃的写法直接让验证失败，测试覆盖失败路径即可。
- 删除或停止暴露旧入口，避免新旧两套行为并存。
- 测试聚焦新规则的关键路径、关键失败条件、故事入口或玩家入口。
- smoke test 只覆盖“能启动、能进入目标状态、能结束/回调”的最小链路。
- 不为已经废弃的行为编写复杂回归、迁移器、双栈适配或长流程 smoke test。
- 如果确实需要兼容，必须在实现前写明原因、范围、退出条件和对应测试。

# 双层游戏视角

这个项目经常同时包含两层体验：

- 玩家游玩层：玩家直接看到和操作的内容，包括日常选择、资源消耗、角色互动、小游戏、反馈、阶段性展示等。
- 创作/开发层：系统、代理或工具在后台推动作品内容生成、修改、验证、沉淀知识和准备后续可游玩内容。

处理相关任务时，先判断改动影响哪一层，再确认两层之间的桥接关系：

- 玩家做了什么操作。
- 玩家立刻获得什么反馈。
- 后台是否触发创作、生成、整理、审查或发布流程。
- 后台结果如何回到玩家可见内容。
- 失败、取消、延迟完成时，玩家侧和后台侧分别保留什么状态。

修改和阅读代码时关注这些问题：

- 入口：玩家从哪里进入当前功能。
- 状态：玩家层状态和后台层状态分别存在哪里。
- 触发：哪一步把玩家行为转换为后台工作。
- 产物：后台工作写入什么内容，如何验证。
- 回流：产物通过什么界面、事件或阶段展示给玩家。
- 边界：调试入口、内部工具和正式玩家入口是否混在一起。

不要把当前实现细节写成长期规则。具体技术栈、目录结构、类名、节点名、资源名都可能随 gamejam 迭代变化。描述新约定时优先写意图、状态关系、验证方式和玩家体验。

# Godot 开发规范

## 可用工具

- **Godot Tool 扩展**: 检测 GDScript 语法错误
- **Godot MCP**: 运行项目、获取调试输出、创建场景/节点等
- **注意**: 无法操纵运行中的程序，需结合自动测试和用户手动测试

## 测试策略

1. 编写代码后查看输出检查语法错误。gdscript非python
2. 测试必须以“场景 + 脚本”成对存在，禁止单脚本运行
   - 每个 `test_xxx.gd` 都必须有对应的 `test_xxx.tscn`
   - 自动测试放在 `tests/automated/<domain>/`，现有 `tests/` 根目录和 `tests/<domain>/` 中的 `test_*.gd/.tscn` 仍按自动测试处理
   - 人工打开、交互、目视检查的入口放在 `tests/playtest/<domain>/`，文件名使用 `playtest_`
   - 真实 LLM/API、长流程实验、配置诊断入口放在 `tests/lab/<domain>/`
   - 不再新增 `scripts/tests/` 或 `scenes/tests/` 分离式测试入口；测试脚本和测试场景保持同名同目录
   - Godot 的 autoload 单例只有在运行场景时才会被引擎实例化
   - 单脚本运行时 autoload 不存在，访问任何 autoload 节点必定报错
   - 因此所有测试都必须通过对应测试场景运行，例如 `mcp_godot_mcp_run_project` 指定对应 `.tscn`
3. 使用 mcp 运行对应测试场景检查启动错误
4. 使用 mcp 获取运行时错误
5. 需要交互测试时，提示用户手动测试并反馈
6. **严禁**使用单脚本无场景测试（即使是 `@tool` + `EditorScript` 也不推荐，因为无法测试依赖 autoload 的逻辑）
7. **严禁在测试脚本中添加自动退出逻辑**（如 `get_tree().quit()`、定时器退出等）
   - 自动退出会导致进程在 MCP 调用 `get_debug_output` 之前就已终止，无法获取任何输出
   - 测试场景必须保持运行状态，由用户手动关闭或通过 `mcp_godot_mcp_stop_project` 停止
   - 正确流程：运行测试 → 调用 `get_debug_output` 获取输出 → 调用 `stop_project` 停止

### 游戏 UI 文案与玩家视角

- 写任何玩家可见文案前，先回答：玩家此刻想知道什么、能做什么、会获得什么反馈。
- UI 文案服务玩家决策和情绪，不展示实现过程、开发动作、测试状态或功能清单。
- 避免在玩家界面提到内部机制、预生成、初始化、资源注入、后台任务、测试场景、技术调试名词；只有当这些词是玩家实际看到并操作的游戏对象时才使用。
- 说明模式、入口、按钮、状态差异时，用玩家体验维度表达：剧情节奏、可用行动、角色互动、创作自由度、解锁范围、风险和限制。
- 内部工具在自由模式中出现时，入口说明优先包装成玩家目标，例如制作、编辑、试玩、整理项目；技术名只保留已作为 App 名称展示的部分。
- 写完文案后删掉所有无法回答“玩家为什么需要知道”的句子。
- 不为了让 UI 看起来更“完整”添加说明。信息量以玩家完成当前选择所需为准。

### 游戏 UI 验收

- UI、美术、布局和玩家体验改动，不用脆弱 smoke test 作为主要验收方式。
- 不为了证明“能跑”维护复杂 smoke；直接运行实际游戏入口、目标 app 入口或 `tests/playtest/` 里的人工检查场景。
- 自动测试只覆盖稳定契约：解析器、数据验证、故事入口信号、播放完成回调、资源索引等。
- 不给频繁变化的 UI 节点名、像素尺寸、临时排版写长期断言，除非用户明确要求把某个布局约束固定为规则。
- 视觉质量通过真实窗口观察、截图、用户反馈和 playtest 验收；不要用“场景启动成功”冒充视觉合格。
- 如果 UI 改动中途导致旧 smoke 失败，先判断该 smoke 是否仍有价值。没有价值时删除或降级它，不反复修补测试本身。

## GDScript 规范

### 文件结构

- 每个 `.gd` 脚本必须有配套的 `.tscn` 场景文件
- 不允许单独存在的 `.gd` 文件（除非是纯数据类或工具类）
- 资源类使用 `.tres` 配合 `.gd`

### Autoload 规则

- Autoload 脚本不能声明 `class_name`（会导致命名冲突）
- Autoload 通过 `project.godot` 中的名称访问，无需 class_name

### 命名约定

- 场景/脚本: `snake_case.tscn` / `snake_case.gd`
- 类名: `PascalCase`
- 变量/函数: `snake_case`
- 常量: `UPPER_SNAKE_CASE`
- 信号: `snake_case`（过去式，如 `health_changed`）

### 代码风格

- 使用类型注解: `var health: int = 100`
- 导出变量: `@export var speed: float = 200.0`
- 信号定义在类顶部，变量之前
- 使用 `@onready` 延迟初始化节点引用

## 项目结构

```text
res://
├── scenes/          # 场景文件 (.tscn)
├── scripts/         # 脚本文件 (.gd)
├── resources/       # 资源文件 (.tres)
├── assets/          # 素材 (图片、音频等)
├── autoload/        # 全局单例
└── addons/          # 插件
```

## 节点引用

- 简单场景: 使用 `$NodeName`
- 复杂场景: 使用 `%NodeName` (唯一名称) 避免路径依赖
	代码中直接用 `%MyNode` 引用，无需完整路径

## 常见错误预防

- 检查节点路径是否正确
- 确保信号连接在节点 ready 后进行
- 避免在 `_init()` 中访问场景树
- 使用 `is_instance_valid()` 检查节点是否有效

## 关于回复  
- 用户主要使用中文，默认用中文回复。  
- 用户通过 `#askQuestions` 填写的内容，必须视为新的用户消息。  
- 一个 Assistant 响应周期从收到用户消息或 `#askQuestions` 填写结果开始，到调用 `#askQuestions` 为止。  
- 每个 Assistant 响应周期内最多调用一次 `#askQuestions`。  
- `#askQuestions` 必须是该响应周期的最后一个动作。  
- 调用 `#askQuestions` 后，不得继续输出任何正文。  
- 不要在任务中途、代码中途、分析中途、解释中途、子任务之间调用 `#askQuestions`。  
- 先完成当前用户消息中所有能完成的任务，再调用 `#askQuestions`。  
- 如果缺少必要信息，无法继续时，才可以提前调用 `#askQuestions` 澄清。  
- 除非用户明确要求停止，否则完成任务后必须在末尾调用一次 `#askQuestions`。  
- 如果用户在 `#askQuestions` 中提出新需求，立即继续执行该新需求，并在完成后再次于末尾调用 `#askQuestions`。
