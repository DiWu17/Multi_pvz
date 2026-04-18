extends Control
class_name ShopRoom

## 肉鸽商店房间 — 复用主线商店视觉素材 (车厢后备箱 + 招牌)
## 金币从 RogueState.gold 读取，购买效果通过 RogueBuffManager / RogueState 执行

signal room_completed()

# ── 场景节点引用 ──
@onready var background: TextureRect = $Background
@onready var continue_button: TextureButton = $ContinueButton
@onready var gold_label: Label = $GoldLabel
@onready var items_container: GridContainer = $Background/Car/ItemsContainer
@onready var confirm_panel: Control = $ConfirmPanel
@onready var confirm_label: Label = $ConfirmPanel/Dialog/MarginContainer/ConfirmLabel
@onready var yes_button: Button = $ConfirmPanel/Dialog/HBoxContainer/YesButton
@onready var no_button: Button = $ConfirmPanel/Dialog/HBoxContainer/NoButton

## 价格标签贴图 (用于动态创建商品)
const PRICE_TAG_TEX := preload("res://assets/image/store/Store_PriceTag.png")
const GOODS_ITEM_SCENE: PackedScene = preload("res://scenes/rogue/shop_goods_item.tscn")
## 新的商品显示场景
const GOODS_DISPLAY_SCENE: PackedScene = preload("res://scenes/rogue/shop_goods_display.tscn")

