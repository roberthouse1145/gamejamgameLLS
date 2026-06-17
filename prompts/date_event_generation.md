你正在为澜京大学城生成地图约会事件。

玩家和林夏会在地图上看到这些事件，然后决定要不要出发。事件必须像“今天可以去做的一件事”，不是小说章节标题、事故预告、新闻播报或任务公告。

关键原则：公开字段（title / subtitle / description / activity_hint）只写出发前两个人就能知道的“想去做的一件普通事”，相当于 NPC 邀请玩家时会说出口的话。进入现场后才会发生的变化、误会、巧合、尴尬、惊喜、机器故障、店员失误、突发事件、反转结局，**只能且必须**写进 detail_prompt，不许出现在公开字段里。

判定方法：把公开字段当作 NPC 发出的邀请。如果 NPC 这样邀请玩家会奇怪、剧透、像预知未来，就是错的。
- 反例：title=“ATM 取钱遇阻” → NPC 不可能邀请玩家“一起去 ATM 遇阻”。✗
- 正例：title=“校门口取个钱” / description=“顺路去校门口 ATM 取点现金，回头一起吃饭。” detail_prompt 里再写机器吐出缺角钞票的反转。✓
- 反例：title=“甜品店店员认错人” → 玩家出发前不会知道这件事。✗
- 正例：title=“甜品店新品试吃” detail_prompt 里再写店员把订单认错的小插曲。✓

公开字段必须写成“一件平平无奇、值得一起去做的小事”，detail_prompt 才是这件小事现场会冒出来的小变数。

地点：
- park：中央公园，树木、长椅、慢跑小道、小卖部
- commercial：商业区，餐厅、甜品店、书店、影院、商场
- school：蓝鲸大学，校园、操场、图书馆、食堂、教学楼
- harbor：旧港区，海边步道、码头、夜宵摊、灯塔
- gate：校门口、公交站、临街小店、共享单车点

时段：
- MORNING：早餐、菜市场、校园散步、晨跑、早八前后的校园琐事
- AFTERNOON：逛街、图书馆、公园、校内活动、买东西、临时绕路
- NIGHT：夜市、海边散步、夜宵、商场晚场、天台和宿舍楼下
每个时段生成 1 到 2 个事件。每个事件必须写 valid_phases，可用 | 分隔。不要把夜市放早上，也不要把晨间活动放深夜。

公开字段写法：
- title 像地图上的活动名，是“出发的理由”，例如“商场晚间折扣”“图书馆找个角落坐会儿”“校门口取个钱顺便吃饭”“便利店补点零食”。不写结果，不写转折，不写情绪冲击。
- subtitle 是一句短提示，像玩家扫地图时看到的小字，写氛围或顺带要做的事，不写现场会发生的具体剧情。
- description 是 2 到 3 句话，写地点、当前活动、排队/天气/店铺消息等出发前就能预期的信息，以及“为什么现在想去”。不要交代任何到了之后才会知道的事。
- activity_hint 写两个人大致打算怎么过这段时间（吃什么、逛什么、聊什么方向），不写现场会冒出来的具体意外，也不写结局。
- 严禁在 title/subtitle/description/activity_hint 里出现：“突然”“故障”“吐出”“缺角”“被困”“吵架”“事故”“报警”“受伤”“认错”“神秘人”“遇阻”“出错”“坏了”“没带钱”“被赶”“走丢”等现场结果或反转词。
- 语气像大学生日常，不要诗化，不要统一温柔治愈。

隐藏字段写法：
- detail_prompt 给 AVG 场景生成器使用，写到了现场之后真正发生的具体推进。
- 这里才允许出现轻微意外、反差、误会、临时变数，比如排队太长、点错东西、绕路、店员误会、活动临时改规则、机器出小毛病等。
- detail_prompt 中的反转**不许**回灌到 title/description；公开字段读起来必须仍然是“一件平常的小事”。

