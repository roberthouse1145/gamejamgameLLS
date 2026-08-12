extends Node
## MailManager 稳定契约：投递、顺序、未读状态与存档快照。

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_mailbox_contract()
	print("[TestMailManager] 结果: %d 通过, %d 失败" % [_passed, _failed])


func _check(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
		print("[TestMailManager] PASS: " + test_name)
	else:
		_failed += 1
		push_error("[TestMailManager] FAIL: " + test_name)


func _test_mailbox_contract() -> void:
	MailManager.reset_runtime_state()
	var first: Dictionary = MailManager.receive_mail(
		"星茫网络",
		"hr@xingmang.example",
		"第一封邮件",
		"这是第一封邮件正文。",
		"第1天 · 上午",
		"test_session"
	)
	var second: Dictionary = MailManager.receive_mail(
		"系统通知",
		"",
		"第二封邮件",
		"这是第二封邮件正文。"
	)
	_check(not first.is_empty() and not second.is_empty(), "有效邮件可投递")
	var messages: Array[Dictionary] = MailManager.get_messages()
	_check(messages.size() == 2 and messages[0].get("mail_id") == second.get("mail_id"), "收件箱按最新来信优先读取")
	_check(MailManager.get_unread_count() == 2, "新邮件默认未读")
	_check(MailManager.mark_read(str(first.get("mail_id"))), "邮件可标记为已读")
	_check(MailManager.get_unread_count() == 1, "未读计数随已读状态更新")
	var snapshot: Dictionary = GameState.to_dict()
	var stored_messages: Array = snapshot.get("mail_messages", [])
	_check(stored_messages.size() == 2 and bool(stored_messages[0].get("is_read")), "邮件正文与已读状态进入 GameState 存档")
	MailManager.reset_runtime_state()
