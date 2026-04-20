extends PanelContainer
class_name RogueBackpackPanel
"""
肉鸽背包面板：不暂停游戏，显示当前 Buff、遗物、植物卡组
按下背包按钮切换显示/隐藏
"""

const ITEM_CARD_SCENE: PackedScene = preload("res://scenes/ui/rogue_backpack_item.tscn")
const ENCHANT_CARD_ITEM_SCENE: PackedScene = preload("res://scenes/rogue/enchant_card_item.tscn")

@onready var buff_container: HBoxContainer = $MarginContainer/VBoxContainer/BuffSection/BuffScrollContainer/BuffContainer
@onready var relic_container: HBoxContainer = $MarginContainer/VBoxContainer/RelicSection/RelicScrollContainer/RelicContainer
@onready var deck_container: HBoxContainer = $MarginContainer/VBoxContainer/DeckSection/DeckScrollContainer/DeckContainer
@onready var close_button: Button = $MarginContainer/VBoxContainer/Header/CloseButton

func _ready() -> void:
	visible = false
	close_button.pressed.connect(_on_close)

func toggle() -> void:
	if visible:
		hide()
	else:
		_refresh()
		show()

func _on_close() -> void:
	hide()

func _refresh() -> void:
	_refresh_relics()
	_refresh_deck()

#region Relic
func _refresh_relics() -> void:
	for child in relic_container.get_children():
		child.queue_free()

	var rels := RogueBuffManager.get_relics()
	if rels.is_empty():
		var lbl := Label.new()
		lbl.text = "暂无遗物"
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		relic_container.add_child(lbl)
		return

	for relic in rels:
		var item := _create_item_card(relic.display_name, relic.description, relic.icon)
		relic_container.add_child(item)
#endregion

#region Deck
func _refresh_deck() -> void:
	for child in deck_container.get_children():
		child.queue_free()

	var instances := RogueState.get_all_card_instances()
	if instances.is_empty():
		var lbl := Label.new()
		lbl.text = "卡组为空"
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		deck_container.add_child(lbl)
		return

	for inst in instances:
		var plant_type = inst["plant_type"]
		var enchants: Array = inst["enchants"]
		var uid: int = inst["uid"]

		var card_panel: PanelContainer = ENCHANT_CARD_ITEM_SCENE.instantiate()
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

		## 显示附魔标签
		if not enchants.is_empty():
			var enchant_names := []
			for e in enchants:
				enchant_names.append(e.display_name)
			enchant_label.text = ", ".join(enchant_names)
			enchant_label.visible = true

		uid_label.text = "#%d" % uid
		deck_container.add_child(card_panel)
#endregion

## 创建一个小展示卡片（图标 + 名称 + 描述）
func _create_item_card(title: String, desc: String, tex: Texture2D = null) -> PanelContainer:
	var panel: PanelContainer = ITEM_CARD_SCENE.instantiate()

	var icon: TextureRect = panel.get_node("%Icon")
	var title_label: Label = panel.get_node("%TitleLabel")
	var desc_label: Label = panel.get_node("%DescLabel")

	title_label.text = title
	desc_label.text = desc

	if tex:
		icon.texture = tex
		icon.visible = true

	return panel
