extends Resource
class_name RelicData
## 遗物数据资源 — 定义一个遗物的属性和效果
##
## 使用方式: 在 res://resources/relics/ 下创建 .tres 文件，选择此脚本类型
## 扩展方式: 新增 EffectType 枚举值 + 在 RogueBuffManager 中添加对应处理逻辑

## 遗物效果类型 — 每新增一种机制只需加一个枚举值
enum EffectType {
	NONE = 0,
	## 阳光产出倍率 (param_float = 加成比例, 如 0.2 表示 +20%)
	SUN_PRODUCTION_MULTIPLIER,
	## 植物攻击力倍率 (param_float = 加成比例, 如 0.1 表示 +10%)
	ATTACK_MULTIPLIER,
	## 击杀敌人获得阳光 (param_int = 阳光数量)
	SUN_ON_KILL,
	## 初始阳光加成 (param_int = 加成值)
	STARTING_SUN_BONUS,
	## 自然阳光产出速率倍率 (param_float = 加成比例)
	SKY_SUN_RATE_MULTIPLIER,
	## 自动拾取阳光
	AUTO_COLLECT_SUN,
	## 僵尸血量倍率 (param_float = 倍率, 如 0.8 表示 80% 血量, 1.5 表示 150%)
	ZOMBIE_HP_MULTIPLIER,
	## 僵尸攻击倍率 (param_float = 倍率)
	ZOMBIE_ATK_MULTIPLIER,
}

## 遗物稀有度
enum Rarity {
	COMMON = 0,   ## 普通
	RARE = 1,     ## 稀有
	EPIC = 2,     ## 史诗
	LEGENDARY = 3 ## 传说
}

## 遗物唯一ID (用于查重 / 序列化)
@export var id: StringName = &""
## 遗物显示名称
@export var display_name: String = ""
## 遗物描述
@export var description: String = ""
## 遗物图标
@export var icon: Texture2D = preload("res://assets/image/relics/akabeko.png")
## 遗物稀有度
@export var rarity: Rarity = Rarity.COMMON
## 是否可叠加 (同一遗物能否拥有多个)
@export var stackable: bool = false

@export_group("效果参数")
## 主效果类型
@export var effect_type: EffectType = EffectType.NONE
## 浮点参数 (用于倍率类效果)
@export var param_float: float = 0.0
## 整数参数 (用于固定数值类效果)
@export var param_int: int = 0
## 附加标签 (供自定义逻辑使用, 如指定特定植物类型等)
@export var tags: PackedStringArray = []
