extends Resource
class_name RogueEffectEntry
## 单个效果条目 — 描述一个选项触发的具体效果
##
## 由 RogueEventOption 的 effects 数组引用。
## 扩展方式: 在 EffectType 中新增枚举值，在 EventRoom._execute_effect() 中添加处理。

## 效果类型枚举
enum EffectType {
	NONE = 0,
	## 添加遗物 (resource_path 指向 .tres)
	ADD_RELIC,
	## [已废弃] 旧 Buff 已迁移为遗物，等同于 ADD_RELIC
	ADD_BUFF,
	## 添加金币 (param_int = 数量, 可为负)
	ADD_GOLD,
	## 添加初始阳光 (param_int = 数量)
	ADD_STARTING_SUN,
	## 添加植物卡 (param_string = PlantType 枚举名, param_int = 数量)
	ADD_PLANT,
	## 移除植物卡 (param_string = PlantType 枚举名, param_int = 数量)
	REMOVE_PLANT,
	## 随机添加植物卡 (param_int = 数量)
	ADD_RANDOM_PLANT,
	## 添加随机遗物 (param_int = 数量)
	ADD_RANDOM_RELIC,
	## [已废弃] 等同于 ADD_RANDOM_RELIC
	ADD_RANDOM_BUFF,
	## 概率分支: 以 param_float 的概率执行 success 效果组, 否则执行 fail 效果组
	CHANCE,
	## 自定义脚本 (param_string = 方法名, 由 EventRoom 调用)
	CUSTOM,
	## 为随机卡牌添加随机附魔 (param_int = 数量)
	ADD_RANDOM_ENCHANT,
	## 弹出附魔目标选择界面 (target_resource_path 指向 BuffData .tres, param_int = 最大选择数量)
	ADD_ENCHANT_PICK_TARGET,
}

## 效果类型
@export var type: EffectType = EffectType.NONE
## 整数参数 (金币数量 / 植物数量 / 阳光数量等)
@export var param_int: int = 0
## 浮点参数 (概率值等, 0.0~1.0)
@export var param_float: float = 0.0
## 字符串参数 (PlantType 枚举名 / 自定义方法名等)
@export var param_string: String = ""
## 目标资源路径 (指向 RelicData / BuffData 的 .tres)
@export var target_resource_path: String = ""
## CHANCE 类型: 成功时执行的子效果 (元素为 RogueEffectEntry)
@export var sub_effects_success: Array[Resource] = []
## CHANCE 类型: 失败时执行的子效果 (元素为 RogueEffectEntry)
@export var sub_effects_fail: Array[Resource] = []
