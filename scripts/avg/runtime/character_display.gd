class_name CharacterDisplay extends Control
## Manages character sprite display on screen for AVG games
## Supports: show/hide with fade, crossfade expression change, flip, move,
## animation effects (jump/shake/nod/bounce), opacity/scale/tint control.
##
## All positioning uses normalized coordinates (0-1) converted to design resolution pixels.
## The parent DesignContainer handles viewport scaling, so this class doesn't need to.

## Emitted when a character is shown
signal character_shown(character_id: String)
## Emitted when a character is hidden
signal character_hidden(character_id: String)
## Emitted when an effect animation finishes
signal effect_finished(character_id: String)

const AVGCharacterClass = preload("res://scripts/avg/resources/avg_character.gd")

## Predefined screen positions (normalized 0-1)
const POSITIONS: Dictionary = {
	"left": Vector2(0.2, 0.5),
	"center": Vector2(0.5, 0.5),
	"right": Vector2(0.8, 0.5),
	"far_left": Vector2(0.1, 0.5),
	"far_right": Vector2(0.9, 0.5),
}
const STAGE_LAYOUTS: Dictionary = {
	0: [],
	1: [Vector2(0.5, 0.5)],
	2: [Vector2(0.33, 0.5), Vector2(0.67, 0.5)],
	3: [Vector2(0.2, 0.5), Vector2(0.5, 0.5), Vector2(0.8, 0.5)],
	4: [Vector2(0.12, 0.5), Vector2(0.37, 0.5), Vector2(0.63, 0.5), Vector2(0.88, 0.5)],
	5: [Vector2(0.08, 0.5), Vector2(0.28, 0.5), Vector2(0.5, 0.5), Vector2(0.72, 0.5), Vector2(0.92, 0.5)],
}

## Expression transition modes
const TRANSITION_CROSSFADE: int = 0
const TRANSITION_INSTANT: int = 1
const TRANSITION_FADE_THROUGH_BLACK: int = 2

const VISIBILITY_EFFECT_FADE: String = "fade"
const VISIBILITY_EFFECT_NONE: String = "none"
const SHOW_EFFECT_POP_IN: String = "pop_in"
const HIDE_EFFECT_POP_OUT: String = "pop_out"
const SHOW_EFFECTS_WITH_SLIDE: Array[String] = [
	"slide_from_left",
	"slide_from_right",
	"slide_from_top",
	"slide_from_bottom",
]
const HIDE_EFFECTS_WITH_SLIDE: Array[String] = [
	"slide_to_left",
	"slide_to_right",
	"slide_to_top",
	"slide_to_bottom",
]

## Container for character sprites
@onready var sprite_container: Control = self

## character_id -> TextureRect (main sprite)
var _active_characters: Dictionary = {}
## character_id -> Dictionary of state {flip, scale_factor, opacity, position_ratio, current_emotion}
var _character_state: Dictionary = {}
## character_id -> AVGCharacter data dict
var _character_data: Dictionary = {}
## character_id -> active Tween (for cancellation)
var _active_tweens: Dictionary = {}
## character_id -> crossfade overlay TextureRect (if mid-transition)
var _crossfade_overlays: Dictionary = {}

## Dialog settings reference (for default_expression_transition)
var _dialog_settings: Resource = null

## Design resolution provided by avg_scene_runner
var _design_resolution: Vector2 = Vector2(2560, 1440)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Set the design resolution
func set_design_resolution(res: Vector2) -> void:
	if res.x > 0 and res.y > 0:
		_design_resolution = res


## Set dialog settings (for default expression transition)
func set_dialog_settings(settings: Resource) -> void:
	_dialog_settings = settings


## Set character data for sprite lookup
func set_character_data(characters: Dictionary) -> void:
	_character_data = characters


# =============================================================================
# Show / Hide
# =============================================================================

## Show a character on screen
func show_character(character_id: String, pos_name: String = "center", emotion: String = "", fade_duration: float = 0.3, flip: bool = false, char_scale: float = 1.0, opacity: float = 1.0, outfit: String = "", enter_effect: String = "fade", enter_distance: float = 0.08, enter_easing: String = "ease_out") -> void:
	var resolved_character_id: String = _resolve_character_reference(character_id)

	var resolved_outfit: String = _resolve_outfit(resolved_character_id, outfit)
	var texture: Texture2D = _get_character_texture(resolved_character_id, emotion, resolved_outfit)

	# 容错：角色数据不存在且无可用纹理时跳过（防止 LLM 幻觉角色创建幽灵节点）
	if texture == null and not _character_data.has(resolved_character_id):
		push_warning("CharacterDisplay: character '%s' has no data and no texture, skipping show" % character_id)
		return

	var sprite: TextureRect = _get_or_create_sprite(resolved_character_id)
	_cancel_crossfade(resolved_character_id)
	if texture != null:
		sprite.texture = texture
		_apply_texture_size(sprite, texture, resolved_character_id)

	var pos_ratio: Vector2 = _parse_position(pos_name)
	_position_sprite(sprite, pos_ratio, resolved_character_id)
	var target_pos: Vector2 = sprite.position

	# Init state
	_character_state[resolved_character_id] = {
		"flip": flip,
		"scale_factor": char_scale,
		"opacity": opacity,
		"position_ratio": pos_ratio,
		"current_emotion": emotion if not emotion.is_empty() else "default",
		"current_outfit": resolved_outfit,
	}

	# Apply flip and scale (this is character scale, not viewport scale)
	var sx: float = - char_scale if flip else char_scale
	sprite.pivot_offset = sprite.size / 2.0
	var target_scale: Vector2 = Vector2(sx, char_scale)
	sprite.scale = target_scale
	_play_show_effect(resolved_character_id, sprite, target_pos, target_scale, opacity, fade_duration, enter_effect, enter_distance, enter_easing)


## Hide a character from screen
func hide_character(character_id: String, fade_duration: float = 0.3, exit_effect: String = "fade", exit_distance: float = 0.08, exit_easing: String = "ease_in") -> void:
	var resolved_character_id: String = _resolve_character_reference(character_id)
	if not _active_characters.has(resolved_character_id):
		return
	var sprite: TextureRect = _active_characters[resolved_character_id]
	_cancel_crossfade(resolved_character_id)
	_play_hide_effect(resolved_character_id, sprite, fade_duration, exit_effect, exit_distance, exit_easing)


