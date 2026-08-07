class_name DanmakuPool extends RefCounted
## 直播弹幕本地模板池：弹幕主体来源，LLM 只做点缀。
## 句式按本场四轴倾向选择；所有随机取自调用方传入的 rng，保证可复现。

const HINT_HOOK: String = "hook"
const HINT_QUALITY: String = "quality"
const HINT_IMPACT: String = "impact"
const HINT_RISK: String = "risk"
const HINT_NEUTRAL: String = "neutral"

const NICKNAMES: Array[String] = [
	"路过的新观众", "今天也在摸鱼", "柚子的茶", "弹幕守卫", "深夜不下线",
	"薯片半价", "看客甲", "追番老宅", "柠檬气泡水", "信号满格",
	"前排钉子户", "云观众代表", "不发言只看", "电波同调中", "熬夜冠军",
	"路过打call", "一级潜水员", "瓜田常客", "键盘鉴赏家", "静音观看中",
	"二刷选手", "待业评论员", "自动点赞机", "住在直播间",
]

const TEMPLATES: Dictionary = {
	HINT_HOOK: [
		"来了来了", "首页刷到的，进来看看", "这标题我必须点进来", "什么动静",
		"围观", "开播了开播了", "点进来就出不去了", "这么多人？",
	],
	HINT_QUALITY: [
		"这段讲得真细", "记笔记了", "学到了学到了", "主播是懂的",
		"干货密度有点高", "这部分回放预定", "专业", "细，太细了",
	],
	HINT_IMPACT: [
		"草", "哈哈哈哈哈哈", "主播太会了", "笑死", "节目效果拉满",
		"这也可以？", "绷不住了", "SC 走起", "值了值了", "名场面预定",
	],
	HINT_RISK: [
		"???", "啊这", "要翻车了吗", "等等，不对劲", "主播冷静",
		"这下刺激了", "弹幕护体", "我有点紧张",
	],
	HINT_NEUTRAL: [
		"前排", "打卡", "666", "来了", "今天状态不错",
		"bgm 好评", "音量刚好", "搬好小板凳",
	],
}


## 按轴倾向抽取 count 条弹幕，返回 [{"nickname":, "text":}]。
static func roll(rng: RandomNumberGenerator, axis_hint: String, count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if rng == null or count <= 0:
		return result
	var pool: Array = TEMPLATES.get(axis_hint, TEMPLATES[HINT_NEUTRAL])
	var neutral: Array = TEMPLATES[HINT_NEUTRAL]
	for index: int in range(count):
		# 七成按倾向，三成掺通用句，避免弹幕口径过于一致
		var source: Array = neutral if rng.randf() < 0.3 else pool
		result.append({
			"nickname": roll_nickname(rng),
			"text": String(source[rng.randi_range(0, source.size() - 1)]),
		})
	return result


static func roll_nickname(rng: RandomNumberGenerator) -> String:
	if rng == null:
		return NICKNAMES[0]
	return NICKNAMES[rng.randi_range(0, NICKNAMES.size() - 1)]
