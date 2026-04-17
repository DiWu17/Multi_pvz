extends MainGameSubManager
class_name DaySunsManagner
## 天降阳光管理器

@export var production_interval: float  # 生产间隔(毫秒)
@export var curr_sun_sum_value := 0

@onready var production_timer: Timer = $ProductionTimer

@export var sun_x_min : float = 50
@export var sun_x_max : float = 750

@export var sun_y_min : float = 130
@export var sun_y_max : float = 550

@export var sun_y_ori : float = -40

@export var sun_y_speed : float = 200

## 多人模式：阳光ID计数器
var _next_sun_id_counter: int = 0
## 多人模式：活跃阳光 {sun_id: Sun}
var active_suns: Dictionary = {}
## 每个玩家收集的阳光统计 {peer_id: int → total_sun: int}
var sun_collected_per_player: Dictionary = {}

func _ready():
	production_timer.timeout.connect(_on_production_timer_timeout)
	EventBus.subscribe("add_sun_value", _on_track_sun_collected)

func init_manager() -> void:
	pass

## 单人模式：追踪阳光收集量
func _on_track_sun_collected(value: int) -> void:
	if NetworkManager.is_multiplayer:
		return
	if not sun_collected_per_player.has(1):
		sun_collected_per_player[1] = 0
	sun_collected_per_player[1] += value

func start_day_sun():
	# 如果计时器是暂停状态，取消暂停
	if production_timer.paused:
		production_timer.paused = false

	if production_timer.is_stopped():
		change_production_interval()
		production_timer.start(production_interval/100)

func pause_day_sun():
	production_timer.paused = true


func _on_production_timer_timeout():
	## 多人模式：仅 Host 生成阳光
	if NetworkManager.is_multiplayer and not NetworkManager.is_server():
		return
	spawn_sun()
	change_production_interval()

## 获取下一个阳光ID
func _next_sun_id() -> int:
	_next_sun_id_counter += 1
	return _next_sun_id_counter

## 创建阳光
func spawn_sun():
	var new_sun = SceneRegistry.SUN.instantiate()
	if new_sun is Sun:
		Global.main_game.suns.add_child(new_sun)
		curr_sun_sum_value += new_sun.sun_value
		# 控制阳光下落
		new_sun.spawn_sun_tween = get_tree().create_tween()
		var pos_x = randf_range(sun_x_min, sun_x_max)
		new_sun.position = Vector2(pos_x, sun_y_ori)
		var target_y = randf_range(sun_y_min, sun_y_max)
		var distance = float(abs(target_y - sun_y_ori))
		var duration = distance / sun_y_speed
		new_sun.spawn_sun_tween.tween_property(new_sun, "position:y", target_y, duration)

		new_sun.spawn_sun_tween.finished.connect(new_sun.on_sun_tween_finished)

		## 多人模式：注册阳光并广播给客户端
		if NetworkManager.is_multiplayer and NetworkManager.is_server():
			var sun_id = _next_sun_id()
			new_sun.set_meta("sun_id", sun_id)
			active_suns[sun_id] = new_sun
			NetworkManager.broadcast_sun_spawn.rpc(sun_id, pos_x, sun_y_ori, target_y)

## 多人模式：从网络生成阳光（客户端调用）
func spawn_sun_from_network(sun_id: int, pos: Vector2, target_y: float) -> void:
	var new_sun = SceneRegistry.SUN.instantiate()
	if new_sun is Sun:
		Global.main_game.suns.add_child(new_sun)
		new_sun.position = pos
		new_sun.set_meta("sun_id", sun_id)
		active_suns[sun_id] = new_sun
		new_sun.spawn_sun_tween = get_tree().create_tween()
		var distance = float(abs(target_y - pos.y))
		var duration = distance / sun_y_speed
		new_sun.spawn_sun_tween.tween_property(new_sun, "position:y", target_y, duration)
		new_sun.spawn_sun_tween.finished.connect(new_sun.on_sun_tween_finished)

## 多人模式：Host 验证阳光收集
func try_collect_sun_network(sun_id: int, peer_id: int) -> void:
	if sun_id in active_suns:
		var sun = active_suns[sun_id]
		active_suns.erase(sun_id)
		## 如果阳光还在且没被本地点击收集，直接销毁（非点击方式的收集）
		if is_instance_valid(sun) and sun is Sun and not sun.collected:
			sun.collected = true
			sun.queue_free()
		## 使用阳光原始值（不缩放），频率已提高
		var value = sun.sun_value if is_instance_valid(sun) and sun is Sun else 25
		## 统计每个玩家收集的阳光
		if not sun_collected_per_player.has(peer_id):
			sun_collected_per_player[peer_id] = 0
		sun_collected_per_player[peer_id] += value
		## 加阳光并同步
		var card_slot = Global.main_game.card_manager.card_slot_battle
		if card_slot:
			card_slot.sun_value += value
			NetworkManager.broadcast_sun_collected.rpc(sun_id, card_slot.sun_value, peer_id, value)

## 多人模式：阳光被收集的客户端处理
func on_sun_collected_network(sun_id: int, collector_peer_id: int = -1, sun_amount: int = 0) -> void:
	if sun_id in active_suns:
		var sun = active_suns[sun_id]
		active_suns.erase(sun_id)
		if is_instance_valid(sun) and sun is Sun and not sun.collected:
			## 其他玩家收集的阳光，本地直接销毁
			sun.collected = true
			sun.queue_free()
		## 如果 sun.collected 已为 true，说明是本地玩家点击的，动画会自行处理销毁
	## 统计每个玩家收集的阳光（客户端同步）
	if collector_peer_id > 0 and sun_amount > 0:
		if not sun_collected_per_player.has(collector_peer_id):
			sun_collected_per_player[collector_peer_id] = 0
		sun_collected_per_player[collector_peer_id] += sun_amount

## 多人模式：从网络生成植物产生的阳光（客户端调用）
func spawn_plant_sun_from_network(sun_id: int, pos: Vector2, rand_x: float, sun_val: int = 25) -> void:
	var new_sun:Sun = SceneRegistry.SUN.instantiate()
	new_sun.init_sun(sun_val, pos)
	Global.main_game.suns.add_child(new_sun)
	new_sun.set_meta("sun_id", sun_id)
	active_suns[sun_id] = new_sun

	var tween = new_sun.create_tween()
	var center_y : float = -15
	var target_y : float = 45
	tween.tween_property(new_sun, "position:y", center_y, 0.3).as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(new_sun, "position:y", target_y, 0.6).as_relative().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	new_sun.spawn_sun_tween = get_tree().create_tween()
	new_sun.spawn_sun_tween.set_parallel()
	new_sun.spawn_sun_tween.tween_subtween(tween)
	new_sun.spawn_sun_tween.tween_property(new_sun, "position:x", rand_x, 0.9).as_relative()
	new_sun.spawn_sun_tween.finished.connect(new_sun.on_sun_tween_finished)

func change_production_interval():
	var A : float = 10 * curr_sun_sum_value + 425
		# 下次天降阳光时间
	if A<950:
		production_interval = (A + randf_range(0,274))
	else:
		production_interval = 950 + randf_range(0,274)

	## 多人模式：按频率倍率缩短间隔
	var freq_scale = NetworkManager.get_sun_freq_scale()
	## Buff/遗物: 自然阳光产出速率加成
	var buff_scale := RogueBuffManager.get_sky_sun_rate_multiplier() if RogueState.is_run_active else 1.0
	production_timer.start(production_interval / 100 * freq_scale * buff_scale)
