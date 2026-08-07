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

# 项目定位与基础设施边界

当前仓库就是新游戏本体，游戏类型、世界观、角色关系、核心循环和正式内容尚未确定。

当前明确保留的能力：

- 桌面壳、窗口管理、应用注册与启动等通用桌面基础设施。
- 游戏本体的 AVG 数据、剧情 DSL、解析、校验、动态生成、播放与资源索引等通用 AVG 基础设施。
- 被上述能力实际依赖的存储、LLM 调用、提示词装配和只读知识检索能力。

默认不作为新游戏前提的内容：

- 旧比赛、旧项目、工单、开发循环、策划代理，以及“在游戏里开发游戏”的玩法和文案。
- 旧角色、恋爱关系、日期推进、养成数值、兼职、约会、商店、社区等具体题材与玩法。
- 为旧玩法服务的应用入口、测试、示例剧情、知识条目和提示词。

处理后续需求时：

- 不根据旧内容推断新游戏题材；需要题材、角色或核心循环时，以用户的新需求为准。
- 新功能优先复用通用基础设施，但不要为了保留旧实现而让新游戏继承旧规则。
- 基础设施与具体游戏内容保持边界：通用层不硬编码角色名、关系、比赛、项目目标或玩法数值。
- 本体只维护一份 AVG 游戏数据；不要引入多项目切换、项目模板、`narrative_projects/` 或同类目录结构。
- 示例和测试使用中性最小数据，只验证稳定技术契约，不把示例设定写成产品规则。
- 调试工具和内部编辑入口默认不出现在正式玩家桌面；只有用户明确要求时才接入玩家流程。

# Godot 开发规范

## 可用工具

- **Godot Tool 扩展**: 检测 GDScript 语法错误
- **Godot MCP**: 运行项目、获取调试输出、创建场景/节点等
- **注意**: 无法操纵运行中的程序，需结合自动测试和用户手动测试

## 测试策略

1. 默认不为简单 UI 调整或局部代码修改启动项目、操作运行中的界面或进行实机验收，除非用户明确要求。
2. 简单改动以静态检查、差异检查和必要的语法检查为限；不要为了证明“已经修改”追加运行、点击、截图或长流程验证。
3. 确实需要验证逻辑时，优先编写最小自动测试，由测试脚本操纵场景并通过 `print` 输出关键状态；最后读取输出判断结果，避免人工操作 UI。
4. 测试必须以“场景 + 脚本”成对存在，禁止单脚本运行
   - 每个 `test_xxx.gd` 都必须有对应的 `test_xxx.tscn`
   - 当前不维护通用基础设施全量回归测试；只有具体功能存在稳定契约时才新增对应测试
   - 自动测试放在 `tests/automated/<domain>/`
   - 人工打开、交互、目视检查的入口放在 `tests/playtest/<domain>/`，文件名使用 `playtest_`
   - 真实 LLM/API、长流程实验、配置诊断入口放在 `tests/lab/<domain>/`
   - 不再新增 `scripts/tests/` 或 `scenes/tests/` 分离式测试入口；测试脚本和测试场景保持同名同目录
   - Godot 的 autoload 单例只有在运行场景时才会被引擎实例化
   - 单脚本运行时 autoload 不存在，访问任何 autoload 节点必定报错
   - 因此所有测试都必须通过对应测试场景运行，例如 `mcp_godot_mcp_run_project` 指定对应 `.tscn`
5. 仅在用户要求验收，或改动风险确实需要运行验证时，使用 mcp 运行对应测试场景并读取输出；不要默认打开正式游戏后人工操作。
6. **重操作验收默认交给用户**：拖拽手感、hover/glow、落点对齐、布局观感、交互节奏、截图对比、反复试玩等，代理不得自行开局验收循环；改完后告知 playtest 入口即可，等用户反馈再修。
7. **严禁**使用单脚本无场景测试（即使是 `@tool` + `EditorScript` 也不推荐，因为无法测试依赖 autoload 的逻辑）
8. **严禁在测试脚本中添加自动退出逻辑**（如 `get_tree().quit()`、定时器退出等）
   - 自动退出会导致进程在 MCP 调用 `get_debug_output` 之前就已终止，无法获取任何输出
   - 测试场景必须保持运行状态，由用户手动关闭或通过 `mcp_godot_mcp_stop_project` 停止
   - 正确流程：运行测试 → 调用 `get_debug_output` 获取输出 → 调用 `stop_project` 停止