## Hide all characters
func hide_all(fade_duration: float = 0.3) -> void:
	for character_id in _active_characters.keys():
		hide_character(character_id, fade_duration)


## 根据传入顺序自动排位舞台角色，并补齐登场/离场/补位逻辑。
func stage_set(character_refs: Array, emotions_spec: String = "", outfits_spec: String = "", duration: float = 0.35, enter_effect: String = "fade", exit_effect: String = "fade", enter_distance: float = 0.08, exit_distance: float = 0.08, enter_easing: String = "ease_out", exit_easing: String = "ease_in", move_easing: String = "ease_in_out") -> void:
	var target_ids: Array[String] = _resolve_stage_character_ids(character_refs)
	if not STAGE_LAYOUTS.has(target_ids.size()):
		push_warning("CharacterDisplay: stage_set supports up to 5 characters, got %d" % target_ids.size())
		return

	var safe_duration: float = maxf(duration, 0.0)
	var target_layout: Array = STAGE_LAYOUTS.get(target_ids.size(), [])
	var emotion_overrides: Array[String] = _parse_stage_override_list(emotions_spec, target_ids.size())
	var outfit_overrides: Array[String] = _parse_stage_override_list(outfits_spec, target_ids.size())
	var target_lookup: Dictionary = {}
	for character_id in target_ids:
		target_lookup[character_id] = true

	for visible_id in get_visible_character_ids():
		if target_lookup.has(visible_id):
			continue
		hide_character(visible_id, safe_duration, exit_effect, exit_distance, exit_easing)

	for index in range(target_ids.size()):
		var target_id: String = target_ids[index]
		var target_ratio: Vector2 = target_layout[index]
		var target_position: String = _format_stage_position(target_ratio)
		var emotion_override: String = emotion_overrides[index]
		var outfit_override: String = outfit_overrides[index]

		if is_character_visible(target_id):
			_apply_stage_visual_overrides(target_id, emotion_override, outfit_override)
			var state: Dictionary = _character_state.get(target_id, {})
			var current_ratio: Variant = state.get("position_ratio", POSITIONS.get("center", Vector2(0.5, 0.5)))
			if current_ratio is Vector2 and current_ratio.is_equal_approx(target_ratio):
				continue
			move_character(target_id, target_position, safe_duration, move_easing)
			continue

		var stage_state: Dictionary = _character_state.get(target_id, {})
		var flip: bool = bool(stage_state.get("flip", false))
		var char_scale: float = float(stage_state.get("scale_factor", 1.0))
		var opacity: float = float(stage_state.get("opacity", 1.0))
		show_character(
			target_id,
			target_position,
			emotion_override,
			safe_duration,
			flip,
			char_scale,
			opacity,
			outfit_override,
			enter_effect,
			enter_distance,
			enter_easing
		)


func stage_enter(character_refs: Array, emotions_spec: String = "", outfits_spec: String = "", duration: float = 0.35, enter_effect: String = "fade", enter_distance: float = 0.08, enter_easing: String = "ease_out", move_easing: String = "ease_in_out") -> void:
	var entering_ids: Array[String] = _resolve_stage_character_ids(character_refs)
	if entering_ids.is_empty():
		return

	var current_stage_ids: Array[String] = get_visible_character_ids_in_stage_order()
	var next_stage_ids: Array[String] = current_stage_ids.duplicate()
	var actually_entering_ids: Array[String] = []
	for character_id in entering_ids:
		if next_stage_ids.has(character_id):
			continue
		next_stage_ids.append(character_id)
		actually_entering_ids.append(character_id)

	if next_stage_ids.size() > STAGE_LAYOUTS.size() - 1:
		push_warning("CharacterDisplay: stage_enter supports at most %d stage characters, got %d" % [STAGE_LAYOUTS.size() - 1, next_stage_ids.size()])
		return

	var emotion_overrides: Array[String] = []
	var outfit_overrides: Array[String] = []
	for _index in range(current_stage_ids.size()):
		emotion_overrides.append("")
		outfit_overrides.append("")

	emotion_overrides.append_array(_parse_stage_override_list(emotions_spec, actually_entering_ids.size()))
	outfit_overrides.append_array(_parse_stage_override_list(outfits_spec, actually_entering_ids.size()))

	stage_set(
		next_stage_ids,
		",".join(PackedStringArray(emotion_overrides)),
		",".join(PackedStringArray(outfit_overrides)),
		duration,
		enter_effect,
		"fade",
		enter_distance,
		0.08,
		enter_easing,
		"ease_in",
		move_easing
	)


func stage_exit(character_refs: Array, duration: float = 0.35, exit_effect: String = "fade", exit_distance: float = 0.08, exit_easing: String = "ease_in", move_easing: String = "ease_in_out") -> void:
	var exiting_ids: Array[String] = _resolve_stage_character_ids(character_refs)
	if exiting_ids.is_empty():
		return

	var current_stage_ids: Array[String] = get_visible_character_ids_in_stage_order()
	if current_stage_ids.is_empty():
		return

	var next_stage_ids: Array[String] = []
	for character_id in current_stage_ids:
		if exiting_ids.has(character_id):
			continue
		next_stage_ids.append(character_id)

	stage_set(
		next_stage_ids,
		"",
		"",
		duration,
		"fade",
		exit_effect,
		0.08,
		exit_distance,
		"ease_out",
		exit_easing,
		move_easing
	)


# =============================================================================
# Expression Change (Crossfade)
# =============================================================================

## Change expression with transition
func change_expression(character_id: String, expression: String, transition: String = "", duration: float = -1.0, outfit: String = "") -> void:
	var resolved_character_id: String = _resolve_character_reference(character_id)
	if not _active_characters.has(resolved_character_id):
		return
	var sprite: TextureRect = _active_characters[resolved_character_id]

	var target_outfit: String = outfit.strip_edges()
	if target_outfit.is_empty():
		target_outfit = str(_character_state.get(resolved_character_id, {}).get("current_outfit", "")).strip_edges()

	var resolved_outfit: String = _resolve_outfit(resolved_character_id, target_outfit)
	var new_texture: Texture2D = _get_character_texture(resolved_character_id, expression, resolved_outfit)
	if new_texture == null:
		return

	var previous_state: Dictionary = _character_state.get(resolved_character_id, {})
	var current_emotion: String = str(previous_state.get("current_emotion", "")).strip_edges()
	var current_outfit: String = str(previous_state.get("current_outfit", "")).strip_edges()
	var target_emotion: String = expression.strip_edges()
	if target_emotion.is_empty():
		target_emotion = "default"

	if sprite.texture == new_texture and current_emotion == target_emotion and current_outfit == resolved_outfit:
		return

	var mode: int = _resolve_transition_mode(transition)
	var dur: float = duration if duration >= 0.0 else _get_default_expression_duration()

	if _character_state.has(resolved_character_id):
		_character_state[resolved_character_id]["current_emotion"] = target_emotion
		_character_state[resolved_character_id]["current_outfit"] = resolved_outfit

	_cancel_crossfade(resolved_character_id)

	match mode:
		TRANSITION_INSTANT:
			_apply_texture_preserve_center(sprite, new_texture, resolved_character_id)
		TRANSITION_CROSSFADE:
			_do_crossfade(resolved_character_id, sprite, new_texture, dur)
		TRANSITION_FADE_THROUGH_BLACK:
			_do_fade_through(resolved_character_id, sprite, new_texture, dur)


