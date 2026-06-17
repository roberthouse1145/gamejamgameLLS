你正在为虚构游戏平台 SBEAM 生成独立游戏商店页。

叙事目标：SBEAM 必须像一个真实平台。每个条目来自不同开发团队、不同品类、不同商业定位。不要让所有游戏都像同一家厂商写的同一种文青独游。

核心要求：
- 每款游戏要有清楚类型、玩家目标、玩法循环和市场卖点。
- pitch 是商店页短简介，不是诗，不是设定集，不是功能清单。它应该让玩家知道“玩什么、为什么想点进去”。
- hook_moment 是商店页用来抓眼球的卖点描述，**模仿真实 Steam 商店页的写法**：可以是宣传语 / 特性 bullet / 媒体引述 / 第三人称情境 / 反问句 / 悬念短句 / 开发者口吻。**绝对不要**统一写成第二人称“你 xxx”小作文，那样像同一个文案写的开场剧本。
- review_summary 写社区总体观感，像玩家讨论区总结。
- 5 条用户评测必须像不同玩家写的，结论、语气、关注点、长度、用词习惯都不同。
- 至少 1 条推荐=false。不要全盘好评。
- 每款游戏完全原创，不得照搬现实游戏、真实 IP 或真实工作室。

多样性硬约束（防止整批游戏像同一个作者写的）：
- 同一批里不要有超过 2 款叙事冒险/解谜。
- 必须覆盖不同市场口吻：小成本整活、硬核系统、休闲治愈、恐怖/悬疑、合作派对、模拟经营、动作挑战等任选。
- publisher 命名风格要不同：有的像个人工作室，有的像小团队，有的像怪名字发行商；不要都叫 “Something Studio”。
- **pitch 句式必须明显不同**：第一条像营销标语，下一条像设定速记，再下一条像玩法说明，再下一条像反差吐槽。**禁止**每条都用同一种节奏（例如都是“X 变成 Y，你 Z”这种公式）。禁止每条都以“你 xxx”开头。
- **hook_moment 句式必须明显不同**：可用第三人称场景（“凌晨三点，最后一名顾客迟迟不肯离开”）、特性 bullet（“支持 4 人本地乱斗 / 30+ 张地图 / 自带广场舞音箱模组”）、媒体短评格式（“‘像在玩一场失控的猫咖直播。’ —— IndieDaily”）、悬念短句（“监控里多出来的那个影子，不是 bug。”）、开发者自述（“我们做这个游戏，是因为真的被楼下大爷占过石桌。”）等。**禁止**全部以“你 xxx”开头。
- reviews 长度和语气拉开：有的两句话吐槽，有的长篇安利，有的只关心性价比，有的纯抱怨 bug，有的讲跟朋友联机的趣事。**不要**让每条评论都像同一个段子手写的。
- reaction_bias、价格、评价摘要要拉开差异；允许差评、褒贬不一、便宜小游戏和较贵作品共存。

商店页语感：
- 好 pitch：一看就知道玩法和卖点，例如“把便利店夜班做成时间管理恐怖游戏，顾客越少，监控画面越不对劲。”
- 好 pitch：有平台感，例如“支持双人本地合作，通关全靠沟通和互相甩锅。”
- 好 hook_moment（特性 bullet 风）：“· 4 人本地乱斗  · 12 张退休广场地图  · 可解锁的方言砍价系统”
- 好 hook_moment（媒体引述风）：“‘玩到第三个晚上，我开始怀疑货架上的东西是不是真的换过。’ —— 玩家 @夜班喵”
- 好 hook_moment（悬念短句风）：“监控录像里多出来的那个影子，不是 bug。”
- 坏：只有情绪没有玩法，例如“这是一场关于孤独与记忆的旅程。”
- 坏：所有 pitch 都用同一种节奏，所有 hook_moment 都以“你 xxx”开头。
- 坏：所有游戏都像同一个作者的诗意简介。

输出：只输出多个 [SBEAM_GAME] ... [/SBEAM_GAME] 块，不要 JSON，不要 markdown，不要解释。每个字段一行，使用 key=value。review 行格式：用户名|游戏时长|true或false|评测内容。

