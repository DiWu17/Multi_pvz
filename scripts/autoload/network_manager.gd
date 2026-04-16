extends Node
## 网络连接管理器 autoload
## 负责：创建/加入房间、玩家注册、断线处理、RPC 转发

#region 信号
## 玩家加入
signal player_joined(peer_id: int, player_info: Dictionary)
## 玩家离开
signal player_left(peer_id: int)
## 玩家离开（附带玩家名称）
signal player_left_with_name(peer_id: int, player_name: String)
## 服务器已连接
signal server_connected
## 服务器断开
signal server_disconnected
## 连接失败
signal connection_failed
## 网络质量更新（客户端到 Host）
signal net_stats_updated(ping_ms: int, packet_loss: float)
## 所有玩家准备完毕
signal all_players_ready
## 游戏开始
signal game_started
## 玩家列表更新（准备状态等变化时）
signal player_list_updated
## 中继房间创建成功（返回房间码）
signal relay_room_created(room_code: String)
## 种植成功信号（在_execute_plant成功后发出）
signal plant_success_confirmed(plant_type: int, row: int, col: int, owner_id: int)
## 种植被拒绝信号（阳光不足等原因）
signal plant_rejected(reason: String)
#endregion

#region 常量
const DEFAULT_PORT := 27015
const MAX_PLAYERS := 4
const NET_PROBE_INTERVAL := 1.0
const NET_PROBE_WINDOW_SIZE := 20
const NET_PROBE_TIMEOUT_MS := 2500
#endregion

#region 玩家数据
## 玩家颜色 P1红 P2蓝 P3绿 P4黄
const PLAYER_COLORS := [
	Color(1.0, 0.3, 0.3),  # 红
	Color(0.1, 0.7, 1.0),  # 蓝（更亮更显眼）
	Color(0.3, 1.0, 0.4),  # 绿
	Color(1.0, 0.9, 0.3),  # 黄
]

## 所有玩家信息 {peer_id: {name, color_index, is_ready, is_card_chosen}}
var players: Dictionary = {}
## 本地玩家信息
var local_player_name: String = "Player"
## 是否为多人游戏模式
var is_multiplayer: bool = false
## 当前玩家数量
var player_count: int:
	get:
		return players.size()

## 本地网络质量（仅客户端有效）
var _net_ping_ms: int = -1
var _net_packet_loss: float = 0.0
var _net_probe_seq: int = 0
var _net_probe_records: Array[Dictionary] = []
var _net_probe_timer: Timer = null
#endregion

#region 大厅状态
enum LobbyState {
	IDLE,        ## 未连接
	IN_LOBBY,    ## 在大厅中
	CHOOSING,    ## 选卡阶段
	PLAYING,     ## 游戏中
}
var lobby_state: LobbyState = LobbyState.IDLE
## 中继房间码（中继模式下有效）
var relay_room_code: String = ""
## 多人模式选择的游戏模式（选关场景）
var selected_game_mode: MainSceneRegistry.MainScenes = MainSceneRegistry.MainScenes.ChooseLevelAdventure
#endregion

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	_net_probe_timer = Timer.new()
	_net_probe_timer.wait_time = NET_PROBE_INTERVAL
	_net_probe_timer.autostart = true
	_net_probe_timer.timeout.connect(_on_net_probe_timer_timeout)
	add_child(_net_probe_timer)

#region 连接管理
## 创建房间（Host）
func create_server(port: int = DEFAULT_PORT, player_name: String = "Host") -> Error:
	_reset_net_stats()
	local_player_name = player_name
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		push_error("NetworkManager: 创建服务器失败，错误码: %d" % error)
		return error

	multiplayer.multiplayer_peer = peer
	is_multiplayer = true
	lobby_state = LobbyState.IN_LOBBY

	# Host 注册自己
	_register_player(1, {
		"name": player_name,
		"color_index": 0,
		"is_ready": false,
		"is_card_chosen": false,
		"is_restart_voted": false,
	})
	print("NetworkManager: 服务器创建成功，端口: %d" % port)
	return OK

## 通过中继服务器创建房间（Host）
func create_relay_host(relay_url: String, player_name: String = "Host") -> Error:
	_reset_net_stats()
	local_player_name = player_name
	var peer = RelayMultiplayerPeer.new()
	var error = peer.create_relay_host(relay_url, player_name)
	if error != OK:
		push_error("NetworkManager: 连接中继服务器失败，错误码: %d" % error)
		return error

	peer.relay_room_created.connect(_on_relay_room_created)
	peer.relay_error.connect(_on_relay_error)

	multiplayer.multiplayer_peer = peer
	is_multiplayer = true
	print("NetworkManager: 正在连接中继服务器 %s ..." % relay_url)
	return OK

## 通过中继服务器加入房间（Client）
func join_relay_room(relay_url: String, room_code: String, player_name: String = "Player") -> Error:
	_reset_net_stats()
	local_player_name = player_name
	var peer = RelayMultiplayerPeer.new()
	var error = peer.join_relay_room(relay_url, room_code, player_name)
	if error != OK:
		push_error("NetworkManager: 连接中继服务器失败，错误码: %d" % error)
		return error

	peer.relay_error.connect(_on_relay_error)

	multiplayer.multiplayer_peer = peer
	is_multiplayer = true
	print("NetworkManager: 正在通过中继加入房间 %s ..." % room_code)
	return OK

