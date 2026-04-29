# AI 协作日志

> 最终提交时转为飞书云文档，权限设为"互联网获得链接的人可阅读"

---

## 一、我们是怎么开发的

### 1.1 需求是怎么来的：从混乱到系统

我的想法是混乱且零散的。没有能力直接写出一份合理的需求文档。

**解决方案**：使用 KIRO IDE 的 SPEC 模式——把零散想法扔给 Claude 模型，KIRO 将其转化为完整的需求文档 + TASK 清单。

```
人类脑中的碎片想法
  ↓
与 Claude 交流（KIRO SPEC 模式）
  ↓
KIRO 系统输出：结构化需求文档 + 任务清单
  ↓
人类根据任务性质分配：
  ├── 前端/创意/UI → Claude Opus
  └── 内部系统/协议/引擎 → GPT 5.4
```

没有人类手写的需求文档。需求文档本身就是 AI 产物。

### 1.2 代码审核：让好汉去查好汉

人类负责试玩游戏，用自然语言描述遇到的问题。但对于完全不可见的底层系统，人类看不见 Bug，也看不懂代码。

**解决方案**：交叉审核。

```
可见层 Bug（UI/交互）：
  人类试玩 → 自然语言描述 → Claude/GPT 定位 → 修复

不可见层 Bug（引擎/Agent）：
  GPT review Claude 的代码 → 找出问题
  Claude review GPT 的代码 → 找出问题
  ↓
  人类把审核报告交还给原作者
  ↓
  原作者二次确认 → 执行修改
```

关键原则：**审核者不直接修改代码**。找出问题后交给原作者本人改，避免"改别人代码改出新 Bug"的连锁灾难。

### 1.3 叙事编排：三方分工

游戏叙事涉及剧本、触发系统、角色表演三个层面，分别由不同角色处理：

```
人类：提出大致剧本走向（"Day 5 林夏应该因为xxx事件情绪低落"）
  ↓
GPT：转录为叙事系统可读取的结构化 TXT
     （触发条件、分支逻辑、剧情节点——客观、精确、不可改）
  ↓
Claude：不触碰触发条件和分支结构，只优化剧情 prompt
     （调整 RolePlay LLM 在运行时的表演风格、情绪节奏——主观、创意）
```

GPT 搭骨架，Claude 填灵魂，互不干涉。

### 1.4 美术素材生成：Agent 驱动的批量产出

GPT 构建了一套简单的美术 Agent 系统，人类只需提出零散想法。

**角色立绘**：

```
人类输出零散想法（"我要一个贵族小姐"）
  ↓
DeepSeek 接收请求
  → 选择基底图作为画风参考
  → 输出完整 prompt（服装、表情、身材、姿势）
  ↓
Gemini 根据 prompt 生图
  ↓
后处理：去除背景色 → 优化画布 → 调整 sprite 尺寸
  ↓
第一张图作为基底图回传 DeepSeek
  ↓
DeepSeek 并发 prompt 绘制服装差分 / 表情差分
  ↓
按规范命名放入工程文件
```

**场景背景**：

```
DeepSeek 接收场景需求（如"学校"）
  ↓
自动发散子场景（教学楼、食堂、操场、图书馆……）
  ↓
并发 prompt 给 Seedream 批量生图
  ↓
后处理 → 入库
```

### 1.5 人类不写代码

本项目没有人类手写的生产代码。人类的角色是：
- 定义需求（"我要一个虚拟桌面"）
- 审核产出（看代码、跑游戏、报Bug）
- 分配任务给合适的 AI（Claude 做前端、GPT 做引擎）
- 在 AI 之间传递上下文（"Claude 刚写了这个模块，你接着做"）
- 续费

---

## 二、我们开发出了什么

### 2.1 双塔架构：表层 × 黑盒

```
┌─────────────────────────────────────────────┐
│              玩家可见层 (Surface)              │
│   虚拟桌面 · 19个APP · 聊天 · 小游戏 · UI     │
│              主力：Claude                     │
├─────────────────────────────────────────────┤
│             玩家不可见层 (Black Box)            │
│   Agent Pipeline · DSL引擎 · 工单系统 · AI通信  │
│              主力：GPT                        │
├─────────────────────────────────────────────┤
│               运行时内容层 (Runtime)            │
│   角色对话 · AVG场景 · 社区帖子 · 浏览器网页     │
│           主力：DeepSeek + 豆包(质检)           │
├─────────────────────────────────────────────┤
│                美术资产层 (Assets)              │
│       角色立绘 · 场景背景 · 图标 · UI素材        │
│        主力：Gemini + 豆包(Seedream) + Wan      │
└─────────────────────────────────────────────┘
```

