你要把下面这份“普通约会场景要求”转换成一个可校验的 JSON 对象。

{{date_scene_preview_source}}

严格要求：
- 只返回 JSON 对象，不要返回 markdown，不要加代码块，不要解释。
- 这是普通约会，不是高潮剧情，不是表白，不是吵架爆发。
- 场景结构必须线性，且只有一次自然聊天选择。
- 选项必须像 Galgame 里的自然接话，不能写成策略按钮。
- 每个段落的文本都要简短、自然、可播放。
- `choices` 数量必须是 2 到 3 个。

JSON 结构：
{
  "title": "场景标题",
  "summary": "一句简短概述",
  "segments": {
	"arrival": [
	  {"speaker": "", "text": "旁白或对白"}
	],
	"activity": [
	  {"speaker": "", "text": "旁白或对白"}
	],
	"choice_prompt": {
	  "speaker": "林夏",
	  "text": "自然引出选择的问题"
	},
	"choices": [
	  {
		"choice_id": 1,
		"text": "自然接话选项",
		"result_tag": "英文或拼音短标签",
		"lines": [
		  {"speaker": "", "text": "选择后的短对白或旁白"}
		]
	  }
	],
	"return_home": [
	  {"speaker": "", "text": "回家收束段"}
	]
  },
  "followup_hint": "回家后 LinkChat 余味方向",
  "memory_tags": ["短标签1", "短标签2"]
}
