class_name CardDisplayMetrics
extends RefCounted
## 直播卡牌统一真实尺寸。显示尺寸由 Control.size 决定，scale 只属于交互动画。

const FULL_SIZE: Vector2 = Vector2(440, 600)
const HAND_SIZE: Vector2 = Vector2(440, 600)
const PREVIEW_SIZE: Vector2 = Vector2(440, 600)


static func hand_size() -> Vector2:
	return HAND_SIZE


static func preview_size() -> Vector2:
	return PREVIEW_SIZE
