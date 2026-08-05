class_name ScheduleActivityAnimation extends Control
## 女主日程活动贴纸动画。
## 日程系统只需切换 Activity，不需要了解纹理路径或 AnimationPlayer 动画名。

enum Activity {
	SLEEP,
	WORK,
	GAME,
	SHOPPING,
}

const ACTIVITY_TEXTURES: Array = [
	preload("res://Assets/images/schedule/ruan_yunyou/sleep_v2.png"),
	preload("res://Assets/images/schedule/ruan_yunyou/work_v2.png"),
	preload("res://Assets/images/schedule/ruan_yunyou/game_v2.png"),
	preload("res://Assets/images/schedule/ruan_yunyou/shopping_v2.png"),
]
const ACTIVITY_SCENE_TEXTURES: Array = [
	preload("res://Assets/images/schedule/ruan_yunyou/backgrounds/sleep_v2.png"),
	preload("res://Assets/images/schedule/ruan_yunyou/backgrounds/work_v2.png"),
	preload("res://Assets/images/schedule/ruan_yunyou/backgrounds/game_v2.png"),
	preload("res://Assets/images/schedule/ruan_yunyou/backgrounds/shopping_v2.png"),
]
const ACTIVITY_ANIMATIONS: PackedStringArray = ["sleep", "work", "game", "shopping"]

@export var activity: Activity = Activity.SLEEP:
	set(value):
		activity = value
		if is_node_ready():
			_apply_activity()

@onready var scene_sticker: TextureRect = %SceneSticker
@onready var sticker: TextureRect = %Sticker
@onready var animation_player: AnimationPlayer = %AnimationPlayer


func _ready() -> void:
	_apply_activity()


func play_activity(value: Activity) -> void:
	activity = value


func play_activity_by_name(activity_name: String) -> bool:
	match activity_name.strip_edges().to_lower():
		"sleep":
			play_activity(Activity.SLEEP)
		"work":
			play_activity(Activity.WORK)
		"game":
			play_activity(Activity.GAME)
		"shopping":
			play_activity(Activity.SHOPPING)
		_:
			return false
	return true


func set_activity_paused(paused: bool) -> void:
	if paused:
		animation_player.pause()
	elif not animation_player.is_playing():
		var index: int = clampi(int(activity), 0, ACTIVITY_ANIMATIONS.size() - 1)
		animation_player.play(ACTIVITY_ANIMATIONS[index])


func _apply_activity() -> void:
	var index: int = clampi(int(activity), 0, ACTIVITY_TEXTURES.size() - 1)
	scene_sticker.texture = ACTIVITY_SCENE_TEXTURES[index] as Texture2D
	sticker.texture = ACTIVITY_TEXTURES[index] as Texture2D
	animation_player.play(ACTIVITY_ANIMATIONS[index])
