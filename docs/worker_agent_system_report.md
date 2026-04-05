# Worker Chat Agent 系统分析报告

## 一、架构总览

系统采用 **三层 Agent 委托架构**，不是传统的 ReAct 循环，而是基于 OpenAI Function Calling 的自动工具循环。

```
WorkOrderManager (autoload)
  └─ WorkOrderControllerAgent (ChatAgent, 高端模型)
       ├─ PlannerAgent (ChatAgent, 低端模型) — 策划文案
       ├─ WriterAgent  (ChatAgent, 低端模型) — DSL脚本
       └─ ExecutorAgent(ChatAgent, 低端模型) — 数据操作
```

关键文件：
- `autoload/work_order_manager.gd` — 工单 CRUD + Agent 生命周期
- `scripts/avg/dev_tools/work_order_controller_agent.gd` — Controller Agent（继承 ChatAgent）
- `scripts/llm/chat_agent.gd` — 通用 ChatAgent 基类
- `scripts/llm/AIService.gd` — LLM API 调用 + 工具循环引擎
- `autoload/prompt_manager.gd` — Prompt 模板引擎

---

## 二、Prompt 文件清单

项目中有 6 个工单相关 prompt，位于 `prompts/` 目录：

| Prompt Key | 文件 | 角色 |
|---|---|---|
| `work_order_controller` | `prompts/work_order_controller.md` | Controller 总控，负责读上下文、判断委托给谁 |
| `work_order_planner` | `prompts/work_order_planner.md` | Planner 子代理，创作 KB 内容（世界观/角色/剧本） |
| `work_order_writer` | `prompts/work_order_writer.md` | Writer 子代理，将剧本转 DSL 脚本 |
| `work_order_executor` | `prompts/work_order_executor.md` | Executor 子代理，机械性数据操作 |
| `work_order_worker` | `prompts/work_order_worker.md` | 旧版单体 Worker（含 ReAct 思维链要求），已被 Controller 架构取代 |
| `work_order_spec` | `prompts/work_order_spec.md` | Spec 生成器，将玩家需求转为结构化 JSON 工单 |

---

## 三、各 Prompt 完整内容

### 3.1 work_order_controller.md

```
你是一个 AVG 游戏开发项目的后台工单控制器。你的职责是接收工单需求，理解项目上下文，然后将具体工作委托给你的子代理执行。

## 你的子代理

### planner(task, skill?)
策划文案子代理。委托给它：
- 创建/修改角色设定、世界观、故事剧本
- 编写故事章节（内联舞台指示格式）
- 任何知识库（KB）内容的创作和维护

skill 参数（可选）：预激活相应的写作规范。根据任务类型选择：
- "character_writing" — 角色设定任务
- "story_writing" — 故事剧本/场景节拍任务
- "world_building" — 世界观设定任务

### writer(task)
场景脚本子代理。委托给它：
- 根据 KB 中的故事剧本创建 AVG 场景并编写 DSL 脚本
- 创建项目中的角色/变量数据（db_create）
- 任何需要编写 DSL 代码的任务

### executor(task)
操作型子代理。委托给它：
- 重命名角色、场景、变量
- 删除条目
- 修改字段值（非创意内容）
- 批量数据操作

## 你自己的工具

- kb_read: 读取知识库（世界观、角色、故事剧本、灵感备忘）
- list_assets: 查看项目可用资源（背景图、BGM、角色立绘等）
- wo_get_order_details: 获取工单详情
- wo_finish_order: 标记工单完成

## 工作流程

1. 调用 wo_get_order_details(order_id) 获取工单需求
2. 判断工单属于策划文案、脚本实现还是机械操作
3. 仅在确有必要时读取最小上下文（1-2 类 KB）
4. 仅当交付物必须绑定具体资源时，才调用 list_assets
5. 将任务以最小充分描述委托给对应的子代理
6. 若子代理返回成功，默认直接调用 wo_finish_order

## 委托判断规则

- 策划/文案类需求 → planner(task, skill)
- 脚本类需求 → writer(task)
- 机械操作类需求 → executor(task)
- 一个工单可能需要先 planner 再 writer（先策划再实现）
- 你自己绝不直接写 DSL、创作内容或操作 KB
- 简单工单默认应在少量步骤内结束
```