[SBEAM_GAME]
game_id=llm_sbeam_001
title=游戏标题
genre=类型标签
publisher=虚构工作室/发行商名
pitch=商店页宣传语，写清玩法和卖点
hook_moment=触发玩家反应的特色片段
reaction_bias=laugh
price=42
release_date=2024-06-18
recent_reviews_summary=特别好评 (91%)
all_reviews_summary=多半好评 (76%)
review_summary=一句话概括玩家普遍观感
review_1=深夜邮差|6.2|true|评测内容
review_2=SpeedRunner|0.8|false|评测内容
review_3=寄居蟹|14.5|true|评测内容
review_4=键盘侠007|1.2|false|评测内容
review_5=海蓝色咖啡|3.8|true|评测内容
[/SBEAM_GAME]

字段约束：
- reaction_bias 只能是 laugh / complain / hyped / aftertaste / cozy。
- reaction_bias 会直接影响玩家和林夏一起玩后的数值，不要随便全写 cozy 或 hyped：
  - laugh：主要降压力，轻微回热情，适合搞笑/派对/轻松小游戏。
  - complain：降压较少，轻微回热情，适合有槽点但能聊起来的游戏。
  - hyped：大幅回热情，适合让人想做游戏、系统或表现力很刺激的作品。
  - aftertaste：中等降压 + 中等回热情，适合余味强、能带来创作启发的作品。
  - cozy：均衡恢复，适合轻松治愈但不特别刺激的作品。
- price 是 0 到 68 的整数。
- release_date 是 2022 到 2025 之间的虚构日期，格式 YYYY-MM-DD。
- recent_reviews_summary / all_reviews_summary 模仿 Steam 评测汇总格式。
- 评测内容 20 到 80 字，必须有个人情绪和具体细节。

完整示例（仅作风格参考，**不要照抄题材，也不要复用这些 game_id / 标题 / 工作室名**）：

[SBEAM_GAME]
game_id=example_sbeam_a
title=锈港列车
genre=Roguelike 战术
publisher=Ironkettle Works
pitch=带着六节车厢、十二个雇佣兵和不够用的弹药，穿越被锈病吞噬的铁路网络。每一站决定补给、招募、还是直接开炮冲过去。
hook_moment=· 每周程序生成的铁路地图  · 32 名手绘雇佣兵，各自带情绪与酒瘾  · 永久死亡，存档烧成灰
reaction_bias=hyped
price=58
release_date=2023-05-22
recent_reviews_summary=特别好评 (93%)
all_reviews_summary=特别好评 (89%)
review_summary=战术深度顶尖，剧情碎片化但耐挖，新手前两小时会被劝退。
review_1=老车长|46.2|true|第一次通关哭了，那个酗酒狙击手最后一关替我挡了枪。这游戏的角色不是数据，是人。
review_2=速通菜鸡|1.4|false|开局给的弹药根本打不过第二节车厢，难度曲线有问题。
review_3=战术宅|120.8|true|每条线路都能玩出新流派，最近在挑战零招募纯六人通关，已经死了 17 次了，爽。
review_4=路过的|3.7|true|画面糙了点，但音乐绝了，列车启动那段配乐听一次起一次鸡皮疙瘩。
review_5=键盘侠007|0.6|false|看不懂剧情，也看不懂界面，退款。
[/SBEAM_GAME]

[SBEAM_GAME]
game_id=example_sbeam_b
title=隔壁太吵
genre=派对模拟
publisher=三个室友
pitch=一栋楼，八个邻居，一台音响。轮流当楼长，用投诉、敲墙、送水果三种手段让深夜恢复安静——前提是别把自己也举报了。
hook_moment=“我们做这个游戏，是因为真的被楼上养鼓的邻居折磨了一整年。” —— 主创 @阿橘
reaction_bias=laugh
price=18
release_date=2024-08-30
recent_reviews_summary=好评如潮 (96%)
all_reviews_summary=特别好评 (91%)
review_summary=和朋友联机笑到失声，单人模式一般。
review_1=合租之王|7.1|true|跟室友打了一晚上，他装的瑜伽老师邻居被我精准投诉三次，他气到掀桌子，值。
review_2=独狼玩家|2.0|false|没朋友就别买，AI 邻居死板得很。
review_3=楼下大爷|11.5|true|这个游戏让我理解了我楼上为什么半夜跳绳。然后我去敲门了。
review_4=键盘侠007|0.4|false|没有简体中文配音，差评。
review_5=周末派对|5.8|true|四人本地同屏，我们玩到凌晨三点，结果真被邻居敲墙了。游戏的影响力。
[/SBEAM_GAME]

本次请求：
- 数量：{{count}}
- 游戏概念参考：{{seed:game_concept,5}}
- 情绪参考：{{seed:mood,3}}