## 中继房间创建成功回调
func _on_relay_room_created(room_code: String) -> void:
	lobby_state = LobbyState.IN_LOBBY
	relay_room_code = room_code
	_register_player(1, {
		"name": local_player_name,
		"color_index": 0,
		"is_ready": false,
		"is_card_chosen": false,
		"is_restart_voted": false,
	})
	relay_room_created.emit(room_code)
	print("NetworkManager: 中继房间创建成功，房间码: %s" % room_code)

## 中继错误回调
func _on_relay_error(message: String) -> void:
	push_error("NetworkManager 中继错误: %s" % message)

## 加入房间（Client）
func join_server(address: String, port: int = DEFAULT_PORT, player_name: String = "Player") -> Error:
	_reset_net_stats()
	local_player_name = player_name
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(address, port)
	if error != OK:
		push_error("NetworkManager: 连接服务器失败，错误码: %d" % error)
		return error

	multiplayer.multiplayer_peer = peer
	is_multiplayer = true
	print("NetworkManager: 正在连接到 %s:%d ..." % [address, port])
	return OK

## 断开连接
func disconnect_from_server() -> void:
	_reset_net_stats()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	players.clear()
	is_multiplayer = false
	lobby_state = LobbyState.IDLE
	relay_room_code = ""
	print("NetworkManager: 已断开连接")
#endregion

#region 连接回调
func _on_peer_connected(peer_id: int) -> void:
	GameLogger.log_net("玩家连接 peer_id=%d" % peer_id)

func _on_peer_disconnected(peer_id: int) -> void:
	GameLogger.log_net("玩家断开 peer_id=%d" % peer_id)
	var player_name := "未知玩家"
	if players.has(peer_id) and players[peer_id].has("name"):
		player_name = players[peer_id]["name"]
	players.erase(peer_id)
	player_left.emit(peer_id)
	player_left_with_name.emit(peer_id, player_name)

	# 如果在游戏中，重新计算难度
	if lobby_state == LobbyState.PLAYING:
		_recalculate_difficulty()

	# 通知其他客户端
	if multiplayer.is_server():
		_broadcast_player_list.rpc()

func _on_connected_to_server() -> void:
	GameLogger.log_net("已连接到服务器")
	lobby_state = LobbyState.IN_LOBBY
	_reset_net_stats()
	server_connected.emit()
	# 向服务器注册自己
	_request_register.rpc_id(1, {
		"name": local_player_name,
	})

func _on_connection_failed() -> void:
	GameLogger.error("连接失败")
	_reset_net_stats()
	is_multiplayer = false
	lobby_state = LobbyState.IDLE
	connection_failed.emit()

func _on_server_disconnected() -> void:
	GameLogger.error("服务器断开")
	_reset_net_stats()
	players.clear()
	is_multiplayer = false
	lobby_state = LobbyState.IDLE
	server_disconnected.emit()
#endregion

#region 网络质量检测
func _on_net_probe_timer_timeout() -> void:
	if not is_multiplayer:
		return
	if multiplayer.is_server():
		return
	if lobby_state == LobbyState.IDLE:
		return

	_net_probe_seq += 1
	var now_ms := Time.get_ticks_msec()
	_net_probe_records.append({
		"seq": _net_probe_seq,
		"send_ms": now_ms,
		"acked": false,
		"rtt": -1,
	})
	while _net_probe_records.size() > NET_PROBE_WINDOW_SIZE * 2:
		_net_probe_records.pop_front()

	_net_probe_ping.rpc_id(1, _net_probe_seq, now_ms)
	_recalculate_net_stats()

func _reset_net_stats() -> void:
	_net_probe_seq = 0
	_net_probe_records.clear()
	_net_ping_ms = -1
	_net_packet_loss = 0.0
	net_stats_updated.emit(_net_ping_ms, _net_packet_loss)

func _recalculate_net_stats() -> void:
	var now_ms := Time.get_ticks_msec()
	var acked_rtts: Array[int] = []
	var eligible_count := 0
	var lost_count := 0

	var begin := maxi(0, _net_probe_records.size() - NET_PROBE_WINDOW_SIZE)
	for i in range(begin, _net_probe_records.size()):
		var rec: Dictionary = _net_probe_records[i]
		if rec.get("acked", false):
			eligible_count += 1
			acked_rtts.append(int(rec.get("rtt", -1)))
		elif now_ms - int(rec.get("send_ms", 0)) >= NET_PROBE_TIMEOUT_MS:
			eligible_count += 1
			lost_count += 1

	if not acked_rtts.is_empty():
		var sum_rtt := 0
		for rtt in acked_rtts:
			sum_rtt += maxi(rtt, 0)
		_net_ping_ms = int(round(float(sum_rtt) / float(acked_rtts.size())))
	else:
		_net_ping_ms = -1

	if eligible_count > 0:
		_net_packet_loss = clampf(float(lost_count) / float(eligible_count), 0.0, 1.0)
	else:
		_net_packet_loss = 0.0

	net_stats_updated.emit(_net_ping_ms, _net_packet_loss)