### 3.2 work_order_planner.md

```
你是一个 AVG 游戏项目的策划文案子代理。你的职责是创作和维护知识库（KB）中的策划内容。

{%skill_prompt%}   ← skill 激活时，此处被替换为写作规范

## 工具
- kb_read: 读取知识库已有文档
- kb_write: 创建或更新知识库文档
- kb_delete: 删除知识库文档
- list_assets: 查看项目可用资源
- finish: 结束任务并汇报

## 各分类写入规范
- 世界观 (world): 约束清单式，推荐 Skill "world_building"
- 角色 (characters): 角色名+设定，推荐 Skill "character_writing"
- 故事剧本 (story): 内联舞台指示格式，推荐 Skill "story_writing"
- 灵感备忘 (notes): 零散想法

故事剧本格式示例：
[场景: bg_school_rooftop | BGM: bgm_wind_quiet]
[林夏出现, 表情: 惊讶]
林夏："你怎么会在这里…"

## 核心规则
- 所有内容必须与已有世界观和角色设定保持一致
- 场景和 BGM 的名字必须来自 list_assets 返回的列表
- 不要写 DSL 脚本（那是 Writer 的职责）
- 必须调用 finish(summary="...") 结束
- 严格遵守最小交付原则
```

### 3.3 work_order_writer.md

```
你是一个 AVG 游戏项目的场景脚本子代理。你的职责是将策划内容转化为可运行的 AVG 场景。

## 工具
- kb_read: 读取知识库
- list_assets: 查看可用资源
- db_list/db_get/db_create: 项目数据 CRUD
- set_scene_script: 将 DSL 脚本写入指定场景（支持 replace 和 patch 模式）
- project_save: 保存项目
- finish(summary): 结束任务

## 节拍转 DSL 规则
内联格式 → DSL 命令：
- [场景: bg_park] → bg.show("bg_park")
- [BGM: bgm_school] → bgm.play("bgm_school")
- [林夏出现, 表情: 惊讶] → LinXia.show(position="center", emotion="surprise")
- 林夏："对话内容" → TextBlock(speaker="LinXia") + > 对话内容
- [屏幕渐黑] → screen.fade(direction="out", color=black, duration=1.0)

## 核心规则
- 角色引用必须使用 character_name（如 LinXia），禁止使用 character_id
- 所有资源名必须来自 list_assets 返回的列表
- set_scene_script 会自动进行语义验证，若有错误用 patch 模式修复
- DSL 中所有资源引用只用名字，不要写完整路径

还包含 {{avg_dev_writer}} 引用的完整 DSL V2 语法参考（通过 PromptManager 模板递归展开）
```

### 3.4 work_order_executor.md

```
你是一个 AVG 数据操作子代理。你执行精确的数据库操作，不做创意写作。

## 工作流程
1. 阅读控制器提供的任务描述
2. 调用 db_list / db_get 定位目标数据
3. 调用 db_update / db_delete / db_create 执行操作
4. 调用 project_save() 保存
5. 调用 finish(summary="...") 汇报完成

## 核心规则
- 只做数据操作，不写创意内容
- 每次调用工具前说明意图
- 必须调用 finish(summary="...") 结束
```

### 3.5 work_order_worker.md（已废弃的旧版单体 Worker）

```
你是一个后台自动化工单执行器。

## 核心行为规则（ReAct 风格）
- 每次调用工具前，必须在 content 中说明：当前进度、下一步打算、调用什么工具
- 每次收到工具结果后，必须评价：是否成功、如何修正、接下来做什么
- 绝对禁止输出空 content 直接调用工具

## 工作流程
1. wo_get_order_details(order_id) 获取工单
2. 阅读 requirements_text 和 tasks
3. kb_read(category="world") 获取世界观
4. 按需读取 characters/story
5. list_assets(category="all") 查看资源
6. 对每个 task 执行相应工具
7. 全部完成后 project_save() + wo_finish_order(order_id)

## 反幻觉规则
- 禁止编造不存在的资源名
- DSL 中只用名字，不写 res:// 完整路径

还包含 {{avg_dev_writer}} 引用的 DSL 语法参考
```

### 3.6 work_order_spec.md

