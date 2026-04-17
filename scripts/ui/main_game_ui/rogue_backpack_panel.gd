extends PanelContainer
class_name RogueBackpackPanel
"""
肉鸽背包面板：不暂停游戏，显示当前 Buff、遗物、植物卡组
按下背包按钮切换显示/隐藏
"""

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
	_refresh_buffs()
	_refresh_relics()
	_refresh_deck()

#region Buff
func _refresh_buffs() -> void:
	for child in buff_container.get_children():
		child.queue_free()

	var buffs := RogueBuffManager.get_buffs()
	if buffs.is_empty():
		var lbl := Label.new()
		lbl.text = "暂无Buff"
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		buff_container.add_child(lbl)
		return

	for buff in buffs:
		var item := _create_item_card(buff.display_name, buff.description, buff.icon)
		buff_container.add_child(item)
#endregion

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

	if RogueState.deck.is_empty():
		var lbl := Label.new()
		lbl.text = "卡组为空"
		lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		deck_container.add_child(lbl)
		return

	for plant_type in RogueState.deck:
		var count: int = RogueState.deck[plant_type]
		var plant_name: String = Global.character_registry.get_plant_info(
			plant_type, CharacterRegistry.PlantInfoAttribute.PlantName
		)
		var item := _create_item_card(plant_name, "x%d" % count)
		deck_container.add_child(item)
#endregion

## 创建一个小展示卡片（图标 + 名称 + 描述）
func _create_item_card(title: String, desc: String, tex: Texture2D = null) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(90, 60)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.85)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	if tex:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(32, 32)
		vbox.add_child(icon)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title_label)

	var desc_label := Label.new()
	desc_label.text = desc
	desc_label.add_theme_font_size_override("font_size", 9)
	desc_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_label)

	return panel
