extends Resource
class_name RogueEventOption
## 事件选项 — 一个可选择的按钮 + 对应的效果列表
##
## 每个效果用 RogueEffectEntry 描述：类型 + 参数。
## 事件触发时由 EventRoom 按顺序执行所有效果。

## 选项显示文本
@export var label: String = ""
## 选项描述/提示
@export var description: String = ""
## 选项图标 (可选)
@export var icon: Texture2D

@export_group("效果列表")
## 选择此选项后依次执行的效果
@export var effects: Array[RogueEffectEntry] = []
