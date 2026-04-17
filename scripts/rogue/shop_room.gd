extends Control
class_name ShopRoom

## 肉鸽商店房间 — 复用主线商店视觉素材 (车厢后备箱 + 招牌)
## 金币从 RogueState.gold 读取，购买效果通过 RogueBuffManager / RogueState 执行

signal room_completed()

# ── 场景节点引用 ──
@onready var background: TextureRect = $Background
@onready var continue_button: TextureButton = $ContinueButton
@onready var gold_label: Label = $GoldLabel
@onready var items_container: HBoxContainer = $Background/Car/ItemsContainer
@onready var confirm_panel: Control = $ConfirmPanel
@onready var confirm_label: Label = $ConfirmPanel/Dialog/MarginContainer/ConfirmLabel
@onready var yes_button: Button = $ConfirmPanel/Dialog/HBoxContainer/YesButton
@onready var no_button: Button = $ConfirmPanel/Dialog/HBoxContainer/NoButton

## 价格标签贴图 (用于动态创建商品)
const PRICE_TAG_TEX := preload("res://assets/image/store/Store_PriceTag.png")

## 商店物品模板
const SHOP_ITEMS: Array = [
	{"name": "随机植物卡", "cost": 40, "type": "plant", "icon_color": Color(0.4, 0.8, 0.3)},
	{"name": "植物升级券", "cost": 55, "type": "upgrade", "icon_color": Color(0.3, 0.6, 0.9)},
	{"name": "随机遗物", "cost": 100, "type": "relic", "icon_color": Color(0.9, 0.7, 0.2)},
	{"name": "铲除植物", "cost": 5, "type": "remove", "icon_color": Color(0.8, 0.3, 0.3)},
]

## 可购买的植物池
const PLANT_POOL: Array = [
	CharacterRegistry.PlantType.P001PeaShooterSingle,
	CharacterRegistry.PlantType.P002SunFlower,
	CharacterRegistry.PlantType.P004WallNut,
	CharacterRegistry.PlantType.P005PotatoMine,
]

## 当前待确认的商品和按钮
var _pending_item: Dictionary = {}
var _pending_goods_node: Control = null
## 每个商品节点绑定的数据 {Node: Dictionary}
var _goods_data: Dictionary = {}

# ══════════════════════════════════════════
#  生命周期
# ══════════════════════════════════════════

func _ready() -> void:
	continue_button.pressed.connect(_on_continue_pressed)
	yes_button.pressed.connect(_on_confirm_yes)
	no_button.pressed.connect(_on_confirm_no)
	confirm_panel.visible = false

	_update_gold_display()
	_populate_shop()

# ══════════════════════════════════════════
#  商品栏生成 — 模仿原版商店 goods 样式
# ══════════════════════════════════════════

func _populate_shop() -> void:
	if items_container == null:
		return
	for child in items_container.get_children():
		child.queue_free()
	_goods_data.clear()

	var available: Array = SHOP_ITEMS.duplicate()
	available.shuffle()
	var count: int = mini(available.size(), randi_range(3, 4))

	for i in range(count):
		var item: Dictionary = available[i]
		var goods_node := _create_goods_node(item)
		items_container.add_child(goods_node)
		_goods_data[goods_node] = item

## 创建单个商品节点 — 复用原版 goods 的视觉结构
func _create_goods_node(item: Dictionary) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(80, 120)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(vbox)

	# 商品图标区域 (彩色方块占位，带商品名)
	var icon_panel := Panel.new()
	icon_panel.custom_minimum_size = Vector2(67, 68)
	vbox.add_child(icon_panel)

	var icon_color := ColorRect.new()
	icon_color.color = item.get("icon_color", Color(0.5, 0.5, 0.5))
	icon_color.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_panel.add_child(icon_color)

	var name_label := Label.new()
	name_label.text = item["name"]
	name_label.set_anchors_preset(Control.PRESET_CENTER)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 2)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_panel.add_child(name_label)

	# 卖光标签 (初始隐藏)
	var sold_label := Label.new()
	sold_label.name = "SoldLabel"
	sold_label.text = "卖光了"
	sold_label.visible = false
	sold_label.set_anchors_preset(Control.PRESET_CENTER)
	sold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sold_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	sold_label.add_theme_font_size_override("font_size", 18)
	sold_label.add_theme_color_override("font_color", Color(1, 0, 0))
	sold_label.add_theme_color_override("font_outline_color", Color.BLACK)
	sold_label.add_theme_constant_override("outline_size", 2)
	sold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_panel.add_child(sold_label)

	# 点击按钮 (覆盖在图标上)
	var btn := Button.new()
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.disabled = RogueState.gold < item["cost"]
	btn.pressed.connect(_on_goods_pressed.bind(root))
	btn.name = "BuyButton"
	icon_panel.add_child(btn)

	# 价格标签
	var price_tag := TextureRect.new()
	price_tag.texture = PRICE_TAG_TEX
	price_tag.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(price_tag)

	var price_label := Label.new()
	price_label.text = "$%d" % item["cost"]
	price_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_tag.add_child(price_label)

	# 鼠标悬停动画
	root.mouse_entered.connect(func(): _goods_hover(root, true))
	root.mouse_exited.connect(func(): _goods_hover(root, false))

	return root

