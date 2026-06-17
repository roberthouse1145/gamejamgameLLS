extends Control
## 可视化测试场景：左侧选择样例，右侧实时渲染 PageMark 页面。
## 给人类肉眼判断渲染质量与版面美观度。

const PageMarkParserClass = preload("res://scripts/apps/browser/page_mark_parser.gd")

const PREMADE_PAGES: Array = [
	"res://resources/data/browser_pages/homepage.tres",
	"res://resources/data/browser_pages/theme_forum.tres",
	"res://resources/data/browser_pages/gamejam_schedule.tres",
	"res://resources/data/browser_pages/gamejam_news.tres",
	"res://resources/data/browser_pages/gamejam_faq.tres",
	"res://resources/data/browser_pages/love.tres",
]

const SYNTHETIC_BBC := """::: card bg=#BB1919 pad=14
::: row sep=24
[color=#ffffff][b]BBC[/b][/color]
::: col fill
:::
[News](action:open url=/news)
[Sport](action:open url=/sport)
[Weather](action:open url=/weather)
[Sounds](action:open url=/sounds)
[Sign in](action:open url=/signin)
:::
:::

::: col pad=20

# 头条新闻：本届 GameJam 新规则正式公布

2026-05-01 · 体育与文化版

> 本届赛事采用统一引擎与统一素材包，回归创意与叙事本身。

正文段落一，写一些**强调内容**和[内部链接](url:/related/12)。

正文段落二，继续阐述。

::: row sep=8
[color=#666666]**标签**：[/color][科技](url:/tag/tech) [创业](url:/tag/startup) [GameJam](url:/tag/gj)
:::
:::"""

const SYNTHETIC_BILIBILI := """::: card bg=#FB7299 pad=12
::: row sep=24
[color=#ffffff][b]bilibili[/b][/color]
::: col fill
:::
[首页](url:/) [动画](url:/anime) [游戏](url:/game) [我的](url:/me)
:::
:::

::: col pad=20

# 推荐视频

::: grid cols=4 sep=14
::: col
::: card bg=#3FB4D9 height=140 pad=12 align=bottom
[color=#ffffff][b]Godot 踩坑[/b][/color]
:::
::: col pad=10 sep=4
**【游戏实况】Godot 大型项目踩坑实录**
UP主-A · 12.3万播放 · 2小时前
:::
:::

::: col
::: card bg=#FF6699 height=140 pad=12 align=bottom
[color=#ffffff][b]EP.05 学编程[/b][/color]
:::
::: col pad=10 sep=4
**学习编程的100种方法 EP.05**
UP主-B · 5.6万播放 · 5小时前
:::
:::

::: col
::: card bg=#9966CC height=140 pad=12 align=bottom
[color=#ffffff][b]性能优化[/b][/color]
:::
::: col pad=10 sep=4
**高能向 Godot 4 性能优化**
UP主-C · 8.1万播放 · 1天前
:::
:::

::: col
::: card bg=#33AA88 height=140 pad=12 align=bottom
[color=#ffffff][b]新作首发[/b][/color]
:::
::: col pad=10 sep=4
**独立游戏开发日志 #88**
UP主-D · 3.4万播放 · 1天前
:::
:::
:::
:::"""

const SYNTHETIC_TIEBA := """::: card bg=#5B86E5 pad=10
::: row sep=12
[color=#ffffff]首页 › 游戏开发吧 › 帖子[/color]
::: col fill
:::
[关注](action:follow)
[发帖](action:post)
:::
:::

::: col pad=20 sep=12

# 求救！这个 bug 我修不了

[color=#888888]楼主 · 2026-05-01 14:30 · 阅读 1234 · 回复 23[/color]

::: card bg=#ffffff
::: row sep=12
::: col width=80
**用户A**
[color=#888888][Lv.5] 老司机[/color]
:::
::: col fill
::: row
::: col fill
:::
[color=#aaaaaa]1L · 14:30[/color]
:::

正文段落一。我在 Godot 项目里遇到这个 bug，不知道怎么修。

::: row sep=8
::: col fill
:::
[回复](action:reply post_id=1)
[举报](action:report post_id=1)
:::
:::
:::
:::

::: card bg=#ffffff
::: row sep=12
::: col width=80
**用户B**
[color=#888888][Lv.3][/color]
:::
::: col fill
::: row
::: col fill
:::
[color=#aaaaaa]2L · 14:45[/color]
:::

::: card bg=#f5f5f5 pad=8
> 引用 1L：我在 Godot 项目里遇到这个 bug
:::

楼主你试试 print(get_stack())。

::: row sep=8
::: col fill
:::
[回复](action:reply post_id=2)
:::
:::
:::
:::

::: row sep=8 align=center
[‹ 上一页](action:page p=1)
[1](url:/page/1) [2](url:/page/2) **3** [4](url:/page/4)
[下一页 ›](action:page p=4)
:::
:::"""

