extends Node
## 肉鸽遗物 & 卡牌附魔管理器
##
## 职责:
## 1. 维护当前 run 中激活的 RelicData 列表 (遗物 = 全局被动效果)
## 2. 维护卡牌附魔映射 (附魔 = 绑定到特定植物类型的效果)
## 3. 提供 query API 供游戏各系统查询聚合后的效果数值
## 4. 监听 EventBus 事件，执行触发型效果 (如击杀获得阳光)
##
## 设计原则 — "查询式" 而非 "修改式":
##   游戏系统在需要时主动调用 get_xxx() 查询最终数值，
##   而不是由本 Manager 去修改各系统的内部变量。

## ─── 信号 ───
signal relics_changed
signal enchants_changed

## ─── 遗物列表 ───
var _active_relics: Array[RelicData] = []

## ─── 卡牌实例附魔 ───
## { int (card_uid) -> Array[BuffData] }
## 每张卡牌实例可以有多个附魔
var _card_instance_enchants: Dictionary = {}

## 当前战斗的基础僵尸血量/攻击倍率 (battle_room 设置)
var _base_zombie_hp_mult: float = 1.0
var _base_zombie_atk_mult: float = 1.0

# ══════════════════════════════════════════
#  生命周期
# ══════════════════════════════════════════

func _ready() -> void:
	# 监听僵尸死亡事件 (用于 SUN_ON_KILL 效果)
	EventBus.subscribe("zombie_killed", _on_zombie_killed)

## 开始新一轮 run 时清空所有效果
func reset() -> void:
	_active_relics.clear()
	_card_instance_enchants.clear()
	_base_zombie_hp_mult = 1.0
	_base_zombie_atk_mult = 1.0
	relics_changed.emit()
	enchants_changed.emit()

# ══════════════════════════════════════════
#  遗物 API
# ══════════════════════════════════════════

func add_relic(relic: RelicData) -> void:
	if not relic.stackable and has_relic(relic.id):
		return
	_active_relics.append(relic)
	relics_changed.emit()

func remove_relic(relic_id: StringName) -> void:
	for i in range(_active_relics.size() - 1, -1, -1):
		if _active_relics[i].id == relic_id:
			_active_relics.remove_at(i)
			break
	relics_changed.emit()

func has_relic(relic_id: StringName) -> bool:
	for r in _active_relics:
		if r.id == relic_id:
			return true
	return false

func get_relics() -> Array[RelicData]:
	return _active_relics

# ══════════════════════════════════════════
#  卡牌实例附魔 API
# ══════════════════════════════════════════

## 为指定卡牌实例 (UID) 添加附魔
func add_instance_enchant(card_uid: int, enchant: BuffData) -> void:
	if not _card_instance_enchants.has(card_uid):
		_card_instance_enchants[card_uid] = []
	_card_instance_enchants[card_uid].append(enchant)
	enchants_changed.emit()

## 移除指定卡牌实例的某个附魔
func remove_instance_enchant(card_uid: int, enchant_id: StringName) -> void:
	if not _card_instance_enchants.has(card_uid):
		return
	var enchants: Array = _card_instance_enchants[card_uid]
	for i in range(enchants.size() - 1, -1, -1):
		if enchants[i].id == enchant_id:
			enchants.remove_at(i)
			break
	if enchants.is_empty():
		_card_instance_enchants.erase(card_uid)
	enchants_changed.emit()

## 清除指定卡牌实例的所有附魔（卡牌被移除时调用）
func remove_instance_enchants(card_uid: int) -> void:
	if _card_instance_enchants.has(card_uid):
		_card_instance_enchants.erase(card_uid)

## 获取指定卡牌实例的所有附魔
func get_instance_enchants(card_uid: int) -> Array:
	return _card_instance_enchants.get(card_uid, [])

## 检查指定卡牌实例是否有某种附魔
func instance_has_enchant(card_uid: int, enchant_name: StringName) -> bool:
	if not _card_instance_enchants.has(card_uid):
		return false
	for e in _card_instance_enchants[card_uid]:
		match enchant_name:
			&"pumpkin":
				if e.enchant_type == BuffData.EnchantType.PUMPKIN:
					return true
			&"inherent":
				if e.enchant_type == BuffData.EnchantType.INHERENT:
					return true
			&"consumable":
				if e.enchant_type == BuffData.EnchantType.CONSUMABLE:
					return true
	return false

## 检查指定植物类型是否有任何实例拥有某种附魔（用于传送带等类型级查询）
func card_has_enchant(plant_type, enchant_name: StringName) -> bool:
	if not RogueState.card_uids.has(plant_type):
		return false
	for uid in RogueState.card_uids[plant_type]:
		if instance_has_enchant(uid, enchant_name):
			return true
	return false

## 获取指定植物类型中拥有某种附魔的所有 UID
func get_uids_with_enchant(plant_type, enchant_name: StringName) -> Array[int]:
	var result: Array[int] = []
	if not RogueState.card_uids.has(plant_type):
		return result
	for uid in RogueState.card_uids[plant_type]:
		if instance_has_enchant(uid, enchant_name):
			result.append(uid)
	return result