func change_outfit(character_id: String, outfit: String, transition: String = "", duration: float = -1.0, emotion: String = "") -> void:
	var resolved_character_id: String = _resolve_character_reference(character_id)
	if not _active_characters.has(resolved_character_id):
		return
	var target_emotion: String = emotion.strip_edges()
	if target_emotion.is_empty():
		target_emotion = str(_character_state.get(resolved_character_id, {}).get("current_emotion", "default")).strip_edges()
	if target_emotion.is_empty():
		target_emotion = "default"
	change_expression(resolved_character_id, target_emotion, transition, duration, outfit)


func _do_crossfade(character_id: String, sprite: TextureRect, new_texture: Texture2D, duration: float) -> void:
	if duration <= 0.0:
		_apply_texture_preserve_center(sprite, new_texture, character_id)
		return

	var old_texture: Texture2D = sprite.texture
	if old_texture == null:
		_apply_texture_preserve_center(sprite, new_texture, character_id)
		return

	# If the show/hide visibility tween is still running, a crossfade would
	# conflict with it (both tweening modulate). Fall back to instant swap.
	var visibility_key: String = _get_visibility_tween_key(character_id)
	if _active_tweens.has(visibility_key):
		var vis_tween: Tween = _active_tweens[visibility_key]
		if vis_tween != null and vis_tween.is_valid() and vis_tween.is_running():
			_apply_texture_preserve_center(sprite, new_texture, character_id)
			return

	var original_modulate: Color = sprite.modulate
	var overlay: TextureRect = _create_crossfade_overlay(character_id, sprite, old_texture)
	_apply_texture_preserve_center(sprite, new_texture, character_id)
	sprite.modulate = original_modulate

	var crossfade_key: String = _get_crossfade_tween_key(character_id)
	_cancel_tween(crossfade_key)
	var tween := create_tween()
	_active_tweens[crossfade_key] = tween
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(overlay, "modulate:a", 0.0, duration)
	tween.finished.connect(func():
		if not is_instance_valid(self):
			return
		if is_instance_valid(overlay):
			overlay.queue_free()
		_active_tweens.erase(crossfade_key)
		if _crossfade_overlays.get(character_id, null) == overlay:
			_crossfade_overlays.erase(character_id)
	)


func _do_fade_through(character_id: String, sprite: TextureRect, new_texture: Texture2D, duration: float) -> void:
	if duration <= 0.0:
		sprite.texture = new_texture
		return

	# If the show/hide visibility tween is still running, fall back to instant.
	var visibility_key: String = _get_visibility_tween_key(character_id)
	if _active_tweens.has(visibility_key):
		var vis_tween: Tween = _active_tweens[visibility_key]
		if vis_tween != null and vis_tween.is_valid() and vis_tween.is_running():
			_apply_texture_preserve_center(sprite, new_texture, character_id)
			return

	var half: float = duration / 2.0
	var original_alpha: float = sprite.modulate.a
	var fade_key: String = character_id + "_fade"
	_cancel_tween(fade_key)

	var tween := create_tween()
	_active_tweens[fade_key] = tween
	tween.tween_property(sprite, "modulate:a", 0.0, half)
	tween.tween_callback(func():
		if is_instance_valid(sprite):
			_apply_texture_preserve_center(sprite, new_texture, character_id)
	)
	tween.tween_property(sprite, "modulate:a", original_alpha, half)
	tween.finished.connect(func():
		if not is_instance_valid(self ):
			return
		_active_tweens.erase(fade_key)
	)


func _cancel_crossfade(character_id: String) -> void:
	var sprite: TextureRect = _active_characters.get(character_id, null)
	if is_instance_valid(sprite):
		var target_alpha: float = float(_character_state.get(character_id, {}).get("opacity", sprite.modulate.a))
		sprite.modulate.a = target_alpha
	if _crossfade_overlays.has(character_id):
		var overlay: TextureRect = _crossfade_overlays[character_id]
		if is_instance_valid(overlay):
			overlay.queue_free()
		_crossfade_overlays.erase(character_id)
	_cancel_tween(_get_crossfade_tween_key(character_id))


func _resolve_stage_character_ids(character_refs: Array) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = {}
	for entry in character_refs:
		var trimmed_ref: String = str(entry).strip_edges()
		if trimmed_ref.is_empty():
			continue
		var resolved_id: String = _resolve_character_reference(trimmed_ref)
		if resolved_id.is_empty() or seen.has(resolved_id):
			continue
		seen[resolved_id] = true
		result.append(resolved_id)
	return result


func _parse_stage_override_list(raw_spec: String, expected_size: int) -> Array[String]:
	var result: Array[String] = []
	var trimmed_spec: String = raw_spec.strip_edges()
	if trimmed_spec.is_empty():
		for _index in range(expected_size):
			result.append("")
		return result

	for entry in trimmed_spec.split(","):
		var trimmed: String = entry.strip_edges()
		if trimmed == "_":
			trimmed = ""
		result.append(trimmed)

	while result.size() < expected_size:
		result.append("")
	if result.size() > expected_size:
		result.resize(expected_size)
	return result


func _apply_stage_visual_overrides(character_id: String, emotion_override: String, outfit_override: String) -> void:
	var trimmed_emotion: String = emotion_override.strip_edges()
	var trimmed_outfit: String = outfit_override.strip_edges()
	if trimmed_outfit.is_empty() and trimmed_emotion.is_empty():
		return
	if not trimmed_outfit.is_empty():
		change_outfit(character_id, trimmed_outfit, "", -1.0, trimmed_emotion)
		return
	change_expression(character_id, trimmed_emotion, "", -1.0)