## 可购买的植物池 - 包含所有可用植物
const PLANT_POOL: Array = [
	CharacterRegistry.PlantType.P001PeaShooterSingle,
	CharacterRegistry.PlantType.P002SunFlower,
	CharacterRegistry.PlantType.P003CherryBomb,
	CharacterRegistry.PlantType.P004WallNut,
	CharacterRegistry.PlantType.P005PotatoMine,
	CharacterRegistry.PlantType.P006SnowPea,
	CharacterRegistry.PlantType.P007Chomper,
	CharacterRegistry.PlantType.P008PeaShooterDouble,
	CharacterRegistry.PlantType.P009PuffShroom,
	CharacterRegistry.PlantType.P010SunShroom,
	CharacterRegistry.PlantType.P011FumeShroom,
	CharacterRegistry.PlantType.P012GraveBuster,
	CharacterRegistry.PlantType.P013HypnoShroom,
	CharacterRegistry.PlantType.P014ScaredyShroom,
	CharacterRegistry.PlantType.P015IceShroom,
	CharacterRegistry.PlantType.P016DoomShroom,
	CharacterRegistry.PlantType.P017LilyPad,
	CharacterRegistry.PlantType.P018Squash,
	CharacterRegistry.PlantType.P019ThreePeater,
	CharacterRegistry.PlantType.P020TangleKelp,
	CharacterRegistry.PlantType.P021Jalapeno,
	CharacterRegistry.PlantType.P022Caltrop,
	CharacterRegistry.PlantType.P023TorchWood,
	CharacterRegistry.PlantType.P024TallNut,
	CharacterRegistry.PlantType.P025SeaShroom,
	CharacterRegistry.PlantType.P026Plantern,
	CharacterRegistry.PlantType.P027Cactus,
	CharacterRegistry.PlantType.P028Blover,
	CharacterRegistry.PlantType.P029SplitPea,
	CharacterRegistry.PlantType.P030StarFruit,
	CharacterRegistry.PlantType.P031Pumpkin,
	CharacterRegistry.PlantType.P032MagnetShroom,
	CharacterRegistry.PlantType.P033CabbagePult,
	CharacterRegistry.PlantType.P034FlowerPot,
	CharacterRegistry.PlantType.P035CornPult,
	CharacterRegistry.PlantType.P036CoffeeBean,
	CharacterRegistry.PlantType.P037Garlic,
	CharacterRegistry.PlantType.P038UmbrellaLeaf,
	CharacterRegistry.PlantType.P039MariGold,
	CharacterRegistry.PlantType.P040MelonPult,
	CharacterRegistry.PlantType.P041GatlingPea,
	CharacterRegistry.PlantType.P042TwinSunFlower,
	CharacterRegistry.PlantType.P043GloomShroom,
	CharacterRegistry.PlantType.P044Cattail,
	CharacterRegistry.PlantType.P045WinterMelon,
	CharacterRegistry.PlantType.P046GoldMagnet,
	CharacterRegistry.PlantType.P047SpikeRock,
	CharacterRegistry.PlantType.P048CobCannon,
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

	# 添加3个随机植物
	var plant_pool_copy: Array = PLANT_POOL.duplicate()
	plant_pool_copy.shuffle()
	for i in range(min(3, plant_pool_copy.size())):
		var plant_type = plant_pool_copy[i]
		var plant_info = CharacterRegistry.PlantInfo.get(plant_type, {})
		var plant_name = plant_info.get(CharacterRegistry.PlantInfoAttribute.PlantName, "未知植物")
		var plant_goods_display: Control = GOODS_DISPLAY_SCENE.instantiate()
		plant_goods_display.buy_pressed.connect(_on_goods_buy_pressed)
		items_container.add_child(plant_goods_display)
		_goods_data[plant_goods_display] = {
			"type": "plant",
			"plant_type": plant_type,
			"name": plant_name,
			"cost": 40
		}
		# 异步初始化，不需要等待
		plant_goods_display.init_plant(plant_type, plant_name, 40)
	
	# 添加3个随机遗物
	var relic_paths := _scan_relics()
	relic_paths.shuffle()
	var relic_count := 0
	for i in range(relic_paths.size()):
		if relic_count >= 3:
			break
		var relic: RelicData = load(relic_paths[i])
		if relic and not RogueBuffManager.has_relic(relic.id):
			var relic_goods_display: Control = GOODS_DISPLAY_SCENE.instantiate()
			relic_goods_display.buy_pressed.connect(_on_goods_buy_pressed)
			items_container.add_child(relic_goods_display)
			_goods_data[relic_goods_display] = {
				"type": "relic",
				"relic": relic,
				"name": relic.display_name,
				"cost": 100
			}
			# 异步初始化，不需要等待
			relic_goods_display.init_relic(relic, 100)
			relic_count += 1
	
	# 添加铲子服务
	var shovel_goods_display: Control = GOODS_DISPLAY_SCENE.instantiate()
	shovel_goods_display.buy_pressed.connect(_on_goods_buy_pressed)
	items_container.add_child(shovel_goods_display)
	_goods_data[shovel_goods_display] = {
		"type": "remove",
		"name": "铲除植物",
		"cost": 5
	}
	# 异步初始化，不需要等待
	shovel_goods_display.init_shovel(5)

## 当商品被购买时的处理
func _on_goods_buy_pressed(item: Dictionary) -> void:
	if item.is_empty():
		return
	_pending_item = item
	# 从_goods_data中查找对应的goods_node
	var goods_node = null
	for node in _goods_data:
		if _goods_data[node] == item:
			goods_node = node
			break
	_pending_goods_node = goods_node
	confirm_label.text = "是否花费 $%d 购买\n「%s」？" % [item["cost"], item["name"]]
	confirm_panel.visible = true

# ══════════════════════════════════════════
#  购买确认流程
# ══════════════════════════════════════════



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

	# 标记已售并执行购买
	if goods_node and goods_node.has_method("mark_sold"):
		var result = _execute_purchase(item)
		goods_node.mark_sold(result)

	_update_gold_display()
	_refresh_button_states()

# ══════════════════════════════════════════
#  购买效果执行
# ══════════════════════════════════════════

func _execute_purchase(item: Dictionary) -> String:
	match item["type"]:
		"plant":
			var plant_type = item["plant_type"]
			RogueState.add_plant(plant_type)
			return "已购买"
		"relic":
			if "relic" in item:
				var relic: RelicData = item["relic"]
				if not RogueBuffManager.has_relic(relic.id):
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
		if goods_node and goods_node.has_method("update_button_state"):
			goods_node.update_button_state()

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
