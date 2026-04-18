extends Control
class_name EnchantTargetSelection

## 附魔目标选择界面
## - 展示背包中所有卡牌实例（不堆叠，每张单独显示）
## - 支持筛选接口（filter_func），方便后续扩展
## - 支持选择数量参数（max_picks），默认1
## - 选择后对指定卡牌实例 UID 施加附魔

signal selection_completed(selected_uids: Array)

const CARD_ITEM_SCENE: PackedScene = preload("res://scenes/rogue/enchant_card_item.tscn")

## 要施加的附魔
var enchant: BuffData
## 最大选择数量
var max_picks: int = 1
## 筛选函数: func(card_instance: Dictionary) -> bool
## card_instance 格式: {uid: int, plant_type: PlantType, enchants: Array[BuffData]}
## 默认不筛选（全部可选）
var filter_func: Callable = Callable()

var _selected_uids: Array[int] = []
## uid -> Control (卡牌 UI 节点)
var _card_nodes: Dictionary = {}

@onready var _card_container: GridContainer = %CardContainer
@onready var _title_label: Label = %TitleLabel
@onready var _enchant_info_label: Label = %EnchantInfoLabel
@onready var _confirm_btn: Button = %ConfirmButton
@onready var _cancel_btn: Button = %CancelButton

func setup(p_enchant: BuffData, p_max_picks: int = 1, p_filter: Callable = Callable()) -> void:
	enchant = p_enchant
	max_picks = p_max_picks
	filter_func = p_filter

func _ready() -> void:
	_confirm_btn.pressed.connect(_on_confirm)
	_cancel_btn.pressed.connect(_on_cancel)
	if enchant:
		_enchant_info_label.text = "附魔: %s — %s" % [enchant.display_name, enchant.description]
	else:
		_enchant_info_label.text = "选择要附魔的卡牌"
	_populate_cards()
	_update_title()

func _populate_cards() -> void:
	var instances := RogueState.get_all_card_instances()

	for inst in instances:
		## 应用筛选
		if filter_func.is_valid() and not filter_func.call(inst):
			continue

		var uid: int = inst["uid"]
		var plant_type = inst["plant_type"]
		var enchants: Array = inst["enchants"]

		## 从场景实例化卡牌容器
		var card_panel: PanelContainer = CARD_ITEM_SCENE.instantiate()

		var card_slot: CenterContainer = card_panel.get_node("%CardSlot")
		var enchant_label: Label = card_panel.get_node("%EnchantLabel")
		var uid_label: Label = card_panel.get_node("%UidLabel")

		## 从 AllCards 获取卡牌模板并复制用于展示
		if AllCards.all_plant_card_prefabs.has(plant_type):
			var card_template: Card = AllCards.all_plant_card_prefabs[plant_type]
			var card_display = card_template.duplicate()
			card_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card_display.set_process(false)
			card_display.set_process_input(false)
			card_slot.add_child(card_display)
		else:
			var placeholder := Label.new()
			placeholder.text = str(plant_type)
			placeholder.add_theme_font_size_override("font_size", 10)
			card_slot.add_child(placeholder)

		## 显示附魔标签
		if not enchants.is_empty():
			var enchant_names := []
			for e in enchants:
				enchant_names.append(e.display_name)
			enchant_label.text = ", ".join(enchant_names)
			enchant_label.visible = true

		## UID 标识
		uid_label.text = "#%d" % uid

		## 选择高亮边框
		var style_normal := StyleBoxFlat.new()
		style_normal.bg_color = Color(0.15, 0.15, 0.15, 0.8)
		style_normal.border_color = Color(0.3, 0.3, 0.3)
		style_normal.set_border_width_all(2)
		style_normal.set_corner_radius_all(4)

		var style_selected := StyleBoxFlat.new()
		style_selected.bg_color = Color(0.2, 0.25, 0.15, 0.9)
		style_selected.border_color = Color(1.0, 0.85, 0.2)
		style_selected.set_border_width_all(3)
		style_selected.set_corner_radius_all(4)

		card_panel.add_theme_stylebox_override("panel", style_normal)
		card_panel.set_meta("style_normal", style_normal)
		card_panel.set_meta("style_selected", style_selected)
		card_panel.set_meta("card_uid", uid)

		card_panel.gui_input.connect(_on_card_gui_input.bind(card_panel, uid))

		_card_container.add_child(card_panel)
		_card_nodes[uid] = card_panel

func _on_card_gui_input(event: InputEvent, card_panel: PanelContainer, uid: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_card(card_panel, uid)

func _toggle_card(card_panel: PanelContainer, uid: int) -> void:
	if uid in _selected_uids:
		## 取消选择
		_selected_uids.erase(uid)
		card_panel.add_theme_stylebox_override("panel", card_panel.get_meta("style_normal"))
	else:
		## 选择
		if _selected_uids.size() >= max_picks:
			## 已达上限，替换最早选择的
			var old_uid: int = _selected_uids.pop_front()
			if _card_nodes.has(old_uid):
				_card_nodes[old_uid].add_theme_stylebox_override("panel", _card_nodes[old_uid].get_meta("style_normal"))
		_selected_uids.append(uid)
		card_panel.add_theme_stylebox_override("panel", card_panel.get_meta("style_selected"))

	_update_title()
	_confirm_btn.disabled = _selected_uids.is_empty()

func _update_title() -> void:
	if _title_label:
		_title_label.text = "选择卡牌 (%d/%d)" % [_selected_uids.size(), max_picks]

func _on_confirm() -> void:
	## 为选中的卡牌实例施加附魔
	for uid in _selected_uids:
		RogueBuffManager.add_instance_enchant(uid, enchant)
	selection_completed.emit(_selected_uids)
	queue_free()

func _on_cancel() -> void:
	selection_completed.emit([])
	queue_free()
