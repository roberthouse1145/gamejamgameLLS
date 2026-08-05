class_name StreamerCharacter extends Resource
## 游戏角色静态定义：身份、称呼、LLM 人物卡、显示引用。
## 关系数值（好感/信任/依赖）属于运行时状态，存于 GameState，此处只放初值。

const ROLE_HEROINE: String = "heroine"
const ROLE_CHILDHOOD_FRIEND: String = "childhood_friend"
const ROLE_TOP_FAN: String = "top_fan"
const ROLE_ONLINE_FRIEND: String = "online_friend"
const ROLE_CLOSE_FRIEND: String = "close_friend"

## 稳定标识，GameState 关系字典的 key
@export var character_key: String = ""
## 私聊软件中的显示名；它可以是真名、昵称或游戏 ID，不等同于公开艺名。
@export var chat_display_name: String = ""
@export var display_name: String = ""
## 功能位，取值见 ROLE_* 常量
@export var role: String = ROLE_HEROINE
## 此角色私下对女主的称呼（如鸢鸢叫"柚柚"），无则留空
@export var address_to_heroine: String = ""
## 观众中唯一具名例外（鹿铃），其余粉丝只是向量与氛围
@export var is_named_fan: bool = false
## LLM 人物卡片段，作为状态快照的一部分注入
@export_multiline var persona_prompt: String = ""
## AVG 演出显示引用（立绘/表情/服装），可为空
@export var avg_character: AVGCharacter = null
## 桌面应用使用的独立头像资产，不从完整立绘运行时裁切。
@export var avatar: Texture2D = null

@export var initial_favor: int = 0
@export var initial_trust: int = 0
@export var initial_dependence: int = 0