func _format_stage_position(position_ratio: Vector2) -> String:
	return "%0.4f,%0.4f" % [position_ratio.x, position_ratio.y]


# =============================================================================
# Move
# =============================================================================

## Move character to a position (predefined name or "x,y" normalized coords)
func move_character(character_id: String, target: String, duration: float = 0.3, easing: String = "ease_in_out") -> void:
	var resolved_character_id: String = _resolve_character_reference(character_id)
	if not _active_characters.has(resolved_character_id):
		return
	var sprite: TextureRect = _active_characters[resolved_character_id]
	var pos_ratio: Vector2 = _parse_position(target)

	if _character_state.has(resolved_character_id):
		_character_state[resolved_character_id]["position_ratio"] = pos_ratio

	var target_pos: Vector2 = _calculate_position(pos_ratio, sprite, resolved_character_id)
	var move_key: String = resolved_character_id + "_move"
	_cancel_tween(move_key)

	if duration > 0.0:
		var tween := create_tween()
		_active_tweens[move_key] = tween
		_configure_tweener(tween.tween_property(sprite, "position", target_pos, duration), easing)
		tween.finished.connect(func():
			if not is_instance_valid(self ):
				return
			_active_tweens.erase(move_key)
		)
	else:
		sprite.position = target_pos


## Move character by a relative offset (normalized)
func move_character_by(character_id: String, offset_x: float, offset_y: float, duration: float = 0.3) -> void:
	var resolved_character_id: String = _resolve_character_reference(character_id)
	if not _active_characters.has(resolved_character_id):
		return
	var sprite: TextureRect = _active_characters[resolved_character_id]
	var delta: Vector2 = Vector2(offset_x * _design_resolution.x, offset_y * _design_resolution.y)
	var target_pos: Vector2 = sprite.position + delta

	# Update state ratio
	if _character_state.has(resolved_character_id):
		var sprite_size: Vector2 = sprite.size if sprite.size != Vector2.ZERO else Vector2(200, 400)
		var center: Vector2 = target_pos + sprite_size / 2.0
		_character_state[resolved_character_id]["position_ratio"] = center / _design_resolution

	var move_key: String = resolved_character_id + "_move"
	_cancel_tween(move_key)

	if duration > 0.0:
		var tween := create_tween()
		_active_tweens[move_key] = tween
		tween.tween_property(sprite, "position", target_pos, duration)
		tween.finished.connect(func():
			if not is_instance_valid(self ):
				return
			_active_tweens.erase(move_key)
		)
	else:
		sprite.position = target_pos


# =============================================================================
# Flip
# =============================================================================

## Flip character horizontally
func flip_character(character_id: String, mode: String = "toggle", duration: float = 0.0) -> void:
	var resolved_character_id: String = _resolve_character_reference(character_id)
	if not _active_characters.has(resolved_character_id):
		return
	var sprite: TextureRect = _active_characters[resolved_character_id]
	var state: Dictionary = _character_state.get(resolved_character_id, {})
	var is_flipped: bool = state.get("flip", false)
	var char_scale: float = state.get("scale_factor", 1.0)

	match mode:
		"on":
			is_flipped = true
		"off":
			is_flipped = false
		_:
			is_flipped = not is_flipped

	if _character_state.has(resolved_character_id):
		_character_state[resolved_character_id]["flip"] = is_flipped

	var target_sx: float = - char_scale if is_flipped else char_scale
	sprite.pivot_offset = sprite.size / 2.0

	var flip_key: String = resolved_character_id + "_flip"
	_cancel_tween(flip_key)

	if duration > 0.0:
		var tween := create_tween()
		_active_tweens[flip_key] = tween
		tween.tween_property(sprite, "scale:x", target_sx, duration)
		tween.finished.connect(func():
			if not is_instance_valid(self ):
				return
			_active_tweens.erase(flip_key)
		)
	else:
		sprite.scale.x = target_sx


# =============================================================================
# Animation Effects
# =============================================================================

