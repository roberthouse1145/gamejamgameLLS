class_name CharacterProfile extends Resource
## 游戏角色静态资料：稳定身份、称呼、人物设定与各应用资料。
## 关系、好友状态和已发布内容属于运行时状态，不写回本资源。

const ROLE_HEROINE: String = "heroine"
const ROLE_CHILDHOOD_FRIEND: String = "childhood_friend"
const ROLE_TOP_FAN: String = "top_fan"
const ROLE_ONLINE_FRIEND: String = "online_friend"
const ROLE_CLOSE_FRIEND: String = "close_friend"

## 稳定角色 ID，也是 GameState 关系字典与各应用关联角色的 key。
@export var character_id: String = ""
@export var display_name: String = ""
## 功能位，取值见 ROLE_* 常量。
@export var role: String = ROLE_HEROINE
## 此角色私下对女主的称呼，无则留空。
@export var address_to_heroine: String = ""
## 观众中唯一具名例外，其余粉丝只是向量与氛围。
@export var is_named_fan: bool = false
## 是否允许作为约会外出对象。默认关闭，避免仅因有角色资料就进入候选列表。
@export var datable: bool = false
@export_range(-50, 50, 1) var base_date_acceptance_modifier: int = 0
## LLM 人物卡片段，作为状态快照的一部分注入。
@export_multiline var persona_prompt: String = ""
## AVG 演出显示引用，可为空。
@export var avg_character: AVGCharacter = null
## LinkChat 账号、头像与该角色拥有的预制动态内容；无账号时为空。
@export var linkchat_profile: LinkChatProfile = null
## 公开社交平台账号；同一角色可以拥有主播身份和个人身份等多个账号。
@export var social_accounts: Array[SocialAccountProfile] = []

@export var initial_favor: int = 0
@export var initial_trust: int = 0
@export var initial_dependence: int = 0


func get_social_account(account_id: String) -> SocialAccountProfile:
	var normalized_id: String = account_id.strip_edges()
	for account: SocialAccountProfile in social_accounts:
		if account != null and account.account_id == normalized_id:
			return account
	return null
