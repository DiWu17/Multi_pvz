extends Node

# Signals
signal deck_changed
signal gold_changed
signal run_started
signal run_ended

# --- Deck Manager ---
# The deck is a Dictionary[CharacterRegistry.PlantType, int] mapping plant type to stock count.
# Initial deck (set in start_run): {P002SunFlower: 3, P001PeaShooterSingle: 5, P005PotatoMine: 1, P004WallNut: 1}
var deck: Dictionary = {}  # CharacterRegistry.PlantType -> int (stock count)
var starting_sun: int = 50

# --- Gold ---
var gold: int = 0

# --- Buff / Relic 已迁移至 RogueBuffManager (基于 Resource 的系统) ---
# 以下属性保留为兼容桥接，实际数据由 RogueBuffManager 管理
var active_buffs: Array:
	get: return _buffs_to_dicts(RogueBuffManager.get_buffs())
var relics: Array:
	get: return _relics_to_dicts(RogueBuffManager.get_relics())

static func _buffs_to_dicts(buffs: Array[BuffData]) -> Array:
	var result: Array = []
	for b in buffs:
		result.append({"id": b.id, "name": b.display_name, "description": b.description})
	return result

static func _relics_to_dicts(rels: Array[RelicData]) -> Array:
	var result: Array = []
	for r in rels:
		result.append({"id": r.id, "name": r.display_name, "description": r.description})
	return result

# --- Run State ---
var is_run_active: bool = false
var current_floor: int = 0  # tracks which map row the player is on
var battles_won: int = 0
var pending_battle_config: Dictionary = {}  # stored by BattleRoom before launching, used by RogueMap on return

# --- Map State (跨场景切换持久化) ---
## 地图数据快照，战斗前保存，战斗后恢复，避免重新生成
var map_snapshot: Dictionary = {}  # {grid_data, edges, room_types, current_row, visited_coords, available_coords}

func start_run() -> void:
	# Reset everything and set initial deck
	deck = {
		CharacterRegistry.PlantType.P002SunFlower: 5,
		CharacterRegistry.PlantType.P001PeaShooterSingle: 10,
		CharacterRegistry.PlantType.P005PotatoMine: 3,
		CharacterRegistry.PlantType.P004WallNut: 2,
	}
	starting_sun = 50
	gold = 0
	RogueBuffManager.reset()
	is_run_active = true
	current_floor = 0
	battles_won = 0
	pending_battle_config = {}
	map_snapshot = {}
	run_started.emit()

func end_run() -> void:
	is_run_active = false
	run_ended.emit()

# --- Deck helpers ---

## Add plants to deck (e.g. as reward)
func add_plant(plant_type: CharacterRegistry.PlantType, count: int = 1) -> void:
	deck[plant_type] = deck.get(plant_type, 0) + count
	deck_changed.emit()

## Remove one stock of a plant (consumed during battle). Returns false if no stock.
func consume_plant(plant_type: CharacterRegistry.PlantType) -> bool:
	var current: int = deck.get(plant_type, 0)
	if current <= 0:
		return false
	deck[plant_type] = current - 1
	if deck[plant_type] <= 0:
		deck.erase(plant_type)
	deck_changed.emit()
	return true

## Get total number of plant cards in deck
func get_deck_size() -> int:
	var total: int = 0
	for count in deck.values():
		total += count
	return total

## Build conveyor belt probability dict from current deck
## Returns Dictionary[CharacterRegistry.PlantType, int] suitable for ResourceLevelData.all_card_plant_type_probability
func build_conveyor_probabilities() -> Dictionary[CharacterRegistry.PlantType, int]:
	var probs: Dictionary[CharacterRegistry.PlantType, int] = {}
	for plant_type in deck:
		probs[plant_type] = deck[plant_type]
	return probs

# --- Gold helpers ---
func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit()

func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	gold_changed.emit()
	return true

# --- Buff / Relic 桥接 API (兼容旧代码, 推荐直接使用 RogueBuffManager) ---

## 通过旧式字典添加 buff (向后兼容)
func add_buff(buff_id: String, buff_name: String, description: String, params: Dictionary = {}) -> void:
	var buff := BuffData.new()
	buff.id = StringName(buff_id)
	buff.display_name = buff_name
	buff.description = description
	RogueBuffManager.add_buff(buff)

func remove_buff(buff_id: String) -> void:
	RogueBuffManager.remove_buff(StringName(buff_id))

func has_buff(buff_id: String) -> bool:
	return RogueBuffManager.has_buff(StringName(buff_id))

## 通过旧式字典添加遗物 (向后兼容)
func add_relic(relic_id: String, relic_name: String, description: String, params: Dictionary = {}) -> void:
	var relic := RelicData.new()
	relic.id = StringName(relic_id)
	relic.display_name = relic_name
	relic.description = description
	RogueBuffManager.add_relic(relic)

func has_relic(relic_id: String) -> bool:
	return RogueBuffManager.has_relic(StringName(relic_id))

## 直接添加 Resource 对象 (推荐新代码使用)
func add_relic_resource(relic: RelicData) -> void:
	RogueBuffManager.add_relic(relic)

func add_buff_resource(buff: BuffData) -> void:
	RogueBuffManager.add_buff(buff)