多样性：
- 事件之间地点、氛围、互动方式必须明显不同。
- 可以有日常、无聊、热闹、尴尬、搞笑、轻微变数，不要每条都安静温暖。
- 禁止“阳光透过树叶”“在宁静中感受彼此”这类空泛文艺句。
- 不要编造游戏中不存在的重要 NPC。
- 避免和近期约会历史重复。

输出：只输出多个 [DATE_EVENT] ... [/DATE_EVENT] 块，不要 JSON，不要 markdown，不要解释。

[DATE_EVENT]
event_id=dayN_short_id
title=事件标题
location_title=地点名称
location_id=park
subtitle=一句话氛围描述
description=2到3句话的事件描述
detail_prompt=给 AVG 生成用的详细场景设定
activity_hint=约会活动方向
valid_phases=AFTERNOON|NIGHT
map_position=0.2|0.3
accent_color=#72C28C
reward_stress=-18
reward_passion=1
reward_money=-20
[/DATE_EVENT]

reward_* 是开放前缀，可选 reward_stress / reward_passion / reward_money。不要输出 reward_affection。每个事件通常选 2 到 3 个维度；购物、吃饭、交通、电影、甜品、买东西时记得 reward_money 为负。
数值范围：
- reward_stress 通常为 -14 到 -20，港口/远地点/特别放松可到 -22。
- reward_passion 通常为 0 到 3，只有明显带来创作启发的活动才到 4 或 5。
- reward_money 允许 0 或负数；至少保留一些低成本/免费事件，不要所有约会都花钱。

参考值：
- map_position: park=0.2|0.3, commercial=0.55|0.35, school=0.4|0.55, harbor=0.8|0.7, gate=0.3|0.6
- accent_color: park=#72C28C, commercial=#F2A65A, school=#7D8FE8, harbor=#5B9BD5, gate=#9DC183

完整示例（仅作风格参考，**不要照抄题材**）：

[DATE_EVENT]
event_id=example_gate_atm
title=校门口取个钱
location_title=校门口
location_id=gate
subtitle=顺路去 ATM 拿点现金再吃饭
description=校门口那台 ATM 就在便利店旁边，去拿点现金回来一起吃晚饭。顺便看看新到的关东煮。
detail_prompt=两人到 ATM 前，机器吐出一张缺角的十块。林夏先笑出声说‘这能花吗’，旁边来取钱的大爷主动说他收这张，掏出完整的十块换给两人。换完之后大爷顺口念叨‘年轻人别耗时间，快去吃饭’。两人拿着完好的十块去便利店买关东煮。
activity_hint=一起在 ATM 前研究纸币、和大爷小聊几句、去便利店选关东煮
valid_phases=AFTERNOON|NIGHT
map_position=0.3|0.6
accent_color=#9DC183
reward_money=-10
reward_stress=-18
reward_passion=1
[/DATE_EVENT]

[DATE_EVENT]
event_id=example_park_jog
title=公园慢跑半小时
location_title=中央公园
location_id=park
subtitle=吃饭前去抖一抖
description=最近坐得久，下午去公园小跑一圈再回来。慢跑道短，走累了就坐长椅看人遛狗。
detail_prompt=两人换上轻便鞋出发，跑到第二个弯道时遇到一只追着泡泡狂奔的金毛，差点撞上林夏。狗主人慌忙道歉并送了瓶水当赔礼。两人坐到长椅上喝水，林夏小声吐槽‘还以为它要扑过来求婚’。
activity_hint=并肩慢跑、被狗插队、坐长椅一起缓气聊天
valid_phases=MORNING|AFTERNOON
map_position=0.2|0.3
accent_color=#72C28C
reward_stress=-18
reward_passion=1
[/DATE_EVENT]

注意上面两个示例：title / description / activity_hint 完全没有"缺角""撞狗"这些剧透，detail_prompt 才写真正发生的小插曲。生成时必须保持这种公开/隐藏字段分层。

本次请求：
- 比赛第 {{next_day}} 天
- 当前状态：{{game_state}}
- 近期约会历史：{{recent_history}}
- 场景参考：{{seed:date_scene,5}}
- 情绪参考：{{seed:mood,4}}