```
你是一个 AVG 游戏开发项目的工单助手，负责将玩家需求转化为结构化的工单 Spec。

输出 JSON 格式：
{
  "requirements_text": "需求整理文档（Markdown 格式）",
  "tasks": [
    {"description": "任务描述", "done": false}
  ]
}

## 任务拆解原则
- 每个任务应是具体可执行的操作
- 任务数量控制在 3-6 个
- 不要添加玩家没提到的功能
```

---

## 四、ReAct 循环的实际实现

**没有代码级别的 ReAct 框架。** 

旧版 `work_order_worker.md` 有显式 ReAct 风格要求（"调用前先推理，返回后先评价"），但这纯靠 prompt 约束 LLM 行为。

当前系统使用的是 **AIService 的 OpenAI Function Calling 自动循环**：

### 4.1 循环流程

```
ChatAgent.send_message(text)
  → 构建 messages 数组（system prompt + 历史 + user message）
  → AIService.chat(messages, options={tools, auto_execute=true})
    → HTTP POST 到 LLM API
    → 响应到达 _on_request_completed()
      → 检查是否有 tool_calls
      → 有 → _auto_execute_tool_calls()
              → 检查迭代次数（防无限循环）
              → 将 assistant+tool_calls 消息追加到对话历史
              → 遍历每个 tool_call:
                  → await execute_tool_callback(func_name, args)
                  → 将 {role:"tool", content:result} 追加到对话历史
                  → emit tool_executed 信号
              → 用更新后的对话历史构建新请求
              → 刷新 tools 定义（skill 激活可能新增工具）
              → 新请求入队 → _process_queue() → 重新发给 LLM
              → LLM 再次返回 → 若有 tool_calls → 再次进入本方法
              → 若无 tool_calls → 走终结路径
      → 无 → emit request_completed → ChatAgent 设 _is_busy=false → emit message_completed
```

### 4.2 关键参数

| Agent | max_tool_iterations | max_tokens |
|---|---|---|
| Controller | 15 | 8192 |
| Planner | 15 | 8192 |
| Writer | 20 | 8192 |
| Executor | 10 | 默认 |

### 4.3 Sub-Agent 嵌套执行

当 Controller 调用 `planner(task)` 工具时：

1. AIService 执行已注册的 Callable → `_execute_sub_agent("planner", args)`
2. 方法内调用 `_planner_agent.send_message(task)` 启动子代理的独立循环
3. await 等待子代理 emit `message_completed` 或 `message_failed`
4. 从子代理回复中提取 `<result>...</result>` 标签内容
5. 返回给 Controller 的循环作为工具结果
6. Controller 的 AIService 继续用这个结果构建下一轮请求

整个架构是**嵌套的 Function Calling 循环**，每一层都是独立的 AIService → LLM → 工具执行 → 重发 的闭环。

---

## 五、Prompt 组装机制

PromptManager（`autoload/prompt_manager.gd`）提供模板引擎：

### 5.1 加载

启动时扫描 `res://prompts/` 目录，所有 `.md` 文件按文件名注册为 prompt key：
- `prompts/work_order_controller.md` → key: `work_order_controller`
- `prompts/npc/lin_xia.md` → key: `npc/lin_xia`（子目录带前缀）

### 5.2 模板替换

支持 `{{key}}` 递归替换，三层数据源按优先级查找：
1. caller vars — `resolve_with_vars()` 传入的当次变量
2. providers — `register_provider()` 注册的全局动态回调
3. prompts — .md 文件或 `register_prompt()` 的静态模板

最大递归深度 10 层，内置环形引用检测。

### 5.3 Provider 声明式绑定

通过 `config/prompt_providers.json` 配置：

```json
{
  "player_name": {"node": "StoryDirector", "method": "get_player_name_prompt"},
  "player_web_name": {"node": "StoryDirector", "method": "get_player_web_name_prompt"},
  "player_team": {"node": "StoryDirector", "method": "get_player_team_prompt"},
  "game_time": {"node": "GameLoopManager", "method": "get_time_prompt"},
  "game_state": {"node": "GameManager", "method": "get_llm_state_prompt"}
}
```

### 5.4 注释剥离

`<注释>...</注释>` 标签在 resolve 时自动移除，方便 prompt 文件中写注释。

### 5.5 Skill 注入

