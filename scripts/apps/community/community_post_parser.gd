class_name CommunityPostParser
extends RefCounted
## 解析 Community Feed DSL 文本为帖子数据数组。
##
## 语法：
##   ===post===       开始帖子
##   ---reply---      主帖下的一层楼
##   ---subreply---   楼中楼回复
##   ===end===        结束帖子
##
## 返回 Array[Dictionary]，每个 Dictionary 结构：
##   {
##     "author": String,
##     "time": String,
##     "likes": int,
##     "replies": int,
##     "title": String,        # 可选
##     "content": String,
##     "reply_list": [
##       {
##         "author": String,
##         "time": String,
##         "likes": int,
##         "content": String,
##         "sub_reply_list": [
##           { "author": String, "time": String, "likes": int, "content": String }
##         ]
##       }
##     ]
##   }

const POST_START := "===post==="
const POST_END := "===end==="
const REPLY_SEP := "---reply---"
const SUB_REPLY_SEP := "---subreply---"


static func parse(source: String) -> Array:
	var text := _strip_fences(source.strip_edges())
	if text.is_empty():
		return []
	var posts: Array = []
	var blocks := _split_post_blocks(text)
	for block in blocks:
		var post := _parse_post_block(block)
		if not post.is_empty():
			posts.append(post)
	return posts


## 去除可能的 markdown 围栏（```...```）
static func _strip_fences(text: String) -> String:
	var t := text
	# 去除开头 ```xxx
	var re_start := RegEx.new()
	re_start.compile("^```[a-zA-Z]*\\s*\\n")
	var m := re_start.search(t)
	if m:
		t = t.substr(m.get_end())
	# 去除结尾 ```
	var re_end := RegEx.new()
	re_end.compile("\\n```\\s*$")
	m = re_end.search(t)
	if m:
		t = t.substr(0, m.get_start())
	return t


## 按 ===post=== ... ===end=== 拆分为帖子块
static func _split_post_blocks(text: String) -> Array:
	var blocks: Array = []
	var pos := 0
	while true:
		var start := text.find(POST_START, pos)
		if start == -1:
			break
		var content_start := start + POST_START.length()
		var end := text.find(POST_END, content_start)
		if end == -1:
			# 没有匹配的 ===end===，取到末尾
			blocks.append(text.substr(content_start).strip_edges())
			break
		blocks.append(text.substr(content_start, end - content_start).strip_edges())
		pos = end + POST_END.length()
	return blocks


## 解析单个帖子块（含楼层与楼中楼）
static func _parse_post_block(block: String) -> Dictionary:
	# 按 ---reply--- 拆分：第一段是主帖，后续是楼层
	var parts := _split_by_separator(block, REPLY_SEP)
	if parts.is_empty():
		return {}

	var main_part: String = parts[0]
	var header_and_content := _split_header_content(main_part)
	var header: Dictionary = header_and_content[0]
	var content: String = header_and_content[1]

	if content.is_empty() and header.is_empty():
		return {}

	var post: Dictionary = {
		"author": header.get("author", "匿名用户"),
		"time": header.get("time", ""),
		"likes": _to_int(header.get("likes", "0")),
		"replies": _to_int(header.get("replies", "0")),
		"content": content,
		"reply_list": [],
	}
	if header.has("title"):
		post["title"] = header["title"]

	# 解析楼层
	for i in range(1, parts.size()):
		var reply := _parse_reply(parts[i])
		if not reply.is_empty():
			post["reply_list"].append(reply)

	return post


## 按分隔符拆分文本
static func _split_by_separator(text: String, separator: String) -> Array:
	var parts: Array = []
	var pos := 0
	while true:
		var sep := text.find(separator, pos)
		if sep == -1:
			parts.append(text.substr(pos).strip_edges())
			break
		parts.append(text.substr(pos, sep - pos).strip_edges())
		pos = sep + separator.length()
	return parts


## 解析楼层段落，兼容旧格式的单层回复
static func _parse_reply(text: String) -> Dictionary:
	var parts := _split_by_separator(text, SUB_REPLY_SEP)
	if parts.is_empty():
		return {}

	var header_and_content := _split_header_content(parts[0])
	var header: Dictionary = header_and_content[0]
	var content: String = header_and_content[1]
	if content.is_empty():
		return {}

	var reply := {
		"author": header.get("author", "匿名用户"),
		"time": header.get("time", ""),
		"likes": _to_int(header.get("likes", "0")),
		"content": content,
		"sub_reply_list": [],
	}

	for i in range(1, parts.size()):
		var sub_reply := _parse_sub_reply(parts[i])
		if not sub_reply.is_empty():
			reply["sub_reply_list"].append(sub_reply)

	reply["replies"] = (reply["sub_reply_list"] as Array).size()
	return reply


static func _parse_sub_reply(text: String) -> Dictionary:
	var header_and_content := _split_header_content(text)
	var header: Dictionary = header_and_content[0]
	var content: String = header_and_content[1]
	if content.is_empty():
		return {}
	return {
		"author": header.get("author", "匿名用户"),
		"time": header.get("time", ""),
		"likes": _to_int(header.get("likes", "0")),
		"content": content,
	}


## 将文本拆分为 header（key: value 行）和 content（空行后的自由文本）
## 返回 [Dictionary, String]
static func _split_header_content(text: String) -> Array:
	var header: Dictionary = {}
	var lines := text.split("\n")
	var content_start := 0
	var found_header := false

	for i in range(lines.size()):
		var line := lines[i].strip_edges()
		if line.is_empty():
			if found_header:
				# 第一个空行标志头部结束
				content_start = i + 1
				break
			continue
		var colon := line.find(":")
		if colon > 0 and colon < line.length() - 1:
			var key := line.substr(0, colon).strip_edges().to_lower()
			var value := line.substr(colon + 1).strip_edges()
			# 只接受已知 header key
			if key in ["author", "time", "likes", "replies", "title"]:
				header[key] = value
				found_header = true
				content_start = i + 1
				continue
		# 不是 key: value 行，说明头部结束，此行开始就是 content
		content_start = i
		break

	# 拼接 content
	var content_lines: Array = []
	for i in range(content_start, lines.size()):
		content_lines.append(lines[i])

	var content := "\n".join(PackedStringArray(content_lines)).strip_edges()
	return [header, content]


## 安全转 int
static func _to_int(value: String) -> int:
	var cleaned := value.strip_edges()
	if cleaned.is_valid_int():
		return int(cleaned)
	# 支持负数
	if cleaned.begins_with("-") and cleaned.substr(1).is_valid_int():
		return int(cleaned)
	return 0