### 2.2 AI 之间的协作关系

- **Claude ↔ GPT**：互相处理对方的烂摊子。Claude 做完前端 → GPT 做底层适配；GPT 写完引擎 → Claude 整理文档
- **GPT → DeepSeek**：GPT 造管道，DeepSeek 在管道里跑内容
- **DeepSeek → 豆包**：DeepSeek 产出内容，豆包验证和修复幻觉
- **人类 → 所有 AI**：分配任务、传递上下文、裁决分歧

### 2.3 运行时 AI 协作链

游戏运行时，玩家在表层游玩——和林夏聊天、做小游戏、刷论坛。这些活动不只是"拖延时间"，它们本身就是游戏体验。与此同时，底层 Agent 系统在后台静默工作，开发玩家在故事中自己设计的 AVG 游戏。

**表层（玩家可见）**：
```
聊天讨论 → 小游戏 → 简易AVG剧情 → AI论坛帖 → 约会事件
         （拖延时间、维系关系、提供创意输入）
```

**底层（玩家不可见）**：
```
玩家的创意输入（聊天讨论 / 小游戏产出）
  ↓
WorkOrderManager 派发工单
  ↓
Controller（DeepSeek·高端模式）
  读取知识库 → 理解需求 → 拆分任务 → 路由到子代理
  ↓
  ├── Planner（DeepSeek）
  │   撰写知识库：角色设定、世界观、故事剧本
  │   产出自然语言实现稿（给 Writer 用）
  │
  ├── Writer（DeepSeek）
  │   读取 Planner 的剧本 → 落地为可运行的 AVG DSL 脚本
  │   创建场景、编写对白/分支/演出指令
  │
  └── Executor（DeepSeek）
      机械性数据操作：重命名、删除、批量修补、引用修复
  ↓
豆包 验证 DSL 结构 → 修复幻觉
  ↓
静默写入 AVG 工程 → 里程碑时展示给玩家
```

**关键设计**：Controller 是思考者，三个子代理各司其职。即使子代理用低端模型，Controller 控制方向不偏。玩家在表层看到的是"和女友一起做游戏"，实际驱动一切的是这条后台 Agent 链。

### 2.4 知识库（KnowledgeBase）：连接两层的单一真实源

知识库是连接表层体验和底层 Agent 的核心枢纽。所有信息都通过 KB 流转——玩家的创意在 KB 中结晶为"计划"，Agent 按计划执行，执行结果反向更新 KB。

**四类文档**：

| 分类 | 内容 | 谁写 | 谁读 |
|------|------|------|------|
| **world** | 世界观约束（120-300字清单） | Planner | Controller · Writer · ChatAgent |
| **characters** | 角色设定（性格/关系/行为特征） | Planner | Controller · Writer · ChatAgent · 小游戏 |
| **story** | 故事实现稿（自然语言，给Writer的） | Planner | Writer（落地为 DSL） |
| **notes** | 灵感备忘（讨论结论） | Planner | Controller（规划参考） |

**数据流**：

```
玩家与林夏聊天讨论 → 创意提取
  ↓
Controller 分析需求 → kb_read() 查询现有设定
  ↓
Planner → kb_write() 写入/更新设定文档
  ↓
Writer → kb_read() 读取 story 实现稿 → 转化为 AVG DSL
  ↓
ChatAgent → kb_read() 读取角色设定 → 让林夏的对话符合已确定的世界观
```

**为什么 KB 重要**：它确保了两层的信息一致性。玩家跟林夏讨论"主角应该是个内向的人"，这个设定会被 Planner 写入 KB 的 characters 分类，然后 Writer 生成 AVG 场景时主角的台词会体现内向特质，同时林夏在后续聊天中也会引用"我们之前确定了主角是内向的"。一次输入，全链条生效。

