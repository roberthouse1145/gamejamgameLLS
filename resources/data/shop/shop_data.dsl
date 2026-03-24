# ═══════════════════════════════════════════════════
#  商店初始数据（全部）
#  所有商店相关的静态数据集中在此文件
# ═══════════════════════════════════════════════════


# ── 分类白名单 ────────────────────────────────────
# items 格式: id|显示名||id|显示名||...

[CATEGORIES]
items=gift|礼物||life|生活||creative|创作||weird|奇趣
[/CATEGORIES]


# ── 价格档位 ──────────────────────────────────────

[PRICE_BANDS]
items=low|mid|high
[/PRICE_BANDS]


# ── 价格区间 ──────────────────────────────────────

[PRICE_RANGES]
low=15|59
mid=45|129
high=120|268
[/PRICE_RANGES]


# ── 分类荒诞度 ────────────────────────────────────

[ABSURDITY]
gift=0.18
life=0.12
creative=0.21
weird=0.36
default=0.2
[/ABSURDITY]


# ── 禁词 ──────────────────────────────────────────

[BANNED_TERMS]
items=淘宝|天猫|京东|apple|任天堂|自杀|枪|炸弹|血腥
[/BANNED_TERMS]


# ── 店铺名池 ──────────────────────────────────────

[SELLER_NAMES]
items=日用好物精选|深夜补给站|桌面生活馆|创意杂货铺|小确幸商店|宿舍生存指南|文具控联盟|零食研究所
[/SELLER_NAMES]


# ── 属性显示名 ────────────────────────────────────

[STAT_LABELS]
stress=压力
passion=激情
affection=好感
completion=完成度
quality=质量
money=金钱
[/STAT_LABELS]


# ── 状态显示名 ────────────────────────────────────

[STATE_LABELS]
ready=可使用
equipped=生效中
consumed=已消耗
gifted=已赠送
[/STATE_LABELS]


# ── 权重调整规则 ──────────────────────────────────
# 格式: 条件字段|阈值运算符|阈值|匹配字段|匹配类型|匹配值|加权

[WEIGHT_RULES]
rule_1=stress|gte|60|category|eq|life|3
rule_2=stress|gte|60|effect_archetype|eq|mood_up_small|3
rule_3=passion|lte|45|effect_archetype|eq|creative_focus_small|2
rule_4=passion|lte|45|effect_archetype|eq|room_ambience_small|2
rule_5=money|lte|180|price_band|eq|low|2
rule_6=*|*|*|category|eq|gift|1
[/WEIGHT_RULES]


# ═══════════════════════════════════════════════════
#  效果原型
# ═══════════════════════════════════════════════════

[EFFECT]
id=sleep_recovery_small
display_name=改善睡眠
use_mode=equip
modifier_slot=sleep
instant_stats=stress:-2
modifiers=sleep_stress_recovery_mult|睡眠时压力恢复 +12%|multiplier|0.12
summary=睡眠恢复会更好一点。
[/EFFECT]

[EFFECT]
id=sleep_recovery_medium
display_name=大幅改善睡眠
use_mode=equip
modifier_slot=sleep
instant_stats=stress:-3
modifiers=sleep_stress_recovery_mult|睡眠时压力恢复 +20%|multiplier|0.20
summary=明显改善睡眠恢复效果。
[/EFFECT]

[EFFECT]
id=creative_focus_small
display_name=提升专注
use_mode=equip
modifier_slot=desk
instant_stats=passion:2
modifiers=creative_focus_mult|创作专注效率 +12%|multiplier|0.12
summary=更容易进入创作状态。
[/EFFECT]

[EFFECT]
id=creative_focus_with_stress
display_name=专注↑ 压力↑
use_mode=equip
modifier_slot=desk
instant_stats=stress:2
modifiers=creative_focus_mult|夜间创作效率 +15%|multiplier|0.15||chat_interrupt_mult|闲聊打断触发率 -15%|multiplier|-0.15
summary=会更专注，但也更像把自己锁进桌面里。
[/EFFECT]

[EFFECT]
id=mood_up_small
display_name=改善心情
use_mode=consume
instant_stats=stress:-5|passion:2
summary=立刻让心情好一点。
[/EFFECT]

[EFFECT]
id=gift_affection_small
display_name=好感↑
use_mode=gift
instant_stats=affection:6
summary=适合送给她，主要提升好感。
[/EFFECT]

[EFFECT]
id=gift_trust_small
display_name=信任↑
use_mode=gift
instant_stats=affection:4|passion:2
summary=更像是"你有在认真记得她"的那种礼物。
[/EFFECT]

[EFFECT]
id=late_night_efficiency_small
display_name=短期效率↑
use_mode=consume
instant_stats=completion:2|stress:3
summary=短期推进效率更高，但也更伤神。
[/EFFECT]

[EFFECT]
id=room_ambience_small
display_name=氛围加成
use_mode=equip
modifier_slot=ambience
instant_stats=stress:-1
modifiers=ambient_stress_recovery_bonus|日常减压恢复 +1|flat|1
summary=房间会更有"待在这里也行"的感觉。
[/EFFECT]

