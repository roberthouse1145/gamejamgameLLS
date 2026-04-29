你正在为恋爱共创 SLG 里的虚构电商 App 生成每日商品。

玩家和林夏会像刷普通网购平台一样看到这些商品。商品要像真实电商条目：有卖点、有店铺口吻、有用户评论，普通生活里能买到，但可以带一点大学生会吐槽的怪味。

商品方向：
- gift：小礼物、玩偶、饰品、纪念品、手作材料
- life：生活用品、收纳、零食、桌面小物、宿舍装备
- creative：GameJam、画画、写作、音频、开发相关的小工具或材料
- weird：真实可买但有点奇怪的东西，不要超现实

写作规则：
- title 像商品标题，短，能被玩家一眼看懂。
- subtitle 是商品卡片副标题，像平台卖点，不要文艺。
- short_desc 是一句快速介绍。
- detail_desc 像商品详情页文案，具体一点，能让林夏有话可吐槽。
- seller_style 写店铺风格，比如“大学城小店”“过度热情的手作店”“像客服但很会整活”。
- user_comments 像真实买家评论，短、有个人口吻，不要全是好评模板。
- 商品要真实可信，禁止真实品牌、真实平台名、知名 IP、政治、血腥、违法、露骨内容。

输出：只输出 [ITEM] ... [/ITEM] 块，不要 JSON，不要 markdown，不要块外解释。
每个商品字段必须完整，字段名精确一致。tags 和 user_comments 用 | 分隔。

固定约束：
- 类别只能是 gift, life, creative, weird。
- price_band 只能是 low / mid / high。
- effect_archetype 必须从白名单选择。
- 商品之间要有明显差异，不要全是礼物或全是开发工具。

本次请求：
- 数量：{{shop_target_count}}
- 时间：Day {{shop_day}} 的 GameJam 期间
- effect_archetype 白名单：{{shop_effect_whitelist}}
{{shop_state_block}}
- 商品参考：{{seed:shop_idea,5}}
- 情绪参考：{{seed:mood,3}}
