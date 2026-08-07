class_name MaterialSponsorTerms extends Resource
## 商单素材的保底收益与满意度门槛。

@export_range(0, 1000000, 1) var guaranteed_money: int = 0
@export_range(-100.0, 100.0, 0.5) var quality_floor: float = 0.0
@export_range(0.0, 1.0, 0.05) var failure_payout_multiplier: float = 0.5


func is_valid() -> bool:
	return guaranteed_money > 0 and failure_payout_multiplier >= 0.0 and failure_payout_multiplier <= 1.0