[EFFECT]
id=flavor_no_effect
display_name=纯风味
use_mode=flavor
summary=主要提供生活气息，没有直接数值收益。
[/EFFECT]


# ═══════════════════════════════════════════════════
#  本地蓝图
# ═══════════════════════════════════════════════════

[BLUEPRINT]
blueprint_id=sleep_aid
category=life
sub_category=sleep_aid
effect_archetype=sleep_recovery_small
giftable=true
price_band=mid
price_range=58|118
shipping_range=1|2
title_prefix=回弹|云朵|午睡|安静
title_suffix=记忆枕|靠垫|抱枕|助眠枕
subtitles=熬夜人自救计划|把脖子先哄好|今晚先别那么硬扛
short_descs=看起来没什么黑科技，但摸上去就让人想早点关灯。|适合在赶工之后把脑子先放一边。
detail_descs=普通材质加一点过分温柔的触感，卖点不是性能，而是终于像认真照顾自己了一回。|没有奇迹，只是会让你在床上多赖五分钟，顺便少一点起床前的敌意。
tags=助眠|柔软|居家
seller_styles=认真过头型文案|治愈系主图
user_comments=睡前一抱，突然觉得明天也不是不能活。|不是药，但比嘴硬有用。
reaction_hints=她会说你最近终于开始把自己当人照顾了。|她大概会先拿它拍你一下，再认真摸摸看。
[/BLUEPRINT]

[BLUEPRINT]
blueprint_id=desk_focus
category=creative
sub_category=desk_focus
effect_archetype=creative_focus_small
giftable=true
price_band=mid
price_range=42|138
shipping_range=1|3
title_prefix=分镜|专注|深夜|截稿
title_suffix=便签纸|桌面灯|理线器|任务板
subtitles=桌面乱的时候脑子也会乱|把零碎想法先留下|适合赶工桌的一点秩序
short_descs=不会直接帮你写完剧本，但至少能让灵感别继续散落在桌面边缘。|是那种看起来没什么，却常常能救回半小时创作杂物。
detail_descs=小物件、轻工具，不夸张，但足够让桌面看起来像真的在认真推进项目。|会让"我之后整理"这件事稍微变得更像现在就能开始。
tags=创作|桌面|效率
seller_styles=文具控种草|桌搭效率风
user_comments=没买之前觉得可有可无，买了以后会开始嫌弃原来那团线。|不是灵感来源，但能让灵感别逃跑。
reaction_hints=她会觉得这东西很像你们项目当前需要的那一点秩序。|她可能会顺手拿去帮你整理桌面。
[/BLUEPRINT]

[BLUEPRINT]
blueprint_id=snack
category=life
sub_category=snack
effect_archetype=mood_up_small
giftable=true
price_band=low
price_range=16|48
shipping_range=1|2
title_prefix=临期|加班后|夜宵|草莓
title_suffix=夹心饼干|黄油曲奇|软糖|小零食箱
subtitles=饿的时候比计划更重要|有些糖分就是比道理快|写不动的时候先嚼点什么
short_descs=不一定健康，但很适合在情绪快要碎掉的时候先垫一口。|属于桌边常备，吃完才想起刚刚自己差点又跟世界翻脸。
detail_descs=味道也许普通，但在熬夜、赶工、情绪低的时候，普通反而比惊艳更可靠。|小包装好拿，深夜嘴馋、低气压、改稿卡住的时候都能提供一点短暂宽容。
tags=零食|减压|便宜
seller_styles=办公室囤货风|深夜补给站
user_comments=吃到一半的时候，确实会没那么想辞职了。|谈不上高级，但在该出现的时候很会出现。
reaction_hints=她会边吐槽边顺走一半。|她大概会说你在用碳水缓冲现实。
[/BLUEPRINT]

[BLUEPRINT]
blueprint_id=gift_cute
category=gift
sub_category=cute_gift
effect_archetype=gift_trust_small
giftable=true
price_band=mid
price_range=25|99
shipping_range=1|3
title_prefix=会发光的|小小的|桌边|睡前
title_suffix=毛绒挂件|手账贴纸|便签印章|迷你摆件
subtitles=不是必要，但会被记住|看起来像"我有在想到你"|小礼物最怕敷衍，也最容易真诚
short_descs=数值意义不大，但非常适合让某个人在看到的时候停一下。|不是贵重礼物，更像把一个微小的偏爱装进盒子里。
detail_descs=这类东西不会改变项目进度，却很可能改变今晚说话的语气。|送得好的时候很轻，留下来的感觉却会比价格久一点。
tags=礼物|可爱|随手买
seller_styles=送礼灵感页|收藏夹里反复出现的那种
user_comments=贵不贵不重要，重要的是对的人会记住。|这种小东西的杀伤力，通常只对特定的人生效。
reaction_hints=她会装作很平静，但之后大概会把它放到看得见的地方。|她可能会先问你怎么会想到买这个。
[/BLUEPRINT]

