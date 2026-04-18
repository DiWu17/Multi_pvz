extends Resource
class_name BuffData
## 卡牌附魔数据资源 — 定义一个可以附加在卡牌上的附魔效果
##
## 附魔是绑定在特定植物卡牌上的特殊效果，在该卡牌被放置时生效。
## 示例:
##   - 南瓜灯: 放下后自带南瓜灯保护
##   - 固有: 该卡牌必定第一个出现在传送带上
##   - 消耗: 放置后不再出现在本局后续循环中
##
## 与 RelicData 的区别: 遗物是全局被动效果，附魔是绑定到特定卡牌上的效果。

## 附魔效果类型
enum EnchantType {
	NONE = 0,
	## 南瓜灯: 放置后自动套上南瓜灯
	PUMPKIN,
	## 固有: 必定第一个出现在传送带上
	INHERENT,
	## 消耗: 放置后不再出现在本局后续循环中
	CONSUMABLE,
}

## 附魔稀有度
enum Rarity {
	COMMON = 0,   ## 普通
	RARE = 1,     ## 稀有
	EPIC = 2,     ## 史诗
	LEGENDARY = 3 ## 传说
}

## 附魔唯一ID
@export var id: StringName = &""
## 附魔显示名称
@export var display_name: String = ""
## 附魔描述
@export var description: String = ""
## 附魔图标
@export var icon: Texture2D = preload("res://assets/image/relics/akabeko.png")
## 附魔稀有度
@export var rarity: Rarity = Rarity.COMMON

@export_group("效果参数")
## 附魔效果类型
@export var enchant_type: EnchantType = EnchantType.NONE
## 浮点参数 (用于倍率类效果)
@export var param_float: float = 0.0
## 整数参数 (用于固定数值类效果)
@export var param_int: int = 0
## 附加标签
@export var tags: PackedStringArray = []