const SYNTHETIC_WIKI := """::: row fill
::: col width=200 bg=#f5f5f5 pad=14
**目录**

---

[简介](url:#intro)
[历史](url:#history)
[相关研究](url:#research)
[参见](url:#see)
:::

::: col fill pad=24

# 示例百科条目

> 本词条由 PageMark 渲染，用于演示混合排版能力。

## 简介

正文段落，包含**粗体**、*斜体*、~~删除~~、[彩色文字](color:#0066CC)与[内联链接](url:/link)。

普通段落分隔，直接换行即可分段。

## 历史沿革

- 列表项一
- 列表项二
- 列表项三

1. 有序项 A
2. 有序项 B

## 引用与图片

> 这是一个引用块，用于摘录他处文字。

![占位图](image:src=res://placeholder.png width=300 height=120)

---

::: card bg=#fafafa
**信息卡片**

属性一：值

属性二：值

属性三：值
:::
:::
:::"""


@onready var _list: ItemList = %SamplesList
@onready var _scroll: ScrollContainer = %PageScroll
@onready var _page_host: PanelContainer = %PageHost
@onready var _info_label: Label = %InfoLabel

var _samples: Array = []  # [{name, content, source}]
var _current_root: Control = null


func _ready() -> void:
	_load_samples()
	for sample in _samples:
		_list.add_item(str(sample.get("name", "?")))
	_list.item_selected.connect(_on_sample_selected)
	if _samples.size() > 0:
		_list.select(0)
		_show_sample(0)


func _load_samples() -> void:
	for path in PREMADE_PAGES:
		var res: WebPageResource = ResourceLoader.load(path) as WebPageResource
		if res == null:
			push_warning("无法加载: %s" % path)
			continue
		var content: String = str(res.content).strip_edges()
		if content.is_empty():
			continue
		_samples.append({
			"name": "[预制] " + str(res.title),
			"content": content,
			"source": path,
		})

	_samples.append({"name": "[合成] BBC 头部 + 文章", "content": SYNTHETIC_BBC, "source": "synthetic"})
	_samples.append({"name": "[合成] Bilibili 视频网格", "content": SYNTHETIC_BILIBILI, "source": "synthetic"})
	_samples.append({"name": "[合成] 贴吧帖子页", "content": SYNTHETIC_TIEBA, "source": "synthetic"})
	_samples.append({"name": "[合成] 百科 + 侧栏目录", "content": SYNTHETIC_WIKI, "source": "synthetic"})


func _on_sample_selected(index: int) -> void:
	_show_sample(index)


func _show_sample(index: int) -> void:
	if index < 0 or index >= _samples.size():
		return
	var sample: Dictionary = _samples[index]
	var content: String = str(sample.get("content", ""))
	var source: String = str(sample.get("source", ""))

	# 走 BrowserManager 同款分流，与生产路径一致
	var tree: Dictionary = BrowserManager._parse_page_content(content)

	# 清掉上一次渲染
	if _current_root != null and is_instance_valid(_current_root):
		_current_root.queue_free()
	_current_root = WebPageRenderer.render(tree, _on_page_action)
	_current_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_current_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.add_child(_current_root)
	_scroll.scroll_vertical = 0

	# 顶部信息条
	var detected: String = _detect_format(content)
	_info_label.text = "[%s]  来源: %s" % [detected, source]


func _detect_format(text: String) -> String:
	var lower: String = text.to_lower()
	for tag in ["<vbox", "<hbox", "<panel", "<rich", "<label"]:
		if lower.find(tag) >= 0:
			return "旧 DSL"
	return "PageMark"


func _on_page_action(action_data: Dictionary) -> void:
	# 测试场景里 link/button 不真实跳转，只打印
	print("[VisualTest] action triggered: %s" % str(action_data))
