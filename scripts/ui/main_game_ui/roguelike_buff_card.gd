extends PanelContainer
class_name RoguelikeBuffCard
## 肉鸽Buff卡牌，用于关卡间选择增益效果

signal card_selected(card: RoguelikeBuffCard)

## Buff 数据结构
## {
##   "id": String,          # 唯一标识
##   "name": String,        # 显示名称
##   "description": String, # 描述文本
##   "icon": Texture2D,     # 图标(可选)
##   "rarity": int,         # 稀有度 0=普通 1=稀有 2=史诗
## }
var buff_data: Dictionary = {}

@onready var _icon: TextureRect = %Icon
@onready var _name_label: Label = %NameLabel
@onready var _desc_label: Label = %DescLabel
@onready var _rarity_bar: ColorRect = %RarityBar

const RARITY_COLORS := {
	0: Color(0.6, 0.8, 0.6),   # 普通 - 绿色
	1: Color(0.5, 0.4, 0.9),   # 稀有 - 紫色
	2: Color(1.0, 0.7, 0.2),   # 史诗 - 金色
}

func setup(data: Dictionary) -> void:
	buff_data = data
	if not is_node_ready():
		await ready
	_name_label.text = data.get("name", "未知Buff")
	_desc_label.text = data.get("description", "")
	var icon_tex = data.get("icon", null)
	if icon_tex is Texture2D:
		_icon.texture = icon_tex
		_icon.visible = true
	else:
		_icon.visible = false
	var rarity: int = data.get("rarity", 0)
	_rarity_bar.color = RARITY_COLORS.get(rarity, RARITY_COLORS[0])

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		card_selected.emit(self)

func play_hover_anim() -> void:
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.05, 1.05), 0.1)

func play_unhover_anim() -> void:
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.1)

func _on_mouse_entered() -> void:
	play_hover_anim()

func _on_mouse_exited() -> void:
	play_unhover_anim()
