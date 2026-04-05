class_name ActivityPreviewHint
extends Node

const ActivityPreviewLayerClass = preload("res://scripts/ui/activity_preview/activity_preview_layer.gd")

@export var preview_title: String = ""
@export_multiline var preview_text: String = ""
@export var preview_conditions: PackedStringArray = PackedStringArray()
@export var preview_rewards: Dictionary = {}
@export var preview_disabled_reason: String = ""
@export var preview_accent_color: Color = Color(0, 0, 0, 0)

var _target: Control = null
var _layer: Control = null
var _payload_override: Dictionary = {}
var _payload_resolver: Callable = Callable()


func _ready() -> void:
	_target = get_parent() as Control
	if _target == null:
		push_warning("ActivityPreviewHint parent must be a Control")
		return

	_layer = ActivityPreviewLayerClass.ensure_for(_find_host_root(_target))
	_target.mouse_entered.connect(_on_target_mouse_entered)
	_target.mouse_exited.connect(_on_target_mouse_exited)
	_target.focus_entered.connect(_on_target_mouse_entered)
	_target.focus_exited.connect(_on_target_mouse_exited)
	_target.tree_exiting.connect(_on_target_tree_exiting)


func set_preview_payload(payload: Dictionary) -> void:
	_payload_override = payload.duplicate(true)


func set_payload_resolver(resolver: Callable) -> void:
	_payload_resolver = resolver


func _on_target_mouse_entered() -> void:
	if _target == null:
		return
	if _layer == null:
		_layer = ActivityPreviewLayerClass.ensure_for(_find_host_root(_target))
	if _layer == null:
		return
	_layer.show_preview(_target, _build_payload())


func _on_target_mouse_exited() -> void:
	if _layer != null:
		_layer.hide_preview(_target)


func _on_target_tree_exiting() -> void:
	if _layer != null:
		_layer.hide_preview(_target)


func _build_payload() -> Dictionary:
	var payload: Dictionary = {
		"title": preview_title,
		"text": preview_text,
		"conditions": Array(preview_conditions),
		"rewards": preview_rewards.duplicate(true),
		"disabled_reason": preview_disabled_reason,
	}
	if preview_accent_color.a > 0.0:
		payload["accent_color"] = preview_accent_color

	if _payload_resolver.is_valid():
		var resolved: Variant = _payload_resolver.call()
		if resolved is Dictionary:
			payload.merge((resolved as Dictionary).duplicate(true), true)

	payload.merge(_payload_override.duplicate(true), true)
	return payload


func _find_host_root(target: Control) -> Control:
	var current: Control = target
	var root: Control = target
	while current != null:
		root = current
		var parent := current.get_parent()
		if not parent is Control:
			break
		current = parent as Control
	return root
