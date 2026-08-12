class_name PostDSLParser extends RefCounted
## 解析面向自然语言正文的 Post DSL。块文本无需 JSON 字符串转义。

const MEDIA_NONE: String = "none"
const MEDIA_ASSET: String = "asset"
const MEDIA_GENERATE: String = "generate"
const REACH_LOW: String = "low"
const REACH_NORMAL: String = "normal"
const REACH_HIGH: String = "high"
const REACH_VALUES: PackedStringArray = [REACH_LOW, REACH_NORMAL, REACH_HIGH]


func parse(source: String) -> Dictionary:
	var posts: Array[Dictionary] = []
	var errors: Array[String] = []
	var lines: PackedStringArray = source.replace("\r\n", "\n").replace("\r", "\n").split("\n", true)
	var current: Dictionary = {}
	var current_comment: Dictionary = {}
	var block_lines: Array[String] = []
	var state: String = "outside"

	for line_index: int in range(lines.size()):
		var raw_line: String = lines[line_index]
		var command: String = raw_line.strip_edges()
		var line_number: int = line_index + 1
		match state:
			"post_text":
				if command == "END_TEXT":
					current["text"] = "\n".join(block_lines).strip_edges()
					block_lines.clear()
					state = "post"
				else:
					block_lines.append(raw_line)
				continue
			"image_prompt":
				if command == "END_IMAGE_PROMPT":
					current["image_prompt"] = "\n".join(block_lines).strip_edges()
					block_lines.clear()
					state = "post"
				else:
					block_lines.append(raw_line)
				continue
			"comment_text":
				if command == "END_COMMENT":
					current_comment["text"] = "\n".join(block_lines).strip_edges()
					block_lines.clear()
					var comment_error_count: int = errors.size()
					_validate_comment(current_comment, line_number, errors)
					if errors.size() == comment_error_count:
						var comments: Array[Dictionary] = []
						comments.assign(current.get("comments", []))
						comments.append(current_comment.duplicate(true))
						current["comments"] = comments
					current_comment.clear()
					state = "post"
				else:
					block_lines.append(raw_line)
				continue

		# Markdown 围栏是 LLM 传输包装；只在正文块之外忽略，不改动用户内容。
		if command.begins_with("```"):
			continue
		if command.is_empty():
			continue
		if state == "outside":
			if not command.begins_with("POST "):
				errors.append("line %d: expected POST <account_id>" % line_number)
				continue
			var account_id: String = command.trim_prefix("POST ").strip_edges()
			if account_id.is_empty() or account_id.contains(" "):
				errors.append("line %d: invalid account_id" % line_number)
				continue
			var comments: Array[Dictionary] = []
			current = {
				"account_id": account_id,
				"text": "",
				"has_text": false,
				"media_mode": MEDIA_NONE,
				"asset_ref": "",
				"image_prompt": "",
				"reach": "",
				"comments": comments,
			}
			state = "post"
			continue

		match command:
			"TEXT":
				if bool(current.get("has_text", false)):
					errors.append("line %d: duplicate TEXT block" % line_number)
				else:
					current["has_text"] = true
					state = "post_text"
			"MEDIA NONE":
				current["media_mode"] = MEDIA_NONE
				current["asset_ref"] = ""
				current["image_prompt"] = ""
			"MEDIA GENERATE":
				current["media_mode"] = MEDIA_GENERATE
				current["asset_ref"] = ""
			"IMAGE_PROMPT":
				if str(current.get("media_mode", "")) != MEDIA_GENERATE:
					errors.append("line %d: IMAGE_PROMPT requires MEDIA GENERATE" % line_number)
				else:
					state = "image_prompt"
			"END_POST":
				var post_error_count: int = errors.size()
				_validate_post(current, line_number, errors)
				if errors.size() == post_error_count:
					posts.append(current.duplicate(true))
				current.clear()
				state = "outside"
			_:
				if command.begins_with("MEDIA ASSET "):
					var asset_ref: String = command.trim_prefix("MEDIA ASSET ").strip_edges()
					if asset_ref.is_empty() or asset_ref.contains(" "):
						errors.append("line %d: invalid asset_ref" % line_number)
					else:
						current["media_mode"] = MEDIA_ASSET
						current["asset_ref"] = asset_ref
						current["image_prompt"] = ""
				elif command.begins_with("REACH "):
					var reach: String = command.trim_prefix("REACH ").strip_edges().to_lower()
					if not REACH_VALUES.has(reach):
						errors.append("line %d: invalid REACH" % line_number)
					elif not str(current.get("reach", "")).is_empty():
						errors.append("line %d: duplicate REACH" % line_number)
					else:
						current["reach"] = reach
				elif command.begins_with("COMMENT "):
					var author_ref: String = command.trim_prefix("COMMENT ").strip_edges()
					if author_ref.is_empty():
						errors.append("line %d: COMMENT requires author_ref" % line_number)
					else:
						current_comment = {
							"author_ref": author_ref,
							"text": "",
						}
						block_lines.clear()
						state = "comment_text"
				else:
					errors.append("line %d: unknown command '%s'" % [line_number, command])

	if state == "post_text":
		errors.append("end of input: missing END_TEXT")
	elif state == "image_prompt":
		errors.append("end of input: missing END_IMAGE_PROMPT")
	elif state == "comment_text":
		errors.append("end of input: missing END_COMMENT")
	elif state == "post":
		errors.append("end of input: missing END_POST")
	return {
		"success": errors.is_empty() and not posts.is_empty(),
		"posts": posts,
		"errors": errors,
	}


func _validate_post(post: Dictionary, line_number: int, errors: Array[String]) -> void:
	if str(post.get("text", "")).is_empty():
		errors.append("line %d: post requires non-empty TEXT" % line_number)
	if not REACH_VALUES.has(str(post.get("reach", ""))):
		errors.append("line %d: post requires REACH LOW, NORMAL, or HIGH" % line_number)
	var comments_value: Variant = post.get("comments", [])
	if not comments_value is Array or comments_value.is_empty():
		errors.append("line %d: post requires at least one COMMENT" % line_number)
	var media_mode: String = str(post.get("media_mode", MEDIA_NONE))
	if media_mode == MEDIA_ASSET and str(post.get("asset_ref", "")).is_empty():
		errors.append("line %d: MEDIA ASSET requires asset_ref" % line_number)
	if media_mode == MEDIA_GENERATE and str(post.get("image_prompt", "")).is_empty():
		errors.append("line %d: MEDIA GENERATE requires IMAGE_PROMPT" % line_number)
	post.erase("has_text")


func _validate_comment(comment: Dictionary, line_number: int, errors: Array[String]) -> void:
	if str(comment.get("author_ref", "")).strip_edges().is_empty():
		errors.append("line %d: COMMENT requires author_ref" % line_number)
	if str(comment.get("text", "")).strip_edges().is_empty():
		errors.append("line %d: COMMENT requires non-empty content" % line_number)