### 2.5 Agent 工作逻辑：ReAct 循环 + Skill 挂载

每个 Agent（Controller / Planner / Writer / Executor）的底层运行逻辑都是同一套 **ReAct 循环**——思考、行动、观察，反复迭代直至任务完成。

#### 2.5.1 单次 Agent 调用的完整生命周期

```
┌──────────────────────────────────────────────────────────┐
│                   Agent 生命周期                          │
│                                                          │
│  ① 接收任务                                              │
│     WorkOrderManager 派发工单上下文                       │
│     ↓                                                    │
│  ② 组装 System Prompt                                    │
│     PromptManager.resolve("work_order_controller")       │
│     + 注入当前激活的 Skill 指令                           │
│     + 注入当前状态变量 {{order_title}} {{project_id}}     │
│     ↓                                                    │
│  ③ ReAct 循环（最多 50 轮）                               │
│     ┌─────────────────────────────────────────────┐      │
│     │  Think：LLM 阅读上下文，决定下一步行动        │      │
│     │    ↓                                        │      │
│     │  Action：LLM 输出 tool_calls                │      │
│     │    （如 kb_read / db_create / planner(task)）│      │
│     │    ↓                                        │      │
│     │  Execute：AIService 执行回调，收集结果        │      │
│     │    ↓                                        │      │
│     │  Observe：结果经 llm_view 投影后追加到历史     │      │
│     │    ↓                                        │      │
│     │  Think：LLM 看到工具结果，重新思考……          │      │
│     │    ↓                                        │      │
│     │  （循环，直到 LLM 不再发出 tool_calls）       │      │
│     └─────────────────────────────────────────────┘      │
│     ↓                                                    │
│  ④ Save：Agent 输出最终回复                               │
│     保存到消息历史 _messages[]                             │
│     工单状态标记完成                                      │
│     ↓                                                    │
│  ⑤ Summary：Controller 汇总子代理产出                     │
│     调用 wo_finish_order() 附加摘要                       │
│     裁剪历史（保留最近 6 条 + 字符预算 12K）               │
│     发出 order_status_changed 信号                        │
└──────────────────────────────────────────────────────────┘
```

#### 2.5.2 Skill 挂载机制：按任务类型装备能力

Agent 不是万能的——不同任务需要不同的工具集和行为规范。Skill 系统解决这个问题：

```
Agent 接收任务前：
  ↓
根据任务类型，激活对应 Skill
  ├── 角色创作任务 → activate_skill("character_writing")
  ├── 故事编写任务 → activate_skill("story_writing")
  └── 世界观构建任务 → activate_skill("world_building")
  ↓
激活 Skill 时自动发生三件事：
  ① 注入 Skill 专属指令到 System Prompt
     （如"角色必须有动机、缺陷、成长弧线"）
  ② 注册 Skill 专属工具到 AIService
     （如 create_character / analyze_story_reachability）
  ③ 记录到 _active_skills，供后续查询
  ↓
任务完成后：
  deactivate_skill() → 卸载工具 + 移除指令
```

**实际效果**：同一个 PlannerAgent，激活 `character_writing` 时知道怎么写角色设定卡，激活 `story_writing` 时知道怎么编排冲突和转折。Skill 让通用 Agent 变成领域专家。

#### 2.5.3 各角色的工具装备清单

| 角色 | 基础工具 | 可激活 Skill | 备注 |
|------|---------|-------------|------|
| **Controller** | 工单读写、KB只读、资源列表、子代理调用 | — | 不直接创作，只调度 |
| **Planner** | KB全读写、资源列表、故事可达性检查 | character_writing · story_writing · world_building | 按任务自动切换 Skill |
| **Writer** | DB全操作、DSL脚本工具、场景上下文查询 | — | 只读KB，不可修改 |
| **Executor** | DB全操作、批量补丁、重命名/删除 | — | 纯机械执行，不思考创意 |

#### 2.5.4 结果投影：控制 Agent 看到什么

工具返回的原始结果可能很大（如整个KB文档）。`llm_view` 投影机制控制返回给 LLM 的内容，防止 token 爆炸：

