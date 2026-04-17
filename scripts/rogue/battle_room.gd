extends Control
class_name BattleRoom

## 战斗房间 - 配置并启动真实PVZ传送带战斗
## 战斗通过改变场景到主游戏实现，胜利后返回肉鸽地图

signal room_completed(victory: bool)

## 战斗难度配置
const BATTLE_CONFIG: Dictionary = {
	## MONSTER: 普通战斗
	RogueMapNode.RoomType.MONSTER: {
		"min_waves": 1,              # 最少波次
		"max_waves": 1,              # 最多波次
		"min_zombies_per_wave": 3,   # 每波最少僵尸数
		"max_zombies_per_wave": 6,   # 每波最多僵尸数
		"hp_multiplier": 0.8,        # 僵尸血量倍率
		"atk_multiplier": 0.8,       # 僵尸攻击倍率
		"zombie_pool": "basic",      # 僵尸池（只有普通/路障/铁桶）
		"reward_picks": 2,   ## 四选二
		"gold_min": 10,
		"gold_max": 30,
	},
	## ELITE: 精英战斗
	RogueMapNode.RoomType.ELITE: {
		"min_waves": 1,
		"max_waves": 3,
		"min_zombies_per_wave": 4,
		"max_zombies_per_wave": 8,
		"hp_multiplier": 1.3,
		"atk_multiplier": 1.2,
		"zombie_pool": "elite",
		"reward_picks": 3,   ## 四选三
		"gold_min": 30,
		"gold_max": 50,
	},
	## BOSS: Boss战斗
	RogueMapNode.RoomType.BOSS: {
		"min_waves": 6,
		"max_waves": 6,
		"min_zombies_per_wave": 5,
		"max_zombies_per_wave": 10,
		"hp_multiplier": 1.5,
		"atk_multiplier": 1.3,
		"zombie_pool": "boss",
		"reward_picks": 4,   ## 四选四
		"gold_min": 100,
		"gold_max": 150,
	},
}

## 基础僵尸池（普通战斗用）
const BASIC_ZOMBIE_POOL: Array = [
	CharacterRegistry.ZombieType.Z001Norm,
	CharacterRegistry.ZombieType.Z003Cone,
	CharacterRegistry.ZombieType.Z005Bucket,
]

## 精英僵尸池（精英战斗用，包含特殊僵尸）
const ELITE_ZOMBIE_POOL: Array = [
	CharacterRegistry.ZombieType.Z001Norm,
	CharacterRegistry.ZombieType.Z003Cone,
	CharacterRegistry.ZombieType.Z005Bucket,
	CharacterRegistry.ZombieType.Z006Paper,
	CharacterRegistry.ZombieType.Z007ScreenDoor,
	CharacterRegistry.ZombieType.Z008Football,
	CharacterRegistry.ZombieType.Z009Jackson,
]

## Boss僵尸池（Boss战用，包含所有僵尸类型）
const BOSS_ZOMBIE_POOL: Array = [
	CharacterRegistry.ZombieType.Z001Norm,
	CharacterRegistry.ZombieType.Z003Cone,
	CharacterRegistry.ZombieType.Z005Bucket,
	CharacterRegistry.ZombieType.Z006Paper,
	CharacterRegistry.ZombieType.Z007ScreenDoor,
	CharacterRegistry.ZombieType.Z008Football,
	CharacterRegistry.ZombieType.Z009Jackson,
	CharacterRegistry.ZombieType.Z016Jackbox,
	CharacterRegistry.ZombieType.Z019Pogo,
	CharacterRegistry.ZombieType.Z024Gargantuar,
]

## 当前战斗状态
var room_type: RogueMapNode.RoomType = RogueMapNode.RoomType.MONSTER
var map_row: int = 0                    ## 当前地图行，影响难度缩放
var _config: Dictionary = {}
var _wave_data: Array = []              ## 生成的波次数据
var _current_wave: int = 0

func _ready() -> void:
	_config = BATTLE_CONFIG.get(room_type, BATTLE_CONFIG[RogueMapNode.RoomType.MONSTER])
	_generate_waves()
	# Defer launch so the node is fully in the tree before we change scene
	_launch_battle.call_deferred()

## 设置战斗参数（在加入场景树前调用）
func setup(p_room_type: RogueMapNode.RoomType, p_row: int) -> void:
	room_type = p_room_type
	map_row = p_row

