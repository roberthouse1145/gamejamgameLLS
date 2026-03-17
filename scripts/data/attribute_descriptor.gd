class_name AttributeDescriptor


## 属性描述字典：{属性名: {等级: 描述文本}}
const DESCRIPTIONS: Dictionary = {
	"strength": {
		1: "体力极弱，几乎无法进行体力活动",
		2: "体力较差，轻微运动就会气喘吁吁",
		3: "体力偏弱，能应付日常活动但容易疲劳",
		4: "体力一般，能进行普通的体力劳动",
		5: "体力中等，具备基本的战斗体能",
		6: "体力良好，能持续进行中等强度的战斗",
		7: "体力优秀，在战斗中展现出明显的力量优势",
		8: "体力强悍，能轻松搬动重物并在激烈战斗中保持持久",
		9: "体力惊人，拥有远超常人的怪力",
		10: "拥有超人般的力量，可以轻松举起汽车",
	},
	"agility": {
		1: "行动迟缓笨拙，反应极慢",
		2: "动作不够灵活，经常磕磕绊绊",
		3: "身手偏慢，能完成基本的闪避动作",
		4: "身手一般，反应速度处于普通水平",
		5: "身手中等，能在战斗中做出合理的闪避",
		6: "身手敏捷，移动和反应都比较迅速",
		7: "身手矫健，能在复杂地形中灵活穿梭",
		8: "身手出众，动作快如闪电令人难以捕捉",
		9: "身手超凡，能轻松躲避高速攻击",
		10: "拥有闪电般的速度和反应，几乎不可能被击中",
	},
	"charisma": {
		1: "性格极度内向，几乎无法与人交流",
		2: "不善社交，在人群中显得格格不入",
		3: "社交能力偏弱，只能进行简单的对话",
		4: "社交能力一般，能维持基本的人际关系",
		5: "具备一定的亲和力，能与大多数人友好相处",
		6: "性格开朗有魅力，容易获得他人好感",
		7: "极具个人魅力，能自然地成为人群焦点",
		8: "魅力出众，言行举止都散发着感染力",
		9: "拥有令人倾倒的气场，能轻易说服和鼓舞他人",
		10: "天生的领袖气质，万众瞩目的存在，一言一行都能影响周围所有人",
	},
	"intelligence": {
		1: "思维混乱，几乎无法理解简单的指令",
		2: "理解力较差，处理问题时经常出错",
		3: "智力偏低，能理解基本概念但分析能力不足",
		4: "智力一般，能处理日常事务和简单推理",
		5: "智力中等，具备基本的分析和判断能力",
		6: "头脑聪明，能快速理解复杂情况并做出判断",
		7: "智力出众，善于分析局势并制定策略",
		8: "才智过人，能在瞬间看透事物本质",
		9: "拥有天才级的智慧，思维缜密洞察力极强",
		10: "超凡的智慧，能预判复杂局势的发展并制定完美策略",
	},
	"willpower": {
		1: "意志极度薄弱，遇到困难立刻放弃",
		2: "意志力较差，容易被恐惧和压力击垮",
		3: "意志力偏弱，在逆境中难以坚持",
		4: "意志力一般，能承受普通程度的压力",
		5: "意志力中等，面对困难时能保持基本的冷静",
		6: "意志坚定，在压力下仍能保持清醒判断",
		7: "意志顽强，即使身处险境也不轻言放弃",
		8: "钢铁般的意志，能抵抗强大的精神攻击和诱惑",
		9: "意志力惊人，在绝望的境地中依然能找到希望",
		10: "不可动摇的意志，任何困难和恐惧都无法使其屈服",
	},
}


## 获取指定属性和等级的描述文本
static func get_attribute_prompt(attribute_name: String, level: int) -> String:
	if not DESCRIPTIONS.has(attribute_name):
		return ""
	var levels: Dictionary = DESCRIPTIONS[attribute_name]
	if not levels.has(level):
		return ""
	return levels[level]


## 获取少女所有属性的描述文本
static func get_all_attributes_prompt(girl_data: MagicalGirlData) -> String:
	var parts: Array[String] = []
	var attributes: Dictionary = {
		"strength": girl_data.strength,
		"agility": girl_data.agility,
		"charisma": girl_data.charisma,
		"intelligence": girl_data.intelligence,
		"willpower": girl_data.willpower,
	}
	for attr_name: String in attributes:
		var level: int = attributes[attr_name]
		var desc: String = get_attribute_prompt(attr_name, level)
		if desc.length() > 0:
			parts.append("【%s】%s" % [_get_attribute_display_name(attr_name), desc])
	return "\n".join(parts)


## 获取属性的中文显示名称
static func _get_attribute_display_name(attribute_name: String) -> String:
	match attribute_name:
		"strength": return "力量"
		"agility": return "灵敏"
		"charisma": return "魅力"
		"intelligence": return "智力"
		"willpower": return "意志"
		_: return attribute_name