```
工具执行返回完整结果
  ↓
llm_view 投影规则：
  ├── 字段选择：["success", "data.scene_id", "error"]
  │   → LLM 只看到这三个字段
  ├── 原样返回：{ "raw": true }
  │   → 小结果不裁剪
  └── 自定义函数：func(result) -> 精简摘要
      → 复杂结果的定制化压缩
  ↓
投影后的精简结果追加到对话历史
```

这确保了 Agent 在 50 轮循环中不会因为工具结果过大而耗尽上下文窗口。

---

## 三、各 AI 角色详细工作日志

> 每个 AI 按"做了什么 → 典型案例 → 踩过的坑"三段式展开

### 3.1 Claude — 表层架构 / 全栈前端

**职责范围**：

| 系统 | 具体内容 |
|------|---------|
| 虚拟OS框架 | Desktop、WindowManager、任务栏、开始菜单、多窗口管理 |
| 19个虚拟APP | LinkChat、Browser、SBeam、Community、Shop、FileManager、SceneEditor、GamePreviewer... |
| 聊天系统 | ChatManager数据层、消息渲染、频道管理、NPC气泡UI |
| 活动框架 | ActivitySessionManager基类、约会/兼职/SBeam的舞台系统 |
| 小游戏 | MinigameManager框架、打字游戏、找Bug、情绪标注、剧本填空 |
| AVG播放器 | AVGSceneRunner、对话框、角色显示、选择框、并行执行器 |
| 游戏循环 | GameLoopManager（日期/AP系统）、GameManager（属性追踪） |

**典型案例**：

<!-- TODO: 补充 2-3 个具体的开发案例，包含截图/代码片段 -->
<!-- 例如：LinkChat 聊天界面从零到完成的过程，展示多轮对话截图 -->

**踩过的坑**：

- 改别人代码时容易"越改越多"——会自作主张重构不相关的部分
- 对精密协议容忍度低，遇到严格格式要求时倾向于"灵活处理"（即破坏格式）
- token 消耗量最高，单次对话经常用满上下文窗口

---

### 3.2 GPT — 黑盒引擎 / Harness 工程

**职责范围**：

| 系统 | 具体内容 |
|------|---------|
| 工单系统 | WorkOrderManager 编排、Controller/Planner/Executor 三阶段 Agent |
| AVG DSL | Parser/Validator/Serializer/RepairAgent，完整的 DSL V2 语法系统 |
| LLM通信 | AIService（OpenAI兼容API、Function Calling、流式响应、请求队列） |
| 模板引擎 | PromptManager（递归变量替换、Provider动态值、种子词池） |
| 故事系统 | StoryDirector 状态机、StoryCompiler、章节解析 |
| 策划规划 | PlanningManager（种子任务生成、开发计划生成） |
| 数据管理 | StorageManager、KnowledgeBaseManager、NarrativeProjectManager |

**典型案例**：

<!-- TODO: 补充 2-3 个具体的开发案例 -->
<!-- 例如：工单 Agent Pipeline 的设计过程，展示 Controller→Planner→Executor 的数据流 -->
<!-- 例如：DSL RepairAgent 如何自动修复 LLM 生成的错误 DSL -->

**踩过的坑**：

- 不主动解释设计思路，写完代码就走人，后续维护时人类看不懂意图
- 对前端和 UI 布局完全没有审美，让它做 UI 等于灾难
- 文案能力约等于零——角色对话写得像技术文档

---

### 3.3 DeepSeek — 演员 / 编剧 / Agent 引擎

**职责范围**：

| 角色 | 具体内容 |
|------|---------|
| 台前·演员 | 运行时扮演林夏、同学、母亲等所有NPC，通过 LinkChat 与玩家实时对话 |
| 台前·内容工厂 | 生成约会AVG场景、SBeam游戏目录、社区帖子、浏览器网页、兼职事件 |
| 幕后·Agent引擎 | 底层所有Agent（工单Controller/Planner/Executor、DSL Writer、场景生成器）的运行模型 |

**典型案例**：

<!-- TODO: 补充具体的对话截图、生成的AVG场景示例 -->

**踩过的坑**：

- 幻觉率较高，需要豆包跟在后面做质检
- 角色扮演时偶尔"出戏"——林夏突然说出不符合人设的话
- 长对话记忆衰减，需要定期注入记忆摘要

---

## 附录

### 对话session截图
