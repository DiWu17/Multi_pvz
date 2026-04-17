extends Resource
class_name RogueEventData
## 肉鸽随机事件数据 — 一个完整事件的定义
##
## 用法: 在 res://resources/events/ 下创建 .tres 文件
## EventRoom 启动时从事件池中随机抽取一个 RogueEventData 展示给玩家

## 事件唯一 ID
@export var id: StringName = &""
## 事件标题
@export var title: String = ""
## 事件描述 (支持 BBCode)
@export_multiline var description: String = ""
## 事件背景图片 (可选, 为空时使用默认背景)
@export var background_image: Texture2D
## 事件图标 (可选, 用于地图节点预览等)
@export var event_icon: Texture2D

@export_group("选项")
## 选项列表 (至少1个, 通常2~4个)
@export var options: Array[RogueEventOption] = []

@export_group("条件")
## 最低楼层 (0 = 不限)
@export var min_floor: int = 0
## 最高楼层 (-1 = 不限)
@export var max_floor: int = -1
## 需要拥有的遗物 ID 列表 (全部满足才出现, 空 = 无条件)
@export var required_relics: PackedStringArray = []
## 排除的遗物 ID 列表 (拥有任一则不出现)
@export var excluded_relics: PackedStringArray = []
## 权重 (在事件池中被选中的相对概率, 默认 10)
@export var weight: int = 10
## 单次 run 最多出现次数 (-1 = 不限)
@export var max_occurrences: int = 1