## 获取所有实例附魔映射
func get_all_instance_enchants() -> Dictionary:
	return _card_instance_enchants

## ─── 旧的类型级附魔 API (兼容桥接) ───

func add_card_enchant(plant_type, enchant: BuffData) -> void:
	push_warning("[RogueBuffManager] add_card_enchant(plant_type) 已废弃，请使用 add_instance_enchant(uid)")
	## 兼容：给该类型所有实例添加
	if RogueState.card_uids.has(plant_type):
		for uid in RogueState.card_uids[plant_type]:
			add_instance_enchant(uid, enchant)

func get_card_enchants(plant_type) -> Array:
	var result: Array = []
	if RogueState.card_uids.has(plant_type):
		for uid in RogueState.card_uids[plant_type]:
			result.append_array(get_instance_enchants(uid))
	return result

func get_all_enchants() -> Dictionary:
	return _card_instance_enchants

# ══════════════════════════════════════════
#  效果查询 API — 游戏系统调用这些方法获取聚合值
# ══════════════════════════════════════════

## 获取阳光产出倍率 (1.0 = 无加成)
## 用法: 实际阳光 = base_sun * get_sun_production_multiplier()
func get_sun_production_multiplier() -> float:
	var mult := 1.0
	for r in _active_relics:
		if r.effect_type == RelicData.EffectType.SUN_PRODUCTION_MULTIPLIER:
			mult += r.param_float
	return mult

## 获取植物攻击力倍率 (1.0 = 无加成)
func get_attack_multiplier() -> float:
	var mult := 1.0
	for r in _active_relics:
		if r.effect_type == RelicData.EffectType.ATTACK_MULTIPLIER:
			mult += r.param_float
	return mult

## 获取初始阳光加成总值
func get_starting_sun_bonus() -> int:
	var bonus := 0
	for r in _active_relics:
		if r.effect_type == RelicData.EffectType.STARTING_SUN_BONUS:
			bonus += r.param_int
	return bonus

## 获取自然阳光产出速率倍率 (1.0 = 正常, < 1.0 = 更快)
## 返回的是计时器乘数，0.95 表示加快 5%
func get_sky_sun_rate_multiplier() -> float:
	var mult := 1.0
	for r in _active_relics:
		if r.effect_type == RelicData.EffectType.SKY_SUN_RATE_MULTIPLIER:
			mult -= r.param_float
	return maxf(mult, 0.1)  # 最低不低于 0.1

## 是否启用自动拾取阳光
func is_auto_collect_sun() -> bool:
	for r in _active_relics:
		if r.effect_type == RelicData.EffectType.AUTO_COLLECT_SUN:
			return true
	return false

## 获取击杀敌人获得的阳光总值
func get_sun_on_kill() -> int:
	var total := 0
	for r in _active_relics:
		if r.effect_type == RelicData.EffectType.SUN_ON_KILL:
			total += r.param_int
	return total

# ══════════════════════════════════════════
#  通用聚合查询 — 按 EffectType 查询所有匹配的遗物效果
# ══════════════════════════════════════════

## 获取指定效果类型的所有浮点参数之和
func sum_float_by_effect(effect_type: RelicData.EffectType) -> float:
	var total := 0.0
	for r in _active_relics:
		if r.effect_type == effect_type:
			total += r.param_float
	return total

## 获取指定效果类型的所有整数参数之和
func sum_int_by_effect(effect_type: RelicData.EffectType) -> int:
	var total := 0
	for r in _active_relics:
		if r.effect_type == effect_type:
			total += r.param_int
	return total

## 是否拥有指定效果类型的任意遗物
func has_effect(effect_type: RelicData.EffectType) -> bool:
	for r in _active_relics:
		if r.effect_type == effect_type:
			return true
	return false

# ══════════════════════════════════════════
#  事件处理 — 触发型效果
# ══════════════════════════════════════════

## 僵尸被击杀时触发
func _on_zombie_killed() -> void:
	var sun_amount := get_sun_on_kill()
	if sun_amount > 0:
		EventBus.push_event("add_sun_value", [sun_amount])

## 获取僵尸血量倍率 (1.0 = 无加成)
## 包含战斗房间难度和遗物/buff叠加
func get_zombie_hp_multiplier() -> float:
	var mult := _base_zombie_hp_mult
	mult += sum_float_by_effect(RelicData.EffectType.ZOMBIE_HP_MULTIPLIER)
	return maxf(mult, 0.1)

## 获取僵尸攻击倍率 (1.0 = 无加成)
func get_zombie_atk_multiplier() -> float:
	var mult := _base_zombie_atk_mult
	mult += sum_float_by_effect(RelicData.EffectType.ZOMBIE_ATK_MULTIPLIER)
	return maxf(mult, 0.1)

## 设置当前战斗的基础僵尸倍率 (由 battle_room 调用)
func set_battle_zombie_scaling(hp_mult: float, atk_mult: float) -> void:
	_base_zombie_hp_mult = hp_mult
	_base_zombie_atk_mult = atk_mult