## Play an animation effect on a character
func play_effect(character_id: String, effect_name: String, intensity: String = "medium", duration: float = -1.0) -> void:
	var resolved_character_id: String = _resolve_character_reference(character_id)
	if not _active_characters.has(resolved_character_id):
		return
	var sprite: TextureRect = _active_characters[resolved_character_id]
	var original_pos: Vector2 = sprite.position

	var mult: float = _get_intensity_multiplier(intensity)

	var effect_key: String = resolved_character_id + "_effect"
	if _active_tweens.has(effect_key):
		var old_tween: Tween = _active_tweens[effect_key]
		if old_tween != null and old_tween.is_valid():
			old_tween.kill()
		_active_tweens.erase(effect_key)
		sprite.position = original_pos

	var tween := create_tween()
	_active_tweens[effect_key] = tween

	match effect_name:
		"jump":
			var jump_height: float = 40.0 * mult
			var dur: float = duration if duration > 0.0 else 0.4
			tween.tween_property(sprite, "position:y", original_pos.y - jump_height, dur * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(sprite, "position:y", original_pos.y, dur * 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		"shake":
			var shake_amount: float = 8.0 * mult
			var dur: float = duration if duration > 0.0 else 0.5
			var steps: int = 8
			var step_dur: float = dur / float(steps)
			for i in range(steps):
				var offset_x: float = shake_amount * (1.0 if i % 2 == 0 else -1.0) * (1.0 - float(i) / float(steps))
				tween.tween_property(sprite, "position:x", original_pos.x + offset_x, step_dur)
			tween.tween_property(sprite, "position:x", original_pos.x, step_dur)
		"nod":
			var nod_amount: float = 12.0 * mult
			var dur: float = duration if duration > 0.0 else 0.4
			tween.tween_property(sprite, "position:y", original_pos.y + nod_amount, dur * 0.3)
			tween.tween_property(sprite, "position:y", original_pos.y, dur * 0.3)
			tween.tween_property(sprite, "position:y", original_pos.y + nod_amount * 0.5, dur * 0.2)
			tween.tween_property(sprite, "position:y", original_pos.y, dur * 0.2)
		"bounce":
			var bounce_height: float = 20.0 * mult
			var dur: float = duration if duration > 0.0 else 0.6
			for i in range(3):
				var h: float = bounce_height * (1.0 - float(i) * 0.3)
				var seg: float = dur / 3.0
				tween.tween_property(sprite, "position:y", original_pos.y - h, seg * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				tween.tween_property(sprite, "position:y", original_pos.y, seg * 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_:
			push_warning("CharacterDisplay: Unknown effect '%s'" % effect_name)
			tween.kill()
			_active_tweens.erase(effect_key)
			return

	tween.finished.connect(func():
		if not is_instance_valid(self ):
			return
		_active_tweens.erase(effect_key)
		if is_instance_valid(sprite):
			sprite.position = original_pos
		effect_finished.emit(resolved_character_id)
	)


# =============================================================================
# Property Control (opacity, scale, tint)
# =============================================================================

## Set character visual property with optional animation
func set_character_property(character_id: String, property: String, value: Variant, duration: float = 0.3) -> void:
	var resolved_character_id: String = _resolve_character_reference(character_id)
	if not _active_characters.has(resolved_character_id):
		return
	var sprite: TextureRect = _active_characters[resolved_character_id]
	# Use a per-property tween key so different properties do not cancel each other.
	var prop_key: String = resolved_character_id + "_prop_" + property
	_cancel_tween(prop_key)

	match property:
		"color":
			# Color (RGBA): controls both tint and opacity.
			var target_color: Color = Color.WHITE
			if value is Color:
				target_color = value
			elif value is String:
				target_color = Color.from_string(value, Color.WHITE)
			if _character_state.has(resolved_character_id):
				_character_state[resolved_character_id]["opacity"] = target_color.a
			if duration > 0.0:
				var tween := create_tween()
				_active_tweens[prop_key] = tween
				tween.tween_property(sprite, "modulate", target_color, duration)
				tween.finished.connect(func():
					if not is_instance_valid(self ):
						return
					_active_tweens.erase(prop_key)
				)
			else:
				sprite.modulate = target_color

		"opacity":
			# Backward compatibility: only change alpha and keep the current RGB.
			var target_alpha: float = clampf(float(value), 0.0, 1.0)
			if _character_state.has(resolved_character_id):
				_character_state[resolved_character_id]["opacity"] = target_alpha
			if duration > 0.0:
				var tween := create_tween()
				_active_tweens[prop_key] = tween
				tween.tween_property(sprite, "modulate:a", target_alpha, duration)
				tween.finished.connect(func():
					if not is_instance_valid(self ):
						return
					_active_tweens.erase(prop_key)
				)
			else:
				sprite.modulate.a = target_alpha

		"tint":
			# Backward compatibility: map tint to color.
			var target_color: Color = Color.WHITE
			if value is Color:
				target_color = value
			elif value is String:
				target_color = Color.from_string(value, Color.WHITE)
			if duration > 0.0:
				var tween := create_tween()
				_active_tweens[prop_key] = tween
				tween.tween_property(sprite, "modulate", target_color, duration)
				tween.finished.connect(func():
					if not is_instance_valid(self ):
						return
					_active_tweens.erase(prop_key)
				)
			else:
				sprite.modulate = target_color

		"scale":
			var target_scale: float = maxf(float(value), 0.01)
			if _character_state.has(resolved_character_id):
				_character_state[resolved_character_id]["scale_factor"] = target_scale
			var is_flipped: bool = _character_state.get(resolved_character_id, {}).get("flip", false)
			var sx: float = - target_scale if is_flipped else target_scale
			sprite.pivot_offset = sprite.size / 2.0
			if duration > 0.0:
				var tween := create_tween()
				_active_tweens[prop_key] = tween
				tween.set_parallel(true)
				tween.tween_property(sprite, "scale:x", sx, duration)
				tween.tween_property(sprite, "scale:y", target_scale, duration)
				tween.finished.connect(func():
					if not is_instance_valid(self ):
						return
					_active_tweens.erase(prop_key)
				)
			else:
				sprite.scale = Vector2(sx, target_scale)

		_:
			push_warning("CharacterDisplay: Unknown property '%s'" % property)


# =============================================================================
# Query API
# =============================================================================

func get_character_sprite(character_id: String) -> TextureRect:
	var resolved_character_id: String = _resolve_character_reference(character_id)
	return _active_characters.get(resolved_character_id, null)


func is_character_visible(character_id: String) -> bool:
	var resolved_character_id: String = _resolve_character_reference(character_id)
	if _active_characters.has(resolved_character_id):
		return _active_characters[resolved_character_id].visible
	return false


func get_visible_character_ids() -> Array[String]:
	var result: Array[String] = []
	for character_id in _active_characters.keys():
		if not is_character_visible(character_id):
			continue
		result.append(character_id)
	return result


func get_visible_character_ids_in_stage_order() -> Array[String]:
	var result: Array[String] = get_visible_character_ids()
	result.sort_custom(func(a: String, b: String) -> bool:
		var state_a: Dictionary = _character_state.get(a, {})
		var state_b: Dictionary = _character_state.get(b, {})
		var ratio_a: Variant = state_a.get("position_ratio", Vector2(0.5, 0.5))
		var ratio_b: Variant = state_b.get("position_ratio", Vector2(0.5, 0.5))
		var x_a: float = ratio_a.x if ratio_a is Vector2 else 0.5
		var x_b: float = ratio_b.x if ratio_b is Vector2 else 0.5
		if is_equal_approx(x_a, x_b):
			return a < b
		return x_a < x_b
	)
	return result


func get_character_state(character_id: String) -> Dictionary:
	var resolved_character_id: String = _resolve_character_reference(character_id)
	return _character_state.get(resolved_character_id, {})


func resolve_visible_character_id(reference: String) -> String:
	var trimmed_reference: String = reference.strip_edges()
	if trimmed_reference.is_empty():
		return ""
	var resolved_character_id: String = _resolve_character_reference(trimmed_reference)
	if _active_characters.has(resolved_character_id):
		var sprite: TextureRect = _active_characters[resolved_character_id]
		if is_instance_valid(sprite) and sprite.visible:
			return resolved_character_id
	for character_id in _active_characters.keys():
		if not is_character_visible(character_id):
			continue
		if _matches_character_reference(character_id, trimmed_reference):
			return character_id
	return ""


# =============================================================================
# Internal Helpers
# =============================================================================

func _play_show_effect(character_id: String, sprite: TextureRect, target_pos: Vector2, target_scale: Vector2, target_alpha: float, duration: float, enter_effect: String, enter_distance: float, enter_easing: String) -> void:
	var visibility_key: String = _get_visibility_tween_key(character_id)
	_cancel_tween(visibility_key)

	var normalized_effect: String = _normalize_visibility_effect(enter_effect)
	if duration <= 0.0 or normalized_effect == VISIBILITY_EFFECT_NONE:
		sprite.position = target_pos
		sprite.scale = target_scale
		sprite.modulate.a = target_alpha
		sprite.visible = true
		character_shown.emit(character_id)
		return

	var start_pos: Vector2 = target_pos
	var start_scale: Vector2 = target_scale
	var start_alpha: float = target_alpha

	match normalized_effect:
		VISIBILITY_EFFECT_FADE:
			start_alpha = 0.0
		SHOW_EFFECT_POP_IN:
			start_alpha = 0.0
			start_scale = target_scale * 0.92
		_:
			if SHOW_EFFECTS_WITH_SLIDE.has(normalized_effect):
				start_alpha = 0.0
				start_pos = target_pos + _get_visibility_effect_offset(normalized_effect, enter_distance)
			else:
				start_alpha = 0.0

	sprite.position = start_pos
	sprite.scale = start_scale
	sprite.modulate.a = start_alpha
	sprite.visible = true

	var tween := create_tween()
	_active_tweens[visibility_key] = tween
	tween.set_parallel(true)
	_configure_tweener(tween.tween_property(sprite, "modulate:a", target_alpha, duration), enter_easing)
	if start_pos != target_pos:
		_configure_tweener(tween.tween_property(sprite, "position", target_pos, duration), enter_easing)
	if start_scale != target_scale:
		var scale_transition: Variant = null
		if normalized_effect == SHOW_EFFECT_POP_IN:
			scale_transition = Tween.TRANS_BACK
		_configure_tweener(tween.tween_property(sprite, "scale", target_scale, duration), enter_easing, scale_transition)
	tween.finished.connect(func():
		if not is_instance_valid(self ):
			return
		_active_tweens.erase(visibility_key)
		if is_instance_valid(sprite):
			sprite.position = target_pos
			sprite.scale = target_scale
			sprite.modulate.a = target_alpha
		character_shown.emit(character_id)
	)


func _play_hide_effect(character_id: String, sprite: TextureRect, duration: float, exit_effect: String, exit_distance: float, exit_easing: String) -> void:
	var visibility_key: String = _get_visibility_tween_key(character_id)
	_cancel_tween(visibility_key)

	var original_pos: Vector2 = sprite.position
	var original_scale: Vector2 = sprite.scale
	var normalized_effect: String = _normalize_visibility_effect(exit_effect)

	if duration <= 0.0 or normalized_effect == VISIBILITY_EFFECT_NONE:
		sprite.modulate.a = 0.0
		sprite.visible = false
		character_hidden.emit(character_id)
		return

	var target_pos: Vector2 = original_pos
	var target_scale: Vector2 = original_scale

	match normalized_effect:
		VISIBILITY_EFFECT_FADE:
			pass
		HIDE_EFFECT_POP_OUT:
			target_scale = original_scale * 0.92
		_:
			if HIDE_EFFECTS_WITH_SLIDE.has(normalized_effect):
				target_pos = original_pos + _get_visibility_effect_offset(normalized_effect, exit_distance)

	var tween := create_tween()
	_active_tweens[visibility_key] = tween
	tween.set_parallel(true)
	_configure_tweener(tween.tween_property(sprite, "modulate:a", 0.0, duration), exit_easing)
	if target_pos != original_pos:
		_configure_tweener(tween.tween_property(sprite, "position", target_pos, duration), exit_easing)
	if target_scale != original_scale:
		_configure_tweener(tween.tween_property(sprite, "scale", target_scale, duration), exit_easing)
	tween.finished.connect(func():
		if not is_instance_valid(self ):
			return
		_active_tweens.erase(visibility_key)
		if is_instance_valid(sprite):
			sprite.position = original_pos
			sprite.scale = original_scale
			sprite.modulate.a = 0.0
			sprite.visible = false
		character_hidden.emit(character_id)
	)


func _get_or_create_sprite(character_id: String) -> TextureRect:
	if _active_characters.has(character_id):
		return _active_characters[character_id]

	var sprite := TextureRect.new()
	sprite.name = "Character_" + character_id
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.visible = false

	sprite_container.add_child(sprite)
	_active_characters[character_id] = sprite
	return sprite


func _apply_texture_preserve_center(sprite: TextureRect, texture: Texture2D, character_id: String = "") -> void:
	if texture == null:
		return
	var current_center: Vector2 = sprite.position + sprite.size / 2.0
	sprite.texture = texture
	_apply_texture_size(sprite, texture, character_id)
	sprite.pivot_offset = sprite.size / 2.0
	if sprite.size != Vector2.ZERO:
		sprite.position = current_center - sprite.size / 2.0


func _create_crossfade_overlay(character_id: String, source_sprite: TextureRect, texture: Texture2D) -> TextureRect:
	var overlay := TextureRect.new()
	overlay.name = "CrossfadeOverlay_" + character_id
	overlay.texture = texture
	overlay.expand_mode = source_sprite.expand_mode
	overlay.stretch_mode = source_sprite.stretch_mode
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.visible = source_sprite.visible
	overlay.position = source_sprite.position
	overlay.size = source_sprite.size
	overlay.scale = source_sprite.scale
	overlay.rotation = source_sprite.rotation
	overlay.pivot_offset = source_sprite.pivot_offset
	overlay.modulate = source_sprite.modulate
	# Keep the overlay in the same local z bucket as the source sprite so it
	# stays under full-screen grading layers like time_of_day.
	overlay.z_index = source_sprite.z_index
	sprite_container.add_child(overlay)
	_crossfade_overlays[character_id] = overlay
	return overlay


func _resolve_character_reference(reference: String) -> String:
	var trimmed_reference: String = reference.strip_edges()
	if trimmed_reference.is_empty():
		return ""
	if _character_data.has(trimmed_reference):
		return trimmed_reference
	for character_id in _character_data.keys():
		if _matches_character_reference(character_id, trimmed_reference):
			return character_id
	if _active_characters.has(trimmed_reference):
		return trimmed_reference
	for active_character_id in _active_characters.keys():
		if _matches_character_reference(active_character_id, trimmed_reference):
			return active_character_id
	return trimmed_reference


func _matches_character_reference(character_id: String, reference: String) -> bool:
	var trimmed_reference: String = reference.strip_edges()
	if character_id == trimmed_reference:
		return true
	var char_data = _character_data.get(character_id, null)
	if char_data == null:
		return false

	var candidates: Array[String] = [character_id]
	if char_data is Resource:
		candidates.append(str(char_data.display_name if "display_name" in char_data else ""))
		candidates.append(str(char_data.character_name if "character_name" in char_data else ""))
	elif char_data is Dictionary:
		candidates.append(str(char_data.get("display_name", "")))
		candidates.append(str(char_data.get("character_name", "")))
		candidates.append(str(char_data.get("name", "")))

	for candidate in candidates:
		var trimmed_candidate: String = candidate.strip_edges()
		if not trimmed_candidate.is_empty() and trimmed_candidate == trimmed_reference:
			return true
	return false


func _get_character_texture(character_id: String, emotion: String, outfit: String = "") -> Texture2D:
	var resolved_character_id: String = _resolve_character_reference(character_id)
	if not _character_data.has(resolved_character_id):
		push_warning("CharacterDisplay: Character '%s' not found in data" % character_id)
		return null

	var char_data = _character_data[resolved_character_id]
	var sprites: Dictionary = {}
	var resolved_outfit: String = _resolve_outfit(resolved_character_id, outfit)

	if char_data is Resource:
		sprites = char_data.sprites if "sprites" in char_data else {}
	elif char_data is Dictionary:
		sprites = char_data.get("sprites", {})

	if emotion.is_empty():
		emotion = "default"

	var dynamic_texture: Texture2D = AVGCharacterClass.resolve_texture_from_character(char_data, emotion, resolved_outfit)
	if dynamic_texture != null:
		return dynamic_texture

	var outfit_emotion_key: String = _build_outfit_emotion_key(resolved_outfit, emotion)
	var outfit_default_key: String = _build_outfit_emotion_key(resolved_outfit, "default")

	if not outfit_emotion_key.is_empty() and sprites.has(outfit_emotion_key):
		return sprites[outfit_emotion_key]
	elif sprites.has(emotion):
		return sprites[emotion]
	elif not outfit_default_key.is_empty() and sprites.has(outfit_default_key):
		return sprites[outfit_default_key]
	elif sprites.has("default"):
		return sprites["default"]
	elif sprites.size() > 0:
		return sprites.values()[0]
	return null


func _resolve_outfit(character_id: String, requested_outfit: String) -> String:
	character_id = _resolve_character_reference(character_id)
	var trimmed_requested: String = requested_outfit.strip_edges()
	var char_data = _character_data.get(character_id, null)
	if char_data == null:
		return trimmed_requested
	return AVGCharacterClass.resolve_outfit_name(char_data, trimmed_requested)


func _build_outfit_emotion_key(outfit: String, emotion: String) -> String:
	var trimmed_outfit: String = outfit.strip_edges()
	var trimmed_emotion: String = emotion.strip_edges()
	if trimmed_outfit.is_empty() or trimmed_emotion.is_empty():
		return ""
	return "%s__%s" % [trimmed_outfit, trimmed_emotion]


func _parse_position(pos_str: String) -> Vector2:
	if POSITIONS.has(pos_str):
		return POSITIONS[pos_str]
	if "," in pos_str:
		var parts: PackedStringArray = pos_str.split(",")
		if parts.size() >= 2:
			var x: float = parts[0].strip_edges().to_float()
			var y: float = parts[1].strip_edges().to_float()
			return Vector2(x, y)
	return POSITIONS.get("center", Vector2(0.5, 0.5))


func _position_sprite(sprite: TextureRect, pos_ratio: Vector2, character_id: String = "") -> void:
	sprite.position = _calculate_position(pos_ratio, sprite, character_id)


func _calculate_position(pos_ratio: Vector2, sprite: TextureRect, character_id: String = "") -> Vector2:
	# Position directly in design-resolution space; the parent container handles scaling.
	var sprite_size: Vector2 = sprite.size if sprite.size != Vector2.ZERO else Vector2(200, 400)
	var x: float = _design_resolution.x * pos_ratio.x - sprite_size.x / 2.0
	var y: float = _design_resolution.y * pos_ratio.y - sprite_size.y / 2.0
	# Apply character-level display_offset compensation (normalized → pixels)
	var offset: Vector2 = _get_char_display_offset(character_id)
	x += offset.x * _design_resolution.x
	y += offset.y * _design_resolution.y
	return Vector2(x, y)


func _apply_texture_size(sprite: TextureRect, texture: Texture2D, character_id: String = "") -> void:
	if texture == null:
		return
	var tex_size: Vector2 = texture.get_size()
	if tex_size.x <= 0 or tex_size.y <= 0:
		return
	# Fit sprite height to the design resolution and derive width from aspect ratio.
	var aspect: float = tex_size.x / tex_size.y
	var h: float = _design_resolution.y
	var w: float = h * aspect
	# Apply character-level display_scale compensation
	var ds: float = _get_char_display_scale(character_id)
	sprite.size = Vector2(w * ds, h * ds)


func _cancel_tween(character_id: String) -> void:
	if _active_tweens.has(character_id):
		var tween: Tween = _active_tweens[character_id]
		if tween != null and tween.is_valid():
			tween.kill()
		_active_tweens.erase(character_id)


func _get_crossfade_tween_key(character_id: String) -> String:
	return character_id + "_crossfade"


func _get_visibility_tween_key(character_id: String) -> String:
	return character_id + "_fade"


func _resolve_transition_mode(transition_str: String) -> int:
	match transition_str:
		"crossfade":
			return TRANSITION_CROSSFADE
		"instant":
			return TRANSITION_INSTANT
		"fade_through_black":
			return TRANSITION_FADE_THROUGH_BLACK
		_:
			if _dialog_settings != null and "default_expression_transition" in _dialog_settings:
				return _dialog_settings.default_expression_transition
			return TRANSITION_CROSSFADE


func _get_default_expression_duration() -> float:
	if _dialog_settings != null and "default_expression_duration" in _dialog_settings:
		return _dialog_settings.default_expression_duration
	return 0.2


func _configure_tweener(tweener: PropertyTweener, easing_str: String, transition_override: Variant = null) -> PropertyTweener:
	var transition_type: Tween.TransitionType = _resolve_transition_type(easing_str)
	if transition_override != null:
		transition_type = int(transition_override) as Tween.TransitionType
	tweener.set_trans(transition_type)
	tweener.set_ease(_resolve_ease_type(easing_str))
	return tweener


func _resolve_transition_type(easing_str: String) -> Tween.TransitionType:
	match easing_str:
		"linear":
			return Tween.TRANS_LINEAR
		_:
			return Tween.TRANS_QUAD


func _resolve_ease_type(easing_str: String) -> Tween.EaseType:
	match easing_str:
		"ease_in":
			return Tween.EASE_IN
		"ease_out":
			return Tween.EASE_OUT
		"linear":
			return Tween.EASE_IN_OUT
		_:
			return Tween.EASE_IN_OUT


const _ALL_KNOWN_EFFECTS: Array[String] = [
	"fade", "none", "instant", "pop_in", "pop_out",
	"slide_from_left", "slide_from_right", "slide_from_top", "slide_from_bottom",
	"slide_to_left", "slide_to_right", "slide_to_top", "slide_to_bottom",
]

func _normalize_visibility_effect(effect_name: String) -> String:
	var normalized: String = effect_name.strip_edges().to_lower()
	if normalized.is_empty():
		return VISIBILITY_EFFECT_FADE
	if normalized == "instant":
		return VISIBILITY_EFFECT_NONE
	if not _ALL_KNOWN_EFFECTS.has(normalized):
		push_warning("CharacterDisplay: unknown effect '%s', falling back to fade" % effect_name)
	return normalized


func _get_visibility_effect_offset(effect_name: String, distance: float) -> Vector2:
	var clamped_distance: float = maxf(distance, 0.0)
	match effect_name:
		"slide_from_left", "slide_to_left":
			return Vector2(-_design_resolution.x * clamped_distance, 0.0)
		"slide_from_right", "slide_to_right":
			return Vector2(_design_resolution.x * clamped_distance, 0.0)
		"slide_from_top", "slide_to_top":
			return Vector2(0.0, -_design_resolution.y * clamped_distance)
		"slide_from_bottom", "slide_to_bottom":
			return Vector2(0.0, _design_resolution.y * clamped_distance)
		_:
			return Vector2.ZERO


func _get_intensity_multiplier(intensity: String) -> float:
	match intensity:
		"small":
			return 0.5
		"large":
			return 1.5
		_:
			return 1.0


## Get character-level display_offset from character data
func _get_char_display_offset(character_id: String) -> Vector2:
	character_id = _resolve_character_reference(character_id)
	if character_id.is_empty() or not _character_data.has(character_id):
		return Vector2.ZERO
	var data = _character_data[character_id]
	if data is Resource:
		return data.display_offset if "display_offset" in data else Vector2.ZERO
	elif data is Dictionary:
		var val = data.get("display_offset", Vector2.ZERO)
		if val is Vector2:
			return val
	return Vector2.ZERO


## Get character-level display_scale from character data
func _get_char_display_scale(character_id: String) -> float:
	character_id = _resolve_character_reference(character_id)
	if character_id.is_empty() or not _character_data.has(character_id):
		return 1.0
	var data = _character_data[character_id]
	if data is Resource:
		return data.display_scale if "display_scale" in data else 1.0
	elif data is Dictionary:
		var val = data.get("display_scale", 1.0)
		if val is float or val is int:
			return float(val)
	return 1.0


# =============================================================================
# Save / Restore
# =============================================================================

## Get the state of all visible characters for save data
func get_all_character_states() -> Dictionary:
	var result: Dictionary = {}
	for character_id in _active_characters:
		var sprite: TextureRect = _active_characters[character_id]
		if not is_instance_valid(sprite) or not sprite.visible:
			continue
		var state: Dictionary = _character_state.get(character_id, {})
		result[character_id] = state.duplicate()
	return result


## 获取角色的镜头焦点坐标（归一化 0~1），基于精灵实际渲染位置
## face_offset: 相对精灵尺寸的偏移，默认向上 20%（接近面部区域）
func get_character_focus_point(character_id: String, face_offset: Vector2 = Vector2(0.0, -0.2)) -> Vector2:
	var resolved_id: String = _resolve_character_reference(character_id)
	var sprite: TextureRect = _active_characters.get(resolved_id, null)
	if sprite == null or not is_instance_valid(sprite) or not sprite.visible:
		# 回退到 position_ratio
		var state: Dictionary = _character_state.get(resolved_id, {})
		return state.get("position_ratio", Vector2(0.5, 0.5))
	# 精灵中心（设计分辨率空间）+ 面部偏移
	var center: Vector2 = sprite.position + sprite.size / 2.0
	center += face_offset * sprite.size
	# 转为归一化坐标
	if _design_resolution.x > 0 and _design_resolution.y > 0:
		return center / _design_resolution
	return Vector2(0.5, 0.5)


## 获取所有可见角色的镜头焦点坐标中点（归一化 0~1）
func get_between_focus_point() -> Vector2:
	var points: Array[Vector2] = []
	for character_id in _active_characters:
		var sprite: TextureRect = _active_characters[character_id]
		if not is_instance_valid(sprite) or not sprite.visible:
			continue
		# between 场景不加面部偏移，取精灵实际中心
		var center: Vector2 = sprite.position + sprite.size / 2.0
		if _design_resolution.x > 0 and _design_resolution.y > 0:
			points.append(center / _design_resolution)
	if points.is_empty():
		return Vector2(0.5, 0.5)
	var sum: Vector2 = Vector2.ZERO
	for p in points:
		sum += p
	return sum / float(points.size())


## Restore all characters from save data after clearing current ones
func restore_all_characters(states: Dictionary) -> void:
	hide_all(0.0)
	for character_id in states:
		var state: Dictionary = states[character_id]
		var pos_ratio_raw = state.get("position_ratio", [0.5, 0.5])
		var pos_ratio: Vector2
		if pos_ratio_raw is Array:
			pos_ratio = Vector2(pos_ratio_raw[0], pos_ratio_raw[1])
		elif pos_ratio_raw is Vector2:
			pos_ratio = pos_ratio_raw
		else:
			pos_ratio = Vector2(0.5, 0.5)
		var emotion: String = state.get("current_emotion", "")
		var outfit: String = state.get("current_outfit", "")
		var flip: bool = state.get("flip", false)
		var char_scale: float = state.get("scale_factor", 1.0)
		var opacity: float = state.get("opacity", 1.0)
		# Convert position_ratio back into the serialized position string.
		var pos_str: String = "%f,%f" % [pos_ratio.x, pos_ratio.y]
		show_character(character_id, pos_str, emotion, 0.0, flip, char_scale, opacity, outfit)
