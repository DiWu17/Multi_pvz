extends Node
## 肉鸽Buff/遗物效果管理器
##
## 职责:
## 1. 维护当前 run 中激活的 RelicData / BuffData 列表
## 2. 提供 query API 供游戏各系统查询聚合后的效果数值
## 3. 监听 EventBus 事件，执行触发型效果 (如击杀获得阳光)
##
## 设计原则 — "查询式" 而非 "修改式":
##   游戏系统在需要时主动调用 get_xxx() 查询最终数值，
##   而不是由本 Manager 去修改各系统的内部变量。
##   这样每个效果的来源都可追溯，移除效果也不会留下脏数据。

## ─── 信号 ───
signal relics_changed
signal buffs_changed

## ─── 激活列表 ───
var _active_relics: Array[RelicData] = []
var _active_buffs: Array[BuffData] = []
## Buff 叠加计数 {buff_id: current_stacks}
var _buff_stacks: Dictionary = {}
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
	_active_buffs.clear()
	_buff_stacks.clear()
	_base_zombie_hp_mult = 1.0
	_base_zombie_atk_mult = 1.0
	relics_changed.emit()
	buffs_changed.emit()

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
#  Buff API
# ══════════════════════════════════════════

func add_buff(buff: BuffData) -> void:
	var current_stacks: int = _buff_stacks.get(buff.id, 0)
	if buff.max_stacks > 0 and current_stacks >= buff.max_stacks:
		return
	_active_buffs.append(buff)
	_buff_stacks[buff.id] = current_stacks + 1
	buffs_changed.emit()

func remove_buff(buff_id: StringName) -> void:
	for i in range(_active_buffs.size() - 1, -1, -1):
		if _active_buffs[i].id == buff_id:
			_active_buffs.remove_at(i)
			var stacks: int = _buff_stacks.get(buff_id, 1) - 1
			if stacks <= 0:
				_buff_stacks.erase(buff_id)
			else:
				_buff_stacks[buff_id] = stacks
			break
	buffs_changed.emit()

func has_buff(buff_id: StringName) -> bool:
	return _buff_stacks.get(buff_id, 0) > 0

func get_buffs() -> Array[BuffData]:
	return _active_buffs

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
	for b in _active_buffs:
		if b.effect_type == RelicData.EffectType.SUN_PRODUCTION_MULTIPLIER:
			mult += b.param_float
	return mult

## 获取植物攻击力倍率 (1.0 = 无加成)
func get_attack_multiplier() -> float:
	var mult := 1.0
	for r in _active_relics:
		if r.effect_type == RelicData.EffectType.ATTACK_MULTIPLIER:
			mult += r.param_float
	for b in _active_buffs:
		if b.effect_type == RelicData.EffectType.ATTACK_MULTIPLIER:
			mult += b.param_float
	return mult

## 获取初始阳光加成总值
func get_starting_sun_bonus() -> int:
	var bonus := 0
	for r in _active_relics:
		if r.effect_type == RelicData.EffectType.STARTING_SUN_BONUS:
			bonus += r.param_int
	for b in _active_buffs:
		if b.effect_type == RelicData.EffectType.STARTING_SUN_BONUS:
			bonus += b.param_int
	return bonus

## 获取自然阳光产出速率倍率 (1.0 = 正常, < 1.0 = 更快)
## 返回的是计时器乘数，0.95 表示加快 5%
func get_sky_sun_rate_multiplier() -> float:
	var mult := 1.0
	for r in _active_relics:
		if r.effect_type == RelicData.EffectType.SKY_SUN_RATE_MULTIPLIER:
			mult -= r.param_float
	for b in _active_buffs:
		if b.effect_type == RelicData.EffectType.SKY_SUN_RATE_MULTIPLIER:
			mult -= b.param_float
	return maxf(mult, 0.1)  # 最低不低于 0.1

## 是否启用自动拾取阳光
func is_auto_collect_sun() -> bool:
	for r in _active_relics:
		if r.effect_type == RelicData.EffectType.AUTO_COLLECT_SUN:
			return true
	for b in _active_buffs:
		if b.effect_type == RelicData.EffectType.AUTO_COLLECT_SUN:
			return true
	return false

## 获取击杀敌人获得的阳光总值
func get_sun_on_kill() -> int:
	var total := 0
	for r in _active_relics:
		if r.effect_type == RelicData.EffectType.SUN_ON_KILL:
			total += r.param_int
	for b in _active_buffs:
		if b.effect_type == RelicData.EffectType.SUN_ON_KILL:
			total += b.param_int
	return total

# ══════════════════════════════════════════
#  通用聚合查询 — 按 EffectType 查询所有匹配效果
# ══════════════════════════════════════════

## 获取指定效果类型的所有浮点参数之和
func sum_float_by_effect(effect_type: RelicData.EffectType) -> float:
	var total := 0.0
	for r in _active_relics:
		if r.effect_type == effect_type:
			total += r.param_float
	for b in _active_buffs:
		if b.effect_type == effect_type:
			total += b.param_float
	return total

## 获取指定效果类型的所有整数参数之和
func sum_int_by_effect(effect_type: RelicData.EffectType) -> int:
	var total := 0
	for r in _active_relics:
		if r.effect_type == effect_type:
			total += r.param_int
	for b in _active_buffs:
		if b.effect_type == effect_type:
			total += b.param_int
	return total

## 是否拥有指定效果类型的任意遗物或buff
func has_effect(effect_type: RelicData.EffectType) -> bool:
	for r in _active_relics:
		if r.effect_type == effect_type:
			return true
	for b in _active_buffs:
		if b.effect_type == effect_type:
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