### 游戏 UI 文案与玩家视角

- 写任何玩家可见文案前，先回答：玩家此刻想知道什么、能做什么、会获得什么反馈。
- UI 文案服务玩家决策和情绪，不展示实现过程、开发动作、测试状态或功能清单。
- 避免在玩家界面提到内部机制、预生成、初始化、资源注入、后台任务、测试场景、技术调试名词；只有当这些词是玩家实际看到并操作的游戏对象时才使用。
- 说明模式、入口、按钮、状态差异时，用玩家体验维度表达：剧情节奏、可用行动、角色互动、创作自由度、解锁范围、风险和限制。
- 内部工具默认不出现在正式玩家入口；只有用户明确要求时才设计其玩家侧文案和交互。
- 禁止使用 emoji 充当图标、按钮标识、状态提示或其他 UI 元素，除非用户明确要求使用 emoji。
- 写完文案后删掉所有无法回答“玩家为什么需要知道”的句子。
- 不为了让 UI 看起来更“完整”添加说明。信息量以玩家完成当前选择所需为准。

### 游戏 UI 验收

- 除非用户明确要求验收，UI、美术、布局、拖拽、卡牌交互和局部代码改动完成后：**不启动项目、不模拟点击/拖拽、不截图、不开 playtest 自测循环**。
- 代理完成改动后的交付边界：静态/语法检查通过 + 指出对应 `playtest_` 入口；手感与视觉验收由用户完成。
- 禁止为“看起来验过了”反复：`play_scene` → 截图 → 模拟输入 → 再截图 → 再改。这类重操作浪费大量时间，收益极低。
- 用户要求验收时，UI、美术、布局和玩家体验改动不用脆弱 smoke test 作为主要依据。
- 逻辑结果可以自动判断时，优先使用“测试场景 + 测试脚本”驱动，并通过 `print` 输出关键状态；不要把人工点击当作默认验证方式。
- 不为了证明“能跑”维护复杂 smoke，也不默认打开正式游戏入口反复操作。
- 自动测试只覆盖稳定契约：解析器、数据验证、故事入口信号、播放完成回调、资源索引等。
- 不给频繁变化的 UI 节点名、像素尺寸、临时排版写长期断言，除非用户明确要求把某个布局约束固定为规则。
- 主观视觉质量与交互手感默认由用户在真实窗口中判断并反馈；只有用户明确要求时，代理才可截图或操作 playtest。
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

## 禁止用 scale / z_index 适配 UI

不可通过强行修改 `Control.scale` 或 `Control.z_index` 让节点“塞进”某个容器或区域。这是脆弱写法，不是布局手段。

- 节点尺寸用 `custom_minimum_size` / `size` / 锚点 / 容器布局表达，不用 `scale` 表达。
- 卡牌、槽位、手牌等 UI 元素的“显示大小”由其真实 `size` 决定；内容用锚点自适应，而不是把节点画成原尺寸再缩小。
- `z_index` 只用于临时层级（拖拽时浮起、tooltip 置顶），不用来“修”渲染顺序问题或替代正确的节点层级。
- `scale` 仅允许作为短时视觉反馈（hover 微放大、拿起放大、落位回弹），动画结束必须回到 `1.0`；不得把 `scale` 当作持久显示比例。
- 需要不同尺寸的同一元素时，做成可复用场景并用 `custom_minimum_size` 指定尺寸，或为该尺寸单独建场景；不要用 `scale = 0.55` 之类硬凑。

违反这条规则会出现：hover/动画把 scale 冲掉、布局算坐标时漏算 scale、容器 hit-test 与视觉不一致、拖拽落位 scale 回不到 1.0 等问题。

## 关于回复  
- 用户主要使用中文，默认用中文回复。  