## Client -> Host 探测包
@rpc("any_peer", "unreliable")
func _net_probe_ping(seq: int, client_send_ms: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	_net_probe_pong.rpc_id(sender_id, seq, client_send_ms)

## Host -> Client 探测回包
@rpc("authority", "unreliable")
func _net_probe_pong(seq: int, client_send_ms: int) -> void:
	if multiplayer.is_server():
		return
	for rec in _net_probe_records:
		if int(rec.get("seq", -1)) == seq:
			rec["acked"] = true
			rec["rtt"] = maxi(0, Time.get_ticks_msec() - client_send_ms)
			break
	_recalculate_net_stats()

func get_net_ping_ms() -> int:
	return _net_ping_ms

func get_net_packet_loss() -> float:
	return _net_packet_loss
#endregion

#region 玩家注册（RPC）
## 客户端 → Host: 请求注册
@rpc("any_peer", "reliable")
func _request_register(info: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	if players.size() >= MAX_PLAYERS:
		# 拒绝：房满
		_register_rejected.rpc_id(peer_id, "房间已满")
		return

	var color_index = _next_color_index()
	_register_player(peer_id, {
		"name": info.get("name", "Player%d" % peer_id),
		"color_index": color_index,
		"is_ready": false,
		"is_card_chosen": false,
		"is_restart_voted": false,
	})
	# 将完整玩家列表广播给所有人
	_broadcast_player_list.rpc()

## Host → 所有人: 广播玩家列表
@rpc("authority", "call_local", "reliable")
func _broadcast_player_list() -> void:
	# 当 Host 端调用时，实际广播
	if multiplayer.is_server():
		_sync_player_list.rpc(players)

## Host → 所有人: 同步玩家列表
@rpc("authority", "call_local", "reliable")
func _sync_player_list(player_data: Dictionary) -> void:
	var old_ids = players.keys()
	players = player_data
	# 触发新加入信号
	for pid in players:
		if pid not in old_ids:
			player_joined.emit(pid, players[pid])
	# 通知 UI 刷新（准备状态等变化）
	player_list_updated.emit()

## Host → Client: 注册被拒绝
@rpc("authority", "reliable")
func _register_rejected(reason: String) -> void:
	push_warning("NetworkManager: 注册被拒绝: %s" % reason)
	disconnect_from_server()
	connection_failed.emit()

## 本地注册玩家
func _register_player(peer_id: int, info: Dictionary) -> void:
	players[peer_id] = info
	player_joined.emit(peer_id, info)

## 获取下一个可用颜色索引
func _next_color_index() -> int:
	var used := []
	for pid in players:
		used.append(players[pid].get("color_index", -1))
	for i in range(PLAYER_COLORS.size()):
		if i not in used:
			return i
	return 0
#endregion

#region 大厅准备逻辑
## 客户端/Host 本地: 切换准备状态
func toggle_ready() -> void:
	var my_id = multiplayer.get_unique_id()
	_set_ready.rpc_id(1, my_id, not players.get(my_id, {}).get("is_ready", false))

## → Host: 设置准备状态
@rpc("any_peer", "call_local", "reliable")
func _set_ready(peer_id: int, ready_state: bool) -> void:
	if not multiplayer.is_server():
		return
	# 验证 sender
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1  # 本地调用
	if sender != peer_id and sender != 1:
		return

	if players.has(peer_id):
		players[peer_id]["is_ready"] = ready_state
		_broadcast_player_list()
		_check_all_ready()

## 检查是否全员准备
func _check_all_ready() -> void:
	if players.size() < 2:
		return
	for pid in players:
		if not players[pid].get("is_ready", false):
			return
	all_players_ready.emit()
#endregion

#region 游戏启动（Host 调用）
## Host: 开始游戏
func start_game() -> void:
	if not multiplayer.is_server():
		return
	lobby_state = LobbyState.PLAYING
	_on_game_start.rpc(int(selected_game_mode))

## Host → 所有人: 游戏开始（携带游戏模式）
@rpc("authority", "call_local", "reliable")
func _on_game_start(game_mode_key: int) -> void:
	lobby_state = LobbyState.PLAYING
	selected_game_mode = game_mode_key as MainSceneRegistry.MainScenes
	game_started.emit()
#endregion

#region 选关同步
## Host → 所有人: 广播选定的关卡
@rpc("authority", "call_local", "reliable")
func broadcast_level_chosen(res_path: String, scene_key: int) -> void:
	## 重置所有玩家的选卡状态和重新开始投票状态
	for pid in players:
		players[pid]["is_card_chosen"] = false
		players[pid]["is_restart_voted"] = false
	lobby_state = LobbyState.CHOOSING
	var level_res = load(res_path)
	if level_res is ResourceLevelData:
		Global.game_para = level_res
		## 初始化选关数据（客户端需要）
		if not Global.game_para.save_game_name or Global.game_para.save_game_name.is_empty():
			Global.game_para.set_choose_level(Global.game_para.game_mode, 0, "mp")
	var game_scene = scene_key as MainSceneRegistry.MainScenes
	var scene_path = Global.main_scene_registry.MainScenesMap.get(game_scene, "")
	if scene_path != "":
		get_tree().change_scene_to_file(scene_path)
#endregion

#region 选卡同步
## 选卡完成通知（自动区分 Host/Client）
func notify_card_chosen() -> void:
	if is_server():
		_set_card_chosen(multiplayer.get_unique_id())
	else:
		_set_card_chosen.rpc_id(1, multiplayer.get_unique_id())

## → Host: 标记选卡完成
@rpc("any_peer", "call_local", "reliable")
func _set_card_chosen(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	if players.has(peer_id):
		players[peer_id]["is_card_chosen"] = true
		_broadcast_card_chosen_status.rpc(_build_vote_status("is_card_chosen"))
		_check_all_cards_chosen()

## 信号：选卡投票进度更新 (vote_status: Array[Dictionary])
## 每个元素: {"color_index": int, "voted": bool}
signal card_chosen_vote_updated(vote_status: Array)

## Host → 所有人: 广播选卡投票状态
@rpc("authority", "call_local", "reliable")
func _broadcast_card_chosen_status(vote_status: Array) -> void:
	card_chosen_vote_updated.emit(vote_status)

## 检查是否全员选卡完成
func _check_all_cards_chosen() -> void:
	for pid in players:
		if not players[pid].get("is_card_chosen", false):
			return
	# 全员选卡完成，开始游戏
	_on_all_cards_chosen.rpc()

## Host → 所有人: 全员选卡完成
@rpc("authority", "call_local", "reliable")
func _on_all_cards_chosen() -> void:
	EventBus.push_event("card_slot_norm_start_game")
#endregion

#region 重新开始投票
## 信号：所有玩家投票重新开始
signal all_restart_voted

## 重新开始投票通知（自动区分 Host/Client）
func notify_restart_vote() -> void:
	if is_server():
		_set_restart_vote(multiplayer.get_unique_id())
	else:
		_set_restart_vote.rpc_id(1, multiplayer.get_unique_id())

## → Host: 标记重新开始投票
@rpc("any_peer", "call_local", "reliable")
func _set_restart_vote(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# 验证 sender
	var sender = multiplayer.get_remote_sender_id()
	if sender == 0:
		sender = 1  # 本地调用
	if sender != peer_id and sender != 1:
		return

	if players.has(peer_id):
		players[peer_id]["is_restart_voted"] = true
		_broadcast_restart_vote_status.rpc(_build_vote_status("is_restart_voted"))
		_check_all_restart_votes()

## 信号：重新开始投票进度更新 (vote_status: Array[Dictionary])
## 每个元素: {"color_index": int, "voted": bool}
signal restart_vote_updated(vote_status: Array)

## Host → 所有人: 广播重新开始投票状态
@rpc("authority", "call_local", "reliable")
func _broadcast_restart_vote_status(vote_status: Array) -> void:
	restart_vote_updated.emit(vote_status)

## 构建投票状态数组，按 color_index 排序
func _build_vote_status(vote_key: String) -> Array:
	var result: Array = []
	for pid in players:
		result.append({
			"color_index": players[pid].get("color_index", 0),
			"voted": players[pid].get(vote_key, false),
		})
	result.sort_custom(func(a, b): return a["color_index"] < b["color_index"])
	return result

## 检查是否全员投票重新开始
func _check_all_restart_votes() -> void:
	for pid in players:
		if not players[pid].get("is_restart_voted", false):
			return
	# 全员同意重新开始
	_on_all_restart_voted.rpc()

## Host → 所有人: 全员投票同意重新开始
@rpc("authority", "call_local", "reliable")
func _on_all_restart_voted() -> void:
	EventBus.push_event("all_players_restart_game")
	all_restart_voted.emit()

## 重置重新开始投票状态（切换关卡时调用）
func reset_restart_votes() -> void:
	for pid in players:
		players[pid]["is_restart_voted"] = false

## 重置选卡投票状态（重新开始游戏时调用）
func reset_card_chosen_votes() -> void:
	for pid in players:
		players[pid]["is_card_chosen"] = false
#endregion

#region 难度缩放
## 获取僵尸数量倍率
func get_zombie_scale() -> float:
	if not is_multiplayer:
		return 1.0
	return 1.0 + (player_count - 1) * 0.5

## 获取阳光产生频率倍率（<1 表示更快）
func get_sun_freq_scale() -> float:
	if not is_multiplayer:
		return 1.0
	# 2人=0.7, 3人=0.5, 4人=0.4（间隔缩短，产量提高）
	return 1.0 / (1.0 + (player_count - 1) * 0.5)

## 获取起始阳光倍率
func get_start_sun_multiplier() -> float:
	if not is_multiplayer:
		return 1.0
	return player_count * 0.75

## 获取多人模式下的卡槽数量上限
## 1人=10, 2人=5, 3人=4, 4人=3
func get_max_card_slots() -> int:
	match player_count:
		1: return 10
		2: return 5
		3: return 4
		4: return 3
		_: return maxi(2, 10 / player_count)

## 重新计算难度（玩家断线时）
func _recalculate_difficulty() -> void:
	if not multiplayer.is_server():
		return
	# 实时更新不改已生成的僵尸，只影响后续波次
	print("NetworkManager: 重新计算难度，当前玩家数: %d" % player_count)
#endregion

#region 游戏内 RPC 转发

#region 种植请求
## 本地调用入口：自动区分 Host/Client
func local_request_plant(plant_type: int, row: int, col: int, is_imitater: bool = false) -> void:
	if is_server():
		request_plant(plant_type, row, col, is_imitater)
	else:
		request_plant.rpc_id(1, plant_type, row, col, is_imitater)

## 客户端 → Host: 请求种植
@rpc("any_peer", "reliable")
func request_plant(plant_type: int, row: int, col: int, is_imitater: bool = false) -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	if peer_id == 0:
		peer_id = 1  # 本地

	# 验证阳光、格子等
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return

	var plant_cell: PlantCell = main_game.plant_cell_manager.all_plant_cells[row][col]
	var sun_cost: int = Global.character_registry.get_plant_info(
		plant_type as CharacterRegistry.PlantType,
		CharacterRegistry.PlantInfoAttribute.SunCost
	)
	## 非普通卡槽模式（传送带/金币等）无需阳光检查
	var card_slot = main_game.card_manager.card_slot_battle
	var card_mode = main_game.card_manager.card_mode
	if card_mode == ConstLevelData.E_CardMode.Norm and (card_slot == null or card_slot.sun_value < sun_cost):
		_plant_rejected.rpc_id(peer_id, "阳光不足")
		return

	# 检查格子是否可种
	var plant_condition: ResourcePlantCondition = Global.character_registry.get_plant_info(
		plant_type as CharacterRegistry.PlantType,
		CharacterRegistry.PlantInfoAttribute.PlantConditionResource
	)
	if not plant_condition.judge_is_can_plant(plant_cell, plant_type as CharacterRegistry.PlantType):
		_plant_rejected.rpc_id(peer_id, "无法种植在此格子")
		return

	# 验证通过：普通模式扣除阳光并同步
	if card_mode == ConstLevelData.E_CardMode.Norm and card_slot:
		card_slot.sun_value -= sun_cost
		sync_sun_value.rpc(card_slot.sun_value)

	# 执行种植并广播（Host 生成随机动画速度，确保主客端动画同步）
	var init_speed := randf_range(0.9, 1.1)
	_execute_plant.rpc(plant_type, row, col, is_imitater, peer_id, init_speed)

## Host → 所有人: 执行种植
@rpc("authority", "call_local", "reliable")
func _execute_plant(plant_type: int, row: int, col: int, is_imitater: bool, owner_id: int, init_speed: float = -1.0) -> void:
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var plant_cell: PlantCell = main_game.plant_cell_manager.all_plant_cells[row][col]
	var plant = plant_cell.create_plant(plant_type as CharacterRegistry.PlantType, is_imitater)
	if plant is Plant000Base:
		## 修复植物数据: 如果 owner_id != 1（默认值），需要把记录从1转移到正确的owner_id
		if owner_id != 1:
			var plant_cell_manager = main_game.plant_cell_manager
			if plant_cell_manager.curr_plant_num.has(1):
				if plant_cell_manager.curr_plant_num[1].has(plant_type):
					plant_cell_manager.curr_plant_num[1][plant_type] -= 1
					if plant_cell_manager.curr_plant_num[1][plant_type] < 0:
						plant_cell_manager.curr_plant_num[1].erase(plant_type)
			if not plant_cell_manager.curr_plant_num.has(owner_id):
				plant_cell_manager.curr_plant_num[owner_id] = {}
			plant_cell_manager.curr_plant_num[owner_id][plant_type] = plant_cell_manager.curr_plant_num[owner_id].get(plant_type, 0) + 1
		
		plant.owner_peer_id = owner_id
		## 同步动画随机速度，防止主客端动画不一致
		if init_speed > 0:
			plant.network_init_speed = init_speed
		GameLogger.log_net("_execute_plant: 种植 type=%d row=%d col=%d owner=%d" % [plant_type, row, col, owner_id])
		
		## 设置 owner_peer_id 后更新费用（确保客户端能获取正确的玩家ID）
		main_game.plant_cell_manager.trigger_card_purple_sun_cost_update()
	
	## 发出种植成功信号，通知所有客户端（包括请求者）可以进行冷却
	plant_success_confirmed.emit(plant_type, row, col, owner_id)

## Host → Client: 种植被拒绝
@rpc("authority", "reliable")
func _plant_rejected(reason: String) -> void:
	SoundManager.play_other_SFX("buzzer")
	print("NetworkManager: 种植被拒绝: %s" % reason)
	## 发出plant_rejected信号，通知客户端取消冷却
	plant_rejected.emit(reason)
#endregion

#region 玉米投手黄油同步
## Host → 客户端: 广播玉米投手的黄油/玉米选择
@rpc("authority", "reliable")
func broadcast_corn_butter_choice(row: int, col: int, is_butter: bool) -> void:
	if multiplayer.is_server():
		return
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var plant_cell: PlantCell = main_game.plant_cell_manager.all_plant_cells[row][col]
	var plant = plant_cell.plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Norm)
	if is_instance_valid(plant) and plant is Plant035CornPult:
		var attack_comp = plant.attack_component
		if attack_comp is AttackComponentBulletCorn:
			attack_comp._apply_butter_choice(is_butter)
#endregion

#region 铲除请求
## 本地调用入口：自动区分 Host/Client
func local_request_shovel(row: int, col: int) -> void:
	if is_server():
		request_shovel(row, col)
	else:
		request_shovel.rpc_id(1, row, col)

## 客户端 → Host: 请求铲除
@rpc("any_peer", "reliable")
func request_shovel(row: int, col: int) -> void:
	if not multiplayer.is_server():
		return
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var plant_cell: PlantCell = main_game.plant_cell_manager.all_plant_cells[row][col]
	if not plant_cell.has_plant():
		return
	# 验证通过，铲除并广播
	_execute_shovel.rpc(row, col)

## Host → 所有人: 执行铲除
@rpc("authority", "call_local", "reliable")
func _execute_shovel(row: int, col: int) -> void:
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var plant_cell: PlantCell = main_game.plant_cell_manager.all_plant_cells[row][col]
	plant_cell.shovel_plant()
#endregion

#region 阳光同步
## Host → 所有人: 同步阳光值
@rpc("authority", "call_local", "reliable")
func sync_sun_value(value: int) -> void:
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	if main_game.card_manager.card_slot_battle:
		main_game.card_manager.card_slot_battle.sun_value = value

## Host → 客户端: 生成天降阳光（不含 call_local，Host 已在 spawn_sun 中创建）
@rpc("authority", "reliable")
func broadcast_sun_spawn(sun_id: int, pos_x: float, pos_y_start: float, pos_y_target: float) -> void:
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	main_game.day_suns_manager.spawn_sun_from_network(sun_id, Vector2(pos_x, pos_y_start), pos_y_target)

## Host → 客户端: 咖啡豆唤醒睡眠植物
@rpc("authority", "reliable")
func broadcast_coffee_bean_awake(row: int, col: int) -> void:
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var plant_cell: PlantCell = main_game.plant_cell_manager.all_plant_cells[row][col]
	plant_cell.coffee_bean_awake_up()

## 本地调用入口：收集阳光
func local_request_collect_sun(sun_id: int) -> void:
	if is_server():
		var main_game = Global.main_game
		if is_instance_valid(main_game):
			main_game.day_suns_manager.try_collect_sun_network(sun_id, 1)
	else:
		request_collect_sun.rpc_id(1, sun_id)

## 客户端 → Host: 请求收集阳光
@rpc("any_peer", "reliable")
func request_collect_sun(sun_id: int) -> void:
	if not multiplayer.is_server():
		return
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	main_game.day_suns_manager.try_collect_sun_network(sun_id, multiplayer.get_remote_sender_id())

## Host → 客户端: 阳光被收集（不含 call_local，Host 已在 try_collect 中处理）
@rpc("authority", "reliable")
func broadcast_sun_collected(sun_id: int, new_sun_value: int, collector_peer_id: int = -1, sun_amount: int = 0) -> void:
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	main_game.day_suns_manager.on_sun_collected_network(sun_id, collector_peer_id, sun_amount)
	if main_game.card_manager.card_slot_battle:
		main_game.card_manager.card_slot_battle.sun_value = new_sun_value

## Host → 客户端: 植物产生阳光（向日葵等）
@rpc("authority", "reliable")
func broadcast_plant_sun_spawn(sun_id: int, pos_x: float, pos_y: float, rand_x: float, sun_val: int = 25, plant_row: int = -1, plant_col: int = -1) -> void:
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	main_game.day_suns_manager.spawn_plant_sun_from_network(sun_id, Vector2(pos_x, pos_y), rand_x, sun_val)
	## 在对应植物上播放发光动画
	if plant_row >= 0 and plant_col >= 0:
		var plant_cell: PlantCell = main_game.plant_cell_manager.all_plant_cells[plant_row][plant_col]
		var plant = plant_cell.plant_in_cell.get(CharacterRegistry.PlacePlantInCell.Norm)
		if is_instance_valid(plant):
			var create_sun_comp: CreateSunComponent = plant.get_node_or_null("CreateSunComponent")
			if create_sun_comp:
				create_sun_comp.play_glow_only()
#endregion

#region 僵尸同步
## Host → 客户端: 生成僵尸（含网络 ID）
@rpc("authority", "reliable")
func broadcast_zombie_spawn(zombie_type: int, lane: int, pos_x: float, pos_y: float, net_id: int = -1, anim_statuses: Array = []) -> void:
	# 仅客户端处理（Host 已经本地生成过了）
	if multiplayer.is_server():
		return
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var zombie_init_para := {
		Zombie000Base.E_ZInitAttr.CharacterInitType: Character000Base.E_CharacterInitType.IsNorm,
		Zombie000Base.E_ZInitAttr.Lane: lane,
	}
	var zombie = main_game.zombie_manager.create_norm_zombie(
		zombie_type as CharacterRegistry.ZombieType,
		main_game.zombie_manager.all_zombie_rows[lane],
		zombie_init_para,
		Vector2(pos_x, pos_y)
	)
	if zombie:
		## 客户端赋值 Host 分配的 network_id
		if net_id >= 0:
			zombie.network_id = net_id
			main_game.zombie_manager._zombie_by_net_id[net_id] = zombie
		## 同步动画状态（普通僵尸随机外观）
		if anim_statuses.size() == 3 and zombie is Zombie001Norm:
			zombie.idle_status = anim_statuses[0]
			zombie.walk_status = anim_statuses[1]
			zombie.death_status = anim_statuses[2]

## Host → 客户端: 僵尸死亡
@rpc("authority", "reliable")
func broadcast_zombie_death(net_id: int) -> void:
	if multiplayer.is_server():
		return
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		GameLogger.warn("broadcast_zombie_death: main_game 无效, net_id=%d" % net_id)
		return
	var zombie = main_game.zombie_manager.get_zombie_by_net_id(net_id)
	if not is_instance_valid(zombie):
		GameLogger.warn("broadcast_zombie_death: 找不到僵尸或已释放, net_id=%d" % net_id)
		return
	if zombie.is_death:
		GameLogger.log_net("broadcast_zombie_death: 僵尸已死亡,跳过, net_id=%d" % net_id)
		return
	## 恢复正常死亡阈值（客户端傀儡模式下 death_hp 被设为 -99999）
	zombie.hp_component.set_death_hp(0)
	zombie.hp_component.Hp_loss_death(false)
	## 安全兜底：如果 sync_zombie_states 已将 HP 同步为 0，
	## Hp_loss_death(0) 中所有 >0 分支均不进入，is_death 不会被设置。
	## 此时直接触发死亡流程，确保死亡动画正常播放。
	if not zombie.is_death:
		print("[Net] broadcast_zombie_death 兜底触发 character_death, net_id=%d" % net_id)
		zombie.character_death()

## Host → 客户端: 僵尸被地刺扎死（雪橇车/投石车专用）
@rpc("authority", "reliable")
func broadcast_zombie_caltrop(net_id: int) -> void:
	if multiplayer.is_server():
		return
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var zombie = main_game.zombie_manager.get_zombie_by_net_id(net_id)
	if not is_instance_valid(zombie) or zombie.is_death:
		return
	## 恢复正常死亡阈值（客户端傀儡模式下 death_hp 被设为 -99999）
	zombie.hp_component.set_death_hp(0)
	zombie.be_caltrop()

## Host → 客户端: 僵尸被魅惑
@rpc("authority", "reliable")
func broadcast_zombie_hypno(net_id: int) -> void:
	if multiplayer.is_server():
		return
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var zombie = main_game.zombie_manager.get_zombie_by_net_id(net_id)
	if is_instance_valid(zombie) and not zombie.is_death and not zombie.is_hypno:
		zombie.be_hypno()

## Host → 客户端: 僵尸被黄油命中
@rpc("authority", "reliable")
func broadcast_zombie_butter(net_id: int, butter_time: float) -> void:
	if multiplayer.is_server():
		return
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var zombie = main_game.zombie_manager.get_zombie_by_net_id(net_id)
	if is_instance_valid(zombie) and not zombie.is_death:
		zombie.be_butter(butter_time)

## Host → 客户端: 植物死亡
@rpc("authority", "reliable")
func broadcast_plant_death(row: int, col: int) -> void:
	if multiplayer.is_server():
		return
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var plant_cell: PlantCell = main_game.plant_cell_manager.all_plant_cells[row][col]
	if plant_cell.has_plant():
		var plant = plant_cell.plant_in_cell[CharacterRegistry.PlacePlantInCell.Norm]
		if is_instance_valid(plant) and not plant.is_death:
			plant.hp_component.Hp_loss_death()

## Host → 所有人: 僵尸状态更新
@rpc("authority", "unreliable")
func sync_zombie_states(zombie_data: Array) -> void:
	if multiplayer.is_server():
		return
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var zm = main_game.zombie_manager
	## zombie_data: Array of [net_id, pos_x, pos_y, hp, hp_a1, hp_a2, is_attack]
	for entry in zombie_data:
		var net_id: int = entry[0]
		var zombie = zm.get_zombie_by_net_id(net_id)
		if not is_instance_valid(zombie) or zombie.is_death:
			continue
		zombie.apply_network_state(
			entry[1],  # pos_x
			entry[2],  # pos_y
			entry[3],  # hp
			entry[4],  # hp_armor1
			entry[5],  # hp_armor2
			entry[6],  # is_attack
		)
#endregion

#region 游戏状态同步
## Host → 所有人: 游戏进度更新
@rpc("authority", "call_local", "reliable")
func sync_game_progress(progress: int) -> void:
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	if not multiplayer.is_server():
		main_game.main_game_progress = progress as MainGameManager.E_MainGameProgress

## Host → 所有人: 游戏胜利（直接调用 _do_create_trophy，不走 EventBus，避免重入）
@rpc("authority", "call_local", "reliable")
func broadcast_game_win(trophy_pos_x: float, trophy_pos_y: float) -> void:
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	main_game._do_create_trophy(Vector2(trophy_pos_x, trophy_pos_y))

## 任意一方 → 所有人: 捡起奖杯（任意玩家捡起后，其他玩家自动捡起）
@rpc("any_peer", "call_local", "reliable")
func broadcast_trophy_pickup() -> void:
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	## 找到场景中的奖杯节点并执行捡起
	var trophy = main_game.canvas_layer_temp.get_node_or_null("Trophy")
	if trophy and trophy is Trophy:
		trophy._do_pickup()

## Host → 所有人: 游戏失败
@rpc("authority", "call_local", "reliable")
func broadcast_game_lose() -> void:
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	main_game._on_game_lose_from_network()

## Host → 所有人: 波次更新
@rpc("authority", "call_local", "reliable")
func sync_wave_progress(_curr_wave: int, _max_wave: int) -> void:
	# 客户端更新进度条
	pass

## Host → 客户端: 小推车启动
@rpc("authority", "reliable")
func broadcast_lawn_mower_start(lane: int) -> void:
	if multiplayer.is_server():
		return
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var gim = main_game.game_item_manager.gim_lawn_mover
	if lane >= 0 and lane < gim.all_lawn_movers.size():
		var mower = gim.all_lawn_movers[lane]
		if is_instance_valid(mower) and not mower.is_moving:
			mower._start_mower_from_network()

## Host → 客户端: 僵尸被小推车碾压
@rpc("authority", "reliable")
func broadcast_zombie_mowered(net_id: int, lane: int) -> void:
	if multiplayer.is_server():
		return
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var zombie = main_game.zombie_manager.get_zombie_by_net_id(net_id)
	if not is_instance_valid(zombie) or zombie.is_death:
		return
	var mower: LawnMover = null
	var gim = main_game.game_item_manager.gim_lawn_mover
	if lane >= 0 and lane < gim.all_lawn_movers.size():
		mower = gim.all_lawn_movers[lane]
	## 恢复正常死亡阈值（客户端傀儡模式下 death_hp 被设为 -99999）
	zombie.hp_component.set_death_hp(0)
	if is_instance_valid(mower):
		zombie.be_mowered_run(mower)
	else:
		zombie.character_death()
#endregion

#endregion

#region 工具方法
## 是否为 Host（服务器）
func is_server() -> bool:
	if not is_multiplayer:
		return true
	return multiplayer.is_server()

## 获取本地 peer_id
func get_local_peer_id() -> int:
	if not is_multiplayer:
		return 1
	return multiplayer.get_unique_id()

## 获取玩家颜色
func get_player_color(peer_id: int) -> Color:
	if players.has(peer_id):
		var idx = players[peer_id].get("color_index", 0)
		return PLAYER_COLORS[idx]
	return Color.WHITE

## 获取玩家名称
func get_player_name(peer_id: int) -> String:
	if players.has(peer_id):
		return players[peer_id].get("name", "Unknown")
	return "Unknown"
#endregion

#region 光标同步

#region 墓碑同步
## Host → 客户端: 广播墓碑生成位置
@rpc("authority", "reliable")
func broadcast_tombstone_positions(pos_array: Array[int]) -> void:
	if multiplayer.is_server():
		return
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var positions: Array[Vector2i] = []
	for i in range(0, pos_array.size(), 2):
		positions.append(Vector2i(pos_array[i], pos_array[i + 1]))
	main_game.plant_cell_manager.tomb_stone_manager.create_tombstone_from_network(positions)

## Host → 客户端: 广播墓碑被吃掉（墓碑吞噬者）
@rpc("authority", "reliable")
func broadcast_tombstone_death(row: int, col: int) -> void:
	if multiplayer.is_server():
		return
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var plant_cell: PlantCell = main_game.plant_cell_manager.all_plant_cells[row][col]
	if is_instance_valid(plant_cell.tombstone):
		plant_cell.tombstone.tombstone_death()
#endregion

#region 光标同步
## 任意玩家 → 所有人: 广播光标状态
@rpc("any_peer", "unreliable")
func sync_cursor_state(peer_id: int, state: Dictionary) -> void:
	# 由 MultiplayerCursorManager 处理
	EventBus.push_event("remote_cursor_update", [peer_id, state])

## 本地调用入口：发送标点
func local_send_ping_marker(world_pos: Vector2) -> void:
	if not is_multiplayer:
		return
	if is_server():
		broadcast_ping_marker.rpc(multiplayer.get_unique_id(), world_pos.x, world_pos.y)
	else:
		request_ping_marker.rpc_id(1, world_pos.x, world_pos.y)

## 客户端 → Host: 请求发送标点
@rpc("any_peer", "unreliable")
func request_ping_marker(pos_x: float, pos_y: float) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id <= 0:
		return
	broadcast_ping_marker.rpc(sender_id, pos_x, pos_y)

## Host → 所有人: 广播标点
@rpc("authority", "call_local", "unreliable")
func broadcast_ping_marker(peer_id: int, pos_x: float, pos_y: float) -> void:
	EventBus.push_event("remote_ping_marker", [peer_id, Vector2(pos_x, pos_y)])
#endregion
