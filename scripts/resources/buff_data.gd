extends Resource
class_name BuffData
## Buff数据资源 — 定义一个Buff的属性和效果
##
## 与 RelicData 共享 EffectType 枚举，二者本质都是"被动效果"，
## 区别在于: 遗物是永久持有的，Buff 可以有持续时间 / 层数限制。
## 扩展方式: 新增 EffectType 枚举值 + 在 RogueBuffManager 中添加对应处理逻辑

## Buff效果类型 — 复用 RelicData.EffectType 以保持统一
const EffectType = RelicData.EffectType

## Buff稀有度 — 复用 RelicData.Rarity
const Rarity = RelicData.Rarity

## Buff唯一ID
@export var id: StringName = &""
## Buff显示名称
@export var display_name: String = ""
## Buff描述
@export var description: String = ""
## Buff图标
@export var icon: Texture2D = preload("res://assets/image/relics/akabeko.png")
## Buff稀有度
@export var rarity: RelicData.Rarity = RelicData.Rarity.COMMON

@export_group("效果参数")
## 主效果类型
@export var effect_type: RelicData.EffectType = RelicData.EffectType.NONE
## 浮点参数 (用于倍率类效果)
@export var param_float: float = 0.0
## 整数参数 (用于固定数值类效果)
@export var param_int: int = 0
## 附加标签
@export var tags: PackedStringArray = []

@export_group("持续性")
## 是否永久 (true = 整个run期间有效, false = 有持续回合/时间)
@export var permanent: bool = true
## 持续回合数 (-1 = 永久, 仅 permanent=false 时有效)
@export var duration_rounds: int = -1
## 可叠加层数上限 (-1 = 无限)
@export var max_stacks: int = 1