[BLUEPRINT]
blueprint_id=ambience
category=weird
sub_category=desk_decor
effect_archetype=room_ambience_small
giftable=true
price_band=mid
price_range=33|109
shipping_range=2|3
title_prefix=会呼吸的|据说转运的|发呆专用|桌面用的
title_suffix=小夜灯|仙人掌摆件|香薰石|风铃球
subtitles=看着就会慢一点|有点怪，但也确实有氛围|桌面不该只有文件和咖啡
short_descs=你很难解释它为什么有用，但没有它的时候桌面又确实少了点什么。|属于电商平台会认真推荐给你的那种小怪东西。
detail_descs=不负责解决问题，只负责让这个房间不那么像纯粹的赶工现场。|很适合放在电脑边，提醒自己你们不是生产线，也还是会过日子的人。
tags=氛围|摆件|怪东西
seller_styles=算法瞎推荐|桌搭疗愈风
user_comments=买之前觉得离谱，摆上以后又觉得它本来就该在这儿。|一看就不刚需，但每天都会多看它两眼。
reaction_hints=她会怀疑这是不是智商税，但最后可能比你先开始摸它。|她大概会先笑你乱买，然后把它摆到顺手的位置。
[/BLUEPRINT]

[BLUEPRINT]
blueprint_id=late_night_supply
category=creative
sub_category=late_night_supply
effect_archetype=late_night_efficiency_small
giftable=false
price_band=low
price_range=19|59
shipping_range=1|2
title_prefix=熬夜|通宵|赶稿|清醒
title_suffix=咖啡包|浓缩冲剂|功能饮料箱|薄荷糖罐
subtitles=短期强力，长期可疑|今天很有用，明天不好说|写完这一段再说睡觉
short_descs=这类东西最擅长的，是让你以为自己还能再多撑一会儿。|效率会上来，脾气和心率通常也会跟着上来。
detail_descs=适合最后冲刺前的物资补给，不适合把它当作长期生活方式。|它会让"今晚再收个尾"这句话显得更像真的，但后劲也通常写在第二天。
tags=熬夜|补给|效率
seller_styles=社畜求生|深夜冲刺区
user_comments=推进是真的推进了，代价也是真的代价。|喝下去那一刻很燃，凌晨四点就没那么浪漫了。
reaction_hints=她会觉得你又想和凌晨三点做朋友了。|她大概会提醒你别把身体也拿去赶工。
[/BLUEPRINT]


# ═══════════════════════════════════════════════════
#  固定核心商品（每日必出）
# ═══════════════════════════════════════════════════

[CORE_ITEM]
item_id=core_pillow
category=life
effect_archetype=sleep_recovery_medium
title=松软记忆枕
subtitle=把今天的疲惫先放下
desc=不是黑科技，只是终于肯让脖子休息一下。\n\n回弹慢，支撑感也刚好，属于一看就很适合在截稿周抱着躺平的那种日用品。
price=128
shipping_days=1
giftable=true
tags=助眠|居家|柔软
user_comments=买来第一晚没什么感觉，第三晚开始不想离开床。|谈不上改变人生，但至少先把肩颈哄好了。
[/CORE_ITEM]

[CORE_ITEM]
item_id=core_headphones
category=creative
effect_archetype=creative_focus_with_stress
title=夜色降噪耳机
subtitle=深夜赶稿专用
desc=把杂音隔开一点，也把自己和世界隔开一点。\n\n并不是录音棚级别的设备，但夜里写东西、改分镜、调情绪时会让桌面安静很多。
price=229
shipping_days=2
giftable=true
tags=创作|专注|夜间
user_comments=戴上以后世界总算愿意闭嘴一会儿。|专注是专注了，就是别人喊我吃饭经常听不见。
[/CORE_ITEM]

[CORE_ITEM]
item_id=core_cake
category=gift
effect_archetype=gift_affection_small
title=晚安小蛋糕
subtitle=情绪低的时候比道理更有用
desc=奶油不算惊艳，但它长得就像一句软一点的话。\n\n小小一盒，适合夜里顺手带回去。不是重大礼物，却很容易让某个时刻变得温柔一点。
price=36
shipping_days=1
giftable=true
tags=礼物|甜点|安慰
user_comments=工作做不完的时候，先把这口甜的吃掉也不错。|送人成功率比自己熬过去高。
[/CORE_ITEM]

[CORE_ITEM]
item_id=core_coffee_box
category=creative
effect_archetype=late_night_efficiency_small
title=截稿周咖啡箱
subtitle=看起来很专业，喝起来很拼命
desc=适合写下'今天一定收尾'，也适合明天继续熬。\n\n一整箱速溶咖啡，摆在桌上就很像进入了真正的赶工状态，但代价通常也写在第二天的脸上。
price=49
shipping_days=1
giftable=false
tags=熬夜|效率|咖啡
user_comments=推进是真的推进了，代价也是真的代价。|不是好喝，是有用。
[/CORE_ITEM]
