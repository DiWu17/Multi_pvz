extends Control
class_name BuffSelection

## 战斗奖励选择 — 从资源池 + 卡组奖励中随机抽取，玩家选择若干个
## 资源池: res://resources/relics/ 和 res://resources/buff/ 下的 .tres 文件
## 卡组奖励: 硬编码的植物卡 / 金币奖励 (不属于 buff/relic 系统)

signal selection_completed

const BUFF_CARD_SCENE: PackedScene = preload("res://scenes/ui/roguelike_buff_card.tscn")

## How many the player can pick
var max_picks: int = 2
var _picks_remaining: int = 0
var _card_container: HBoxContainer

## 奖励池 — 每个条目是 Dictionary，包含 display 信息 + 执行回调
## 格式: {"id", "name", "description", "rarity", "_type": "relic"|"buff"|"deck", "_resource"?: Resource, "_deck_action"?: Callable}
var _reward_pool: Array = []

## 卡组奖励 (非资源型，硬编码)
const DECK_REWARDS: Array = [
	{"id": "extra_pea", "name": "额外豌豆", "description": "获得2张豌豆射手", "rarity": 0,
		"_type": "deck", "_plant": "P001PeaShooterSingle", "_count": 2},
	{"id": "extra_sunflower", "name": "向日葵补给", "description": "获得2张向日葵", "rarity": 0,
		"_type": "deck", "_plant": "P002SunFlower", "_count": 2},
	{"id": "wall_nut_supply", "name": "坚果补给", "description": "获得1张坚果墙", "rarity": 0,
		"_type": "deck", "_plant": "P004WallNut", "_count": 1},
	{"id": "potato_supply", "name": "土豆地雷补给", "description": "获得1张土豆地雷", "rarity": 0,
		"_type": "deck", "_plant": "P005PotatoMine", "_count": 1},
	{"id": "gold_bonus", "name": "金币奖励", "description": "获得20金币", "rarity": 1,
		"_type": "deck", "_gold": 20},
	{"id": "deck_expand", "name": "卡组扩充", "description": "获得3张随机植物", "rarity": 2,
		"_type": "deck", "_random_plants": 3},
]

const RARITY_MAP := {
	RelicData.Rarity.COMMON: 0,
	RelicData.Rarity.RARE: 1,
	RelicData.Rarity.EPIC: 2,
	RelicData.Rarity.LEGENDARY: 2,
}

func _ready() -> void:
	# Setup UI structure
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(vbox)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 20)

	var title := Label.new()
	title.text = "选择奖励 (剩余 %d 次)" % _picks_remaining
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.name = "TitleLabel"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	vbox.add_child(title)

	var center := CenterContainer.new()
	vbox.add_child(center)

	_card_container = HBoxContainer.new()
	_card_container.add_theme_constant_override("separation", 20)
	center.add_child(_card_container)

	var skip_btn := Button.new()
	skip_btn.text = "跳过"
	skip_btn.pressed.connect(_on_skip)
	skip_btn.custom_minimum_size = Vector2(120, 40)
	var skip_center := CenterContainer.new()
	skip_center.add_child(skip_btn)
	vbox.add_child(skip_center)

	_build_reward_pool()
	_show_rewards()

func setup(picks: int) -> void:
	max_picks = picks
	_picks_remaining = picks

## 构建奖励池: 扫描资源文件 + 加入卡组奖励
func _build_reward_pool() -> void:
	_reward_pool.clear()

	# 扫描遗物资源
	for path in _scan_tres("res://resources/relics/"):
		var relic: RelicData = load(path)
		if relic and not RogueBuffManager.has_relic(relic.id):
			_reward_pool.append({
				"id": relic.id, "name": relic.display_name,
				"description": relic.description,
				"icon": relic.icon,
				"rarity": RARITY_MAP.get(relic.rarity, 0),
				"_type": "relic", "_resource_path": path,
			})

	# 扫描 buff 资源
	for path in _scan_tres("res://resources/buff/"):
		var buff: BuffData = load(path)
		if buff and not RogueBuffManager.has_buff(buff.id):
			_reward_pool.append({
				"id": buff.id, "name": buff.display_name,
				"description": buff.description,
				"icon": buff.icon,
				"rarity": RARITY_MAP.get(buff.rarity, 0),
				"_type": "buff", "_resource_path": path,
			})

	# 加入卡组奖励
	_reward_pool.append_array(DECK_REWARDS)

func _show_rewards() -> void:
	var pool := _reward_pool.duplicate()
	pool.shuffle()
	var show_count := mini(4, pool.size())
	for i in range(show_count):
		var card: RoguelikeBuffCard = BUFF_CARD_SCENE.instantiate()
		_card_container.add_child(card)
		card.setup(pool[i])
		card.card_selected.connect(_on_card_selected)

func _on_card_selected(card: RoguelikeBuffCard) -> void:
	_apply_reward(card.buff_data)
	card.queue_free()
	_picks_remaining -= 1
	var title_label = find_child("TitleLabel")
	if title_label:
		title_label.text = "选择奖励 (剩余 %d 次)" % _picks_remaining
	if _picks_remaining <= 0:
		_finish()

func _apply_reward(data: Dictionary) -> void:
	var reward_type: String = data.get("_type", "")
	match reward_type:
		"relic":
			var relic: RelicData = load(data["_resource_path"])
			if relic:
				RogueBuffManager.add_relic(relic)
		"buff":
			var buff: BuffData = load(data["_resource_path"])
			if buff:
				RogueBuffManager.add_buff(buff)
		"deck":
			_apply_deck_reward(data)

func _apply_deck_reward(data: Dictionary) -> void:
	if data.has("_plant"):
		var plant_name: String = data["_plant"]
		if CharacterRegistry.PlantType.has(plant_name):
			var plant_type = CharacterRegistry.PlantType[plant_name]
			RogueState.add_plant(plant_type, data.get("_count", 1))
	if data.has("_gold"):
		RogueState.add_gold(data["_gold"])
	if data.has("_random_plants"):
		var plant_pool = [
			CharacterRegistry.PlantType.P001PeaShooterSingle,
			CharacterRegistry.PlantType.P002SunFlower,
			CharacterRegistry.PlantType.P004WallNut,
			CharacterRegistry.PlantType.P005PotatoMine,
		]
		for j in range(data["_random_plants"]):
			RogueState.add_plant(plant_pool[randi() % plant_pool.size()])

## 扫描目录下所有 .tres 文件路径
func _scan_tres(dir_path: String) -> Array[String]:
	var paths: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return paths
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".tres"):
			paths.append(dir_path + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	return paths

func _on_skip() -> void:
	_finish()

func _finish() -> void:
	selection_completed.emit()
	queue_free()
