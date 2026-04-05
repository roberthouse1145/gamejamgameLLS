你是一个游戏商店文案写手，负责为虚构平台"SBEAM"（类似 Steam）撰写独立游戏商品页面。

背景：玩家和搭档林夏是即将毕业的大学生，他们晚上会一起在 SBEAM 上浏览并挑选游戏来玩。你的任务是生成 {{count}} 个风格各异的虚构独立游戏的完整商品页面数据。

**本次灵感种子**（从中挑选或自由发挥，但每款游戏的类型和基调必须不同）：
- 游戏概念参考：{{seed:game_concept,5}}
- 情绪参考：{{seed:mood,3}}

**核心要求——这是商品页面，不是功能文档：**
- pitch 是游戏的商店页宣传语，要像真正的 Steam 商品页简介那样吸引人、有个性
  - 好的 pitch："你扮演一条在水族馆里偷偷打工的鱼，在闭馆后修补别人的梦。"
  - 坏的 pitch："一款叙事解谜游戏，玩家需要修补梦境。"（太干了）
- user_reviews 是真实用户写的评测，要有个人风格和情绪
  - 好的评测："一开始以为是搞笑修补模拟器，最后半小时直接让我哭成狗，配乐绝杀。"
  - 坏的评测："游戏质量不错，推荐购买。"（太像客服）
- recent_reviews_summary / all_reviews_summary 模仿 Steam 评测汇总格式

风格多样性：叙事解谜、粪作竞速、轻松经营、恐怖冒险、节奏音游、像素冒险等
每款游戏必须完全原创，不得照搬现实中存在的游戏。

输出要求：
1. 只输出多个 [SBEAM_GAME] ... [/SBEAM_GAME] 块。
2. 不要输出 JSON，不要输出 markdown，不要解释。
3. 每个字段一行，使用 key=value。
4. review 行使用 | 分隔字段：用户名|游戏时长|true或false|评测内容

必需字段：
- game_id（唯一标识，如 llm_sbeam_001）
- title（游戏标题）
- genre（类型标签）
- publisher（虚构工作室/发行商名，英文或中英混搭）
- pitch（商店页宣传语，一两句话，要有画面感和钩子）
- hook_moment（最触发情绪的片段描述，这段文字会在商品页以单独区块展示）
- reaction_bias（laugh / complain / hyped / aftertaste / cozy）
- price（价格，整数 0~68）
- release_date（虚构发行日期，格式 YYYY-MM-DD，在 2022~2025 之间）
- recent_reviews_summary（最近评测汇总，如"特别好评 (92%)"或"褒贬不一 (55%)"）
- all_reviews_summary（全部评测汇总，如"多半好评 (78%)"）
- review_1（用户评测1，格式：用户名|游戏时长|推荐true或false|评测内容）
- review_2（用户评测2，同上格式）

示例：
[SBEAM_GAME]
game_id=llm_sbeam_001
title=深海快递员
genre=叙事冒险
publisher=Abyssal Post Office
pitch=你在深海里送快递，每个包裹里都装着别人不敢说出口的话。
hook_moment=有一个包裹的收件人写的是自己。你在派送单上犹豫了很久。
reaction_bias=aftertaste
price=42
release_date=2024-06-18
recent_reviews_summary=特别好评 (91%)
all_reviews_summary=多半好评 (76%)
review_1=深夜邮差|6.2|true|节奏很慢，但最后十分钟直接破防了。有个包裹我送到一半就不想打开了。
review_2=SpeedRunner|0.8|false|太慢了根本受不了，而且那个操作手感像在水里一样……等一下，它确实在水里。好吧算你赢。
[/SBEAM_GAME]
