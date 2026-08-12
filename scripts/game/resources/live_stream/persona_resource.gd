class_name StreamPersonaResource extends StreamContentResource
## 一张人设卡就是一套完整直播账号：频道身份、皮套、休息画面与声音配置共同切换。
## 人设正文存放在 prompts/live_stream/personas/*.md；继承的 prompt_fragment 仅保存 PromptManager 模板引用。

@export var model: StreamerModelResource = null

@export_group("Channel Identity")
@export var channel_name: String = ""
@export var channel_avatar: Texture2D = null
@export var resting_background: Texture2D = null

@export_group("Speech")
## 直播字幕逐字显示时使用的角色说话音效。每个人设可配置自己的 WAV 音色。
@export var speech_blip: AudioStreamWAV = null
@export_range(-40.0, 6.0, 0.5) var speech_blip_volume_db: float = -15.0
@export_range(0.0, 0.3, 0.01) var speech_blip_pitch_variation: float = 0.06
@export_range(1, 4, 1) var speech_blip_character_interval: int = 2

@export_group("")
## 保留字段：基础表现倍率。暂不参与玩法结算，仅留作后续设计的占位。
@export_range(0.0, 2.0, 0.05) var base_performance_multiplier: float = 1.0
## 保留字段：熟练度初始值。暂不参与玩法结算，仅留作后续设计的占位。
@export_range(0.0, 100.0, 1.0) var initial_proficiency: float = 0.0
## 保留字段：固化度初始值。暂不参与玩法结算，仅留作后续设计的占位。
@export_range(0.0, 100.0, 1.0) var initial_fixation: float = 0.0


func is_valid() -> bool:
	return (
		is_valid_base()
		and model != null
		and model.is_valid()
		and not channel_name.strip_edges().is_empty()
		and channel_avatar != null
		and resting_background != null
		and base_performance_multiplier > 0.0
	)