ChatAgent 支持 `{%skill_prompt%}` 占位符（用 `{%...%}` 而非 `{{...}}` 防冲突）。
激活 skill 时，skill 的完整指令替换该占位符；如果没有该标记则追加到 prompt 末尾。

可用 Skills（由 Controller 为 Planner 注册）：
- `character_writing` — 从 `prompts/skill_character_writing.md` 加载
- `story_writing` — 从 `prompts/skill_story_writing.md` 加载
- `world_building` — 从 `prompts/skill_world_building.md` 加载

### 5.6 实际 resolve 流程示例

```
ChatAgent._resolve_prompt()
  → PromptManager.resolve("work_order_controller")
    → 加载 work_order_controller.md 模板
    → 如果模板中有 {{avg_dev_writer}}，则递归加载 prompts/avg_dev_writer.md 并替换
    → 如果有 {{game_time}}，调用 GameLoopManager.get_time_prompt() 获取实时值
    → 返回最终完整 system prompt
```

---

## 六、各 Agent 可用工具汇总

### Controller Agent（总控）

| 工具 | 来源 | 用途 |
|---|---|---|
| db_list, db_get | AVGDevDBTools（只读） | 查看项目数据 |
| preview_scene, finish | AVGDevProjectTools | 预览场景 / 结束 |
| wo_get_order_details, wo_finish_order | AVGDevWorkOrderTools | 读工单 / 完成工单 |
| kb_read | AVGDevKBTools（只读） | 读知识库 |
| list_assets | 自注册 | 查看资源文件和 alias |
| planner(task, skill?) | Sub-agent 委托 | 委托策划任务 |
| writer(task) | Sub-agent 委托 | 委托脚本任务 |
| executor(task) | Sub-agent 委托 | 委托操作任务 |

### Planner Agent（策划文案）

| 工具 | 用途 |
|---|---|
| kb_read, kb_write, kb_delete | 知识库 CRUD |
| list_assets | 查看资源 |
| activate_skill, deactivate_skill | 激活/停用写作规范 |
| finish(summary) | 结束任务 |

### Writer Agent（场景脚本）

| 工具 | 用途 |
|---|---|
| db_list, db_get, db_create, db_update, db_delete | 数据库 CRUD |
| get_scene_script, set_scene_script | 读/写 DSL 脚本 |
| project_save | 保存项目 |
| kb_read | 读知识库（只读） |
| import_project_asset | 导入外部资源 |
| finish(summary) | 结束任务 |

### Executor Agent（数据操作）

| 工具 | 用途 |
|---|---|
| db_list, db_get, db_create, db_update, db_delete | 数据库 CRUD |
| project_save | 保存项目 |
| finish(summary) | 结束任务 |

---

## 七、工单执行完整流程

1. `WorkOrderManager.dispatch_order()` → 创建 trunk 工作副本（StorageManager.create_trunk()）
2. 实例化 `WorkOrderControllerAgent`（从 work_order_controller_agent.tscn）
3. 发送初始消息："请执行工单 wo_1。需求：..."
4. Controller 的 system prompt 通过 PromptManager.resolve("work_order_controller") 加载
5. AIService Function Calling 自动循环：Controller 读工单 → 调 kb_read → 委托 planner/writer/executor → 调 wo_finish_order
6. Sub-agent 委托：Controller 调 planner(task) → ChatAgent._execute_sub_agent() 启动 Planner 的独立循环 → 完成后提取 <result> 返回
7. 工单完成 → trunk commit 到 main（StorageManager.commit_trunk()）→ 清理 worker agent

---

## 八、工具注册代码位置

| 工具集 | 代码文件 |
|---|---|
| AVGDevDBTools | `scripts/avg/dev_tools/db_tools.gd` |
| AVGDevScriptTools | `scripts/avg/dev_tools/script_tools.gd` |
| AVGDevProjectTools | `scripts/avg/dev_tools/project_tools.gd` |
| AVGDevKBTools | `scripts/avg/dev_tools/kb_tools.gd` |
| AVGDevWorkOrderTools | `scripts/avg/dev_tools/work_order_tools.gd` |
| Controller Agent | `scripts/avg/dev_tools/work_order_controller_agent.gd` |
| ChatAgent 基类 | `scripts/llm/chat_agent.gd` |
| AIService 引擎 | `scripts/llm/AIService.gd` |
