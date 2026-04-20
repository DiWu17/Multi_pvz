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
	## 移除随机植物卡 (param_int = 数量)
	REMOVE_RANDOM_PLANT,
	## 添加随机遗物 (param_int = 数量)
	ADD_RANDOM_RELIC,
	## 概率分支: 以 param_float 的概率执行 success 效果组, 否则执行 fail 效果组
	CHANCE,
	## 自定义脚本 (param_string = 方法名, 由 EventRoom 调用)
	CUSTOM,
	## 为随机卡牌添加随机附魔 (param_int = 数量)
	ADD_RANDOM_ENCHANT,
	## 弹出附魔目标选择界面 (target_resource_path 指向 BuffData .tres, param_int = 最大选择数量)
	ADD_ENCHANT_PICK_TARGET,
	## 显示下一组选项，支持链式事件 (sub_options 存储下一步选项)
	NEXT_OPTIONS,
	## 显示"继续"按钮，结束当前步骤
	CONTINUE,

}

## 效果类型
@export var type: EffectType = EffectType.NONE
## 整数参数 (金币数量 / 植物数量 / 阳光数量等)
@export var param_int: int = 0
## 浮点参数 (概率值等, 0.0~1.0)
@export var param_float: float = 0.0
## 字符串参数 (PlantType 枚举名 / 自定义方法名等)
@export var param_range: int = 0
## 范围参数 (取随机值的范围)
@export var param_string: String = ""
## 目标资源路径 (指向 RelicData / BuffData 的 .tres)
@export var target_resource_path: String = ""
## CHANCE 类型: 成功时执行的子效果 (元素为 RogueEffectEntry)
@export var sub_effects_success: Array[Resource] = []
## CHANCE 类型: 失败时执行的子效果 (元素为 RogueEffectEntry)
@export var sub_effects_fail: Array[Resource] = []
@export var plant_pool: Array[CharacterRegistry.PlantType] = [] # 供 ADD_RANDOM_PLANT 使用的植物池
@export var relic_pool: Array[String] = [] # 供 ADD_RANDOM_RELIC 使用的遗物资源路径池
@export var enchant_pool: Array[String] = [] # 供 ADD_RANDOM_ENCHANT 使用的附魔资源路径池

@export_group("链式选项字段 (NEXT_OPTIONS 使用)")
## NEXT_OPTIONS 类型: 下一步的选项集合
@export var sub_options: Array[RogueEventOption] = [] # 元素为 RogueEventOption
## NEXT_OPTIONS 类型: 是否更新标题 (空字符串则保持原标题)
@export var title_update: String = ""
## NEXT_OPTIONS 类型: 是否更新描述 (空字符串则保持原描述)
@export var description_update: String = ""
