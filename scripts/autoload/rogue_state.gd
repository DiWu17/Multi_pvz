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

# --- 卡牌实例 UID 系统 ---
# 每张卡牌都有唯一 UID，用于实例级附魔
var card_uids: Dictionary = {}  # CharacterRegistry.PlantType -> Array[int]
var _next_card_uid: int = 0

# --- Gold ---
var gold: int = 0

# --- Buff / Relic 已迁移至 RogueBuffManager (基于 Resource 的系统) ---
# Buff 系统已重构为卡牌附魔系统，以下属性保留为兼容桥接
var active_buffs: Array:
	get: return []
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
		CharacterRegistry.PlantType.P001PeaShooterSingle: 5,
		CharacterRegistry.PlantType.P005PotatoMine: 3,
		CharacterRegistry.PlantType.P004WallNut: 2,
	}
	starting_sun = 50
	gold = 0
	_next_card_uid = 0
	card_uids = {}
	# 为初始卡组分配 UID
	for plant_type in deck:
		card_uids[plant_type] = []
		for i in range(deck[plant_type]):
			card_uids[plant_type].append(_next_card_uid)
			_next_card_uid += 1
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

## 添加植物卡到牌组（如事件奖励）
func add_plant(plant_type: CharacterRegistry.PlantType, count: int = 1) -> void:
	deck[plant_type] = deck.get(plant_type, 0) + count
	if not card_uids.has(plant_type):
		card_uids[plant_type] = []
	for i in range(count):
		card_uids[plant_type].append(_next_card_uid)
		_next_card_uid += 1
	deck_changed.emit()

## 移除植物卡（如事件惩罚），返回是否成功（如果卡牌不足则失败）
func consume_plant(plant_type: CharacterRegistry.PlantType) -> bool:
	var current: int = deck.get(plant_type, 0)
	if current <= 0:
		return false
	deck[plant_type] = current - 1
	# 移除最后一个 UID，同时清理其附魔
	if card_uids.has(plant_type) and not card_uids[plant_type].is_empty():
		var removed_uid: int = card_uids[plant_type].pop_back()
		RogueBuffManager.remove_instance_enchants(removed_uid)
	if deck[plant_type] <= 0:
		deck.erase(plant_type)
		card_uids.erase(plant_type)
	deck_changed.emit()
	return true

## Get total number of plant cards in deck
func get_deck_size() -> int:
	var total: int = 0
	for count in deck.values():
		total += count
	return total

## 检查牌组中是否有某种植物卡
## 返回 Dictionary[PlantType, int]，表示每种植物在传送带上出现的权重（基于当前牌组）
func build_conveyor_probabilities() -> Dictionary[CharacterRegistry.PlantType, int]:
	var probs: Dictionary[CharacterRegistry.PlantType, int] = {}
	for plant_type in deck:
		probs[plant_type] = deck[plant_type]
	return probs

## 获取所有卡牌实例（展开为单独条目，每张卡有 uid）
## 返回 Array[Dictionary]，每个元素: {uid: int, plant_type: PlantType, enchants: Array[BuffData]}
func get_all_card_instances() -> Array:
	var result: Array = []
	for plant_type in card_uids:
		for uid in card_uids[plant_type]:
			result.append({
				"uid": uid,
				"plant_type": plant_type,
				"enchants": RogueBuffManager.get_instance_enchants(uid),
			})
	return result

# --- 金币 ---
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

## 为卡牌添加附魔 (按 UID，新系统)
func add_card_enchant_by_uid(card_uid: int, enchant: BuffData) -> void:
	RogueBuffManager.add_instance_enchant(card_uid, enchant)

## 为卡牌添加附魔 (按类型，给该类型所有实例添加)
func add_card_enchant(plant_type: CharacterRegistry.PlantType, enchant: BuffData) -> void:
	if card_uids.has(plant_type):
		for uid in card_uids[plant_type]:
			RogueBuffManager.add_instance_enchant(uid, enchant)