## 生成波次数据
func _generate_waves() -> void:
	_wave_data.clear()
	var wave_count: int = randi_range(_config["min_waves"], _config["max_waves"])
	var pool: Array = _get_zombie_pool()

	for wave_idx in range(wave_count):
		var zombie_count: int = randi_range(
			_config["min_zombies_per_wave"],
			_config["max_zombies_per_wave"]
		)
		# 后面的波次稍微增加僵尸数
		zombie_count += wave_idx / 2

		var wave: Dictionary = {
			"zombies": _pick_zombies(pool, zombie_count, wave_idx, wave_count),
			"hp_multiplier": _config["hp_multiplier"] * _get_row_scaling(),
			"atk_multiplier": _config["atk_multiplier"] * _get_row_scaling(),
		}
		_wave_data.append(wave)

func _get_zombie_pool() -> Array:
	match _config.get("zombie_pool", "basic"):
		"elite":
			return ELITE_ZOMBIE_POOL
		"boss":
			return BOSS_ZOMBIE_POOL
		_:
			return BASIC_ZOMBIE_POOL

## 根据地图行数缩放难度（越高层越难）
func _get_row_scaling() -> float:
	return 1.0 + map_row * 0.05

## 为一个波次选择僵尸
func _pick_zombies(pool: Array, count: int, wave_idx: int, total_waves: int) -> Array:
	var zombies: Array = []
	for i in range(count):
		# 后期波次更倾向于选择池子中靠后的（更强的）僵尸
		var weight_factor: float = float(wave_idx) / float(maxi(total_waves - 1, 1))
		var idx: int
		if randf() < weight_factor * 0.5:
			# 倾向于选强僵尸
			idx = randi_range(pool.size() / 2, pool.size() - 1)
		else:
			idx = randi() % pool.size()
		zombies.append(pool[idx])
	return zombies

## 配置并启动真实PVZ传送带战斗
func _launch_battle() -> void:
	var level_data := create_level_data()

	# 在 RogueState 中保存战斗上下文，以便战斗胜利后回到肉鸽地图时处理奖励
	RogueState.pending_battle_config = {
		"room_type": room_type,
		"map_row": map_row,
		"gold_min": _config["gold_min"],
		"gold_max": _config["gold_max"],
		"reward_picks": _config["reward_picks"],
	}

	# 设置全局游戏参数并切换到主游戏场景
	Global.game_para = level_data
	get_tree().change_scene_to_file(
		Global.main_scene_registry.MainScenesMap[level_data.game_sences]
	)

## 创建传送带模式的关卡数据
func create_level_data() -> ResourceLevelData:
	var level_data := ResourceLevelData.new()

	# 场景与模式 - 胜利后返回肉鸽地图
	level_data.game_mode = MainSceneRegistry.MainScenes.RogueMap
	level_data.game_sences = MainSceneRegistry.MainScenes.MainGameFront
	level_data.game_round = 1

	# 肉鸽传送带模式配置（有限卡组、消耗阳光）
	level_data.card_mode = ConstLevelData.E_CardMode.RogueConveyor
	level_data.can_choosed_card = false
	level_data.is_day_sun = true
	level_data.start_sun = RogueState.starting_sun + RogueBuffManager.get_starting_sun_bonus()
	level_data.look_show_zombie = false
	level_data.is_lawn_mover = true

	# 根据玩家牌组生成传送带植物概率
	level_data.all_card_plant_type_probability = RogueState.build_conveyor_probabilities()

	# 僵尸配置
	level_data.max_wave = _wave_data.size() * 10
	level_data.zombie_multy = maxi(int(_get_row_scaling()), 1)  # spawn budget scales with row, always >= 1

	# 僵尸血量/攻击倍率通过 RogueBuffManager 传递给僵尸实例化
	var row_scale: float = _get_row_scaling()
	RogueBuffManager.set_battle_zombie_scaling(
		_config["hp_multiplier"] * row_scale,
		_config["atk_multiplier"] * row_scale
	)
	var pool: Array = _get_zombie_pool()
	var zombie_types: Array[CharacterRegistry.ZombieType] = []
	for z in pool:
		zombie_types.append(z)
	level_data.zombie_refresh_types = zombie_types

	return level_data

## 获取生成的波次数据（供外部系统使用）
func get_wave_data() -> Array:
	return _wave_data

## 获取战斗配置
func get_config() -> Dictionary:
	return _config

## 获取奖励金币数
func roll_gold_reward() -> int:
	return randi_range(_config["gold_min"], _config["gold_max"])

## 获取奖励可选数
func get_reward_picks() -> int:
	return _config["reward_picks"]