func _goods_hover(node: Control, entered: bool) -> void:
	var tween := node.create_tween()
	if entered:
		tween.tween_property(node, "scale", Vector2(1.08, 1.08), 0.1)
	else:
		tween.tween_property(node, "scale", Vector2.ONE, 0.1)

# ══════════════════════════════════════════
#  购买确认流程
# ══════════════════════════════════════════

func _on_goods_pressed(goods_node: Control) -> void:
	var item: Dictionary = _goods_data.get(goods_node, {})
	if item.is_empty():
		return
	_pending_item = item
	_pending_goods_node = goods_node
	confirm_label.text = "是否花费 $%d 购买\n「%s」？" % [item["cost"], item["name"]]
	confirm_panel.visible = true

func _on_confirm_yes() -> void:
	confirm_panel.visible = false
	if _pending_item.is_empty() or _pending_goods_node == null:
		return
	_do_purchase(_pending_item, _pending_goods_node)
	_pending_item = {}
	_pending_goods_node = null

func _on_confirm_no() -> void:
	confirm_panel.visible = false
	_pending_item = {}
	_pending_goods_node = null

func _do_purchase(item: Dictionary, goods_node: Control) -> void:
	var cost: int = item["cost"]
	if not RogueState.spend_gold(cost):
		return

	# 标记已售
	var btn: Button = goods_node.find_child("BuyButton")
	if btn:
		btn.disabled = true
	var sold_label: Label = goods_node.find_child("SoldLabel")
	if sold_label:
		sold_label.visible = true
		sold_label.text = _execute_purchase(item)

	_update_gold_display()
	_refresh_button_states()

# ══════════════════════════════════════════
#  购买效果执行
# ══════════════════════════════════════════

func _execute_purchase(item: Dictionary) -> String:
	match item["type"]:
		"plant":
			var plant_type = PLANT_POOL[randi() % PLANT_POOL.size()]
			RogueState.add_plant(plant_type)
			return "已购买"
		"upgrade":
			var owned_types: Array = RogueState.deck.keys()
			if owned_types.is_empty():
				return "卡组为空"
			var upgrade_type = owned_types[randi() % owned_types.size()]
			RogueState.add_plant(upgrade_type)
			return "已购买"
		"relic":
			var relic_paths := _scan_relics()
			relic_paths.shuffle()
			for path in relic_paths:
				var relic: RelicData = load(path)
				if relic and not RogueBuffManager.has_relic(relic.id):
					RogueBuffManager.add_relic(relic)
					return relic.display_name
			return "无可用遗物"
		"remove":
			var owned_types: Array = RogueState.deck.keys()
			if owned_types.is_empty():
				return "卡组为空"
			var remove_type = owned_types[randi() % owned_types.size()]
			RogueState.consume_plant(remove_type)
			return "已移除"
	return "已购买"

# ══════════════════════════════════════════
#  UI 更新
# ══════════════════════════════════════════

func _update_gold_display() -> void:
	if gold_label:
		gold_label.text = "金币: %d" % RogueState.gold

func _refresh_button_states() -> void:
	for goods_node in _goods_data:
		if not is_instance_valid(goods_node):
			continue
		var item: Dictionary = _goods_data[goods_node]
		var btn: Button = goods_node.find_child("BuyButton")
		if btn and not goods_node.find_child("SoldLabel").visible:
			btn.disabled = RogueState.gold < item["cost"]

# ══════════════════════════════════════════
#  工具方法
# ══════════════════════════════════════════

func _scan_relics() -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open("res://resources/relics/")
	if dir == null:
		return paths
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			paths.append("res://resources/relics/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return paths

func _on_continue_pressed() -> void:
	room_completed.emit()
