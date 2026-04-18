extends Control
class_name ShopGoodsDisplay

## 商品数据
var item_data: Dictionary = {}

@onready var icon_area: Control = %IconArea
@onready var card_display: Control = %CardDisplay
@onready var card_bg_rect: TextureRect = %CardBg
@onready var character_static: Node2D = %CharacterStatic
@onready var name_label: Label = %NameLabel
@onready var sold_label: Label = %SoldLabel
@onready var buy_button: Button = %BuyButton
@onready var price_label: Label = %PriceLabel

const CARD_BG_NORM   = preload("res://resources/card_bg/01Norm.tres")
const CARD_BG_PURPLE = preload("res://resources/card_bg/02Purple.tres")

signal buy_pressed(data: Dictionary)

func _ready() -> void:
	buy_button.pressed.connect(_on_buy_pressed)

## 初始化商品显示 - 植物类型
func init_plant(plant_type: CharacterRegistry.PlantType, plant_name: String, cost: int) -> void:
	item_data = {
		"type": "plant",
		"plant_type": plant_type,
		"name": plant_name,
		"cost": cost
	}
	
	# 使用延迟调用确保 _ready 已执行
	await get_tree().process_frame
	name_label.text = plant_name
	price_label.text = "$%d" % cost
	buy_button.disabled = RogueState.gold < cost
	
	_display_plant_card(plant_type)

## 初始化商品显示 - 遗物类型
func init_relic(relic: RelicData, cost: int) -> void:
	item_data = {
		"type": "relic",
		"relic": relic,
		"name": relic.display_name,
		"cost": cost
	}
	
	# 使用延迟调用确保 _ready 已执行
	await get_tree().process_frame
	name_label.text = relic.display_name
	price_label.text = "$%d" % cost
	buy_button.disabled = RogueState.gold < cost
	
	_display_relic_icon(relic)

## 初始化商品显示 - 铲子类型
func init_shovel(cost: int) -> void:
	item_data = {
		"type": "remove",
		"name": "铲除植物",
		"cost": cost
	}
	
	# 使用延迟调用确保 _ready 已执行
	await get_tree().process_frame
	name_label.text = "铲除植物"
	price_label.text = "$%d" % cost
	buy_button.disabled = RogueState.gold < cost
	
	_display_shovel()

## 显示植物卡牌（参考 card.tscn 结构：CardBg + CharacterStatic）
func _display_plant_card(plant_type: CharacterRegistry.PlantType) -> void:
	# 获取植物信息
	var plant_info = CharacterRegistry.PlantInfo.get(plant_type, {})
	if plant_info.is_empty():
		_add_default_background()
		return
	
	# 根据是否为紫卡选择卡片背景，与 card_base.gd 逻辑一致
	var plant_condition = Global.character_registry.get_plant_info(
			plant_type, CharacterRegistry.PlantInfoAttribute.PlantConditionResource)
	var is_purple: bool = plant_condition != null and plant_condition.is_purple_card
	card_bg_rect.texture = CARD_BG_PURPLE if is_purple else CARD_BG_NORM
	
	# 清空 CharacterStatic 下之前一个现展示的 sprite
	for child in character_static.get_children():
		child.queue_free()
	
	# 展示卡片区，隐藏其他显示区
	card_display.visible = true
	icon_area.visible = false
	
	# 从 AllCards 预制卡片中 duplicate CharacterStatic（与 hm_character.gd 方式一致）
	var prefab_card: Card = AllCards.all_plant_card_prefabs.get(plant_type, null)
	if prefab_card and is_instance_valid(prefab_card.character_static):
		var cloned := prefab_card.character_static.duplicate()
		# 原版卡片 50x70，我们的面板 90x115，缩放比取较小值保持比例
		cloned.scale = Vector2(1.64, 1.64)
		cloned.position = Vector2.ZERO
		character_static.add_child(cloned)
		return
	
	# duplicate 失败时仅保留卡片背景（无 sprite）

## 显示遗物icon
func _display_relic_icon(relic: RelicData) -> void:
	for child in icon_area.get_children():
		child.queue_free()
	card_display.visible = false
	icon_area.visible = true
	
	if relic.icon:
		var icon_rect := TextureRect.new()
		icon_rect.texture = relic.icon
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_rect.anchor_right = 1.0
		icon_rect.anchor_bottom = 1.0
		icon_area.add_child(icon_rect)
	else:
		_add_default_background()

## 显示锹子
func _display_shovel() -> void:
	for child in icon_area.get_children():
		child.queue_free()
	card_display.visible = false
	icon_area.visible = true
	
	var shovel_tex = preload("res://assets/image/ui/ui_card/Shovel_hi_res.png") as Texture2D
	if shovel_tex:
		var shovel_rect := TextureRect.new()
		shovel_rect.texture = shovel_tex
		shovel_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shovel_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		shovel_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shovel_rect.anchor_right = 1.0
		shovel_rect.anchor_bottom = 1.0
		icon_area.add_child(shovel_rect)
	else:
		_add_default_background()

## 添加默认背景（当无法加载具体内容时）
func _add_default_background() -> void:
	card_display.visible = false
	icon_area.visible = true
	var color_rect := ColorRect.new()
	color_rect.color = Color(0.3, 0.3, 0.3, 0.8)
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	color_rect.anchor_right = 1.0
	color_rect.anchor_bottom = 1.0
	icon_area.add_child(color_rect)

## 更新按钮状态（当金币数量改变时）
func update_button_state() -> void:
	if item_data.is_empty():
		return
	buy_button.disabled = RogueState.gold < item_data["cost"]

## 标记为已售出
func mark_sold(status_text: String = "") -> void:
	buy_button.disabled = true
	sold_label.visible = true
	if status_text:
		sold_label.text = status_text

func _on_buy_pressed() -> void:
	if item_data.is_empty():
		return
	buy_pressed.emit(item_data)
