extends Node2D
## 多人模式光标管理器
## 显示其他玩家的光标位置、手持植物预览、铲子图标和格子高亮
## 参考杀戮尖塔2合作模式：队友光标 + 手中卡牌实时可见

class_name MultiplayerCursorManager

## 远程光标节点 {peer_id: Node2D}
var remote_cursors: Dictionary = {}

## 本地光标同步计时器
var sync_timer: Timer

## 光标同步频率 (10Hz)
const SYNC_INTERVAL := 0.1
const NET_HUD_UPDATE_INTERVAL := 0.5
const PING_KEEP_TIME := 0.5

## 铲子纹理
const SHOVEL_TEXTURE := preload("res://assets/image/ui/ui_card/Shovel.png")

## 植物预览缓存 {PlantType: Node2D(原型)} — 避免重复实例化
var _plant_preview_cache: Dictionary = {}

## 每个 peer 当前高亮的格子 {peer_id: Vector2i}
var _peer_highlighted_cells: Dictionary = {}

## 每个 peer 当前显示的植物类型 {peer_id: int}
var _peer_held_plant_type: Dictionary = {}

## 每个 peer 当前的格子植物虚影 {peer_id: {node, plant_type, row, col}}
var _peer_cell_ghosts: Dictionary = {}

## 光标插值用 Tween {peer_id: Tween}
var _peer_tweens: Dictionary = {}

## 每个 peer 当前标点节点 {peer_id: Node2D}
var _peer_ping_nodes: Dictionary = {}

## 网络状态 HUD
var _net_hud_layer: CanvasLayer = null
var _net_status_label: Label = null
var _disconnect_label: Label = null
var _net_hud_timer: Timer = null

func _ready() -> void:
	if not NetworkManager.is_multiplayer:
		return

	# 订阅远端光标更新事件
	EventBus.subscribe("remote_cursor_update", _on_remote_cursor_update)
	EventBus.subscribe("remote_ping_marker", _on_remote_ping_marker)
	NetworkManager.player_left.connect(_on_player_left)

	# 创建本地光标同步计时器
	sync_timer = Timer.new()
	sync_timer.wait_time = SYNC_INTERVAL
	sync_timer.autostart = true
	sync_timer.timeout.connect(_on_sync_timer_timeout)
	add_child(sync_timer)

	_create_network_hud()
	NetworkManager.net_stats_updated.connect(_on_net_stats_updated)
	NetworkManager.server_disconnected.connect(_on_host_disconnected)
	NetworkManager.connection_failed.connect(_on_host_disconnected)
	NetworkManager.player_left_with_name.connect(_on_client_disconnected)

func _exit_tree() -> void:
	if EventBus.has_signal("remote_cursor_update"):
		EventBus.unsubscribe("remote_cursor_update", _on_remote_cursor_update)
	if EventBus.has_signal("remote_ping_marker"):
		EventBus.unsubscribe("remote_ping_marker", _on_remote_ping_marker)
	if NetworkManager.net_stats_updated.is_connected(_on_net_stats_updated):
		NetworkManager.net_stats_updated.disconnect(_on_net_stats_updated)
	if NetworkManager.server_disconnected.is_connected(_on_host_disconnected):
		NetworkManager.server_disconnected.disconnect(_on_host_disconnected)
	if NetworkManager.connection_failed.is_connected(_on_host_disconnected):
		NetworkManager.connection_failed.disconnect(_on_host_disconnected)
	if NetworkManager.player_left_with_name.is_connected(_on_client_disconnected):
		NetworkManager.player_left_with_name.disconnect(_on_client_disconnected)
	# 清除所有虚影
	_peer_highlighted_cells.clear()
	for pid in _peer_cell_ghosts.keys():
		_hide_cell_ghost(pid)
	for pid in _peer_ping_nodes.keys():
		if is_instance_valid(_peer_ping_nodes[pid]):
			_peer_ping_nodes[pid].queue_free()
	_peer_ping_nodes.clear()

func _create_network_hud() -> void:
	_net_hud_layer = CanvasLayer.new()
	_net_hud_layer.name = "NetworkHudLayer"
	add_child(_net_hud_layer)

	var root = Control.new()
	root.name = "NetworkHudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_net_hud_layer.add_child(root)

	_net_status_label = Label.new()
	_net_status_label.name = "NetworkStatusLabel"
	_net_status_label.position = Vector2(16, 12)
	_net_status_label.add_theme_font_size_override("font_size", 14)
	_net_status_label.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	root.add_child(_net_status_label)

	_disconnect_label = Label.new()
	_disconnect_label.name = "DisconnectLabel"
	_disconnect_label.position = Vector2(16, 34)
	_disconnect_label.add_theme_font_size_override("font_size", 18)
	_disconnect_label.add_theme_color_override("font_color", Color(1.0, 0.1, 0.1))
	_disconnect_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_disconnect_label.add_theme_constant_override("outline_size", 3)
	_disconnect_label.text = ""
	_disconnect_label.visible = false
	root.add_child(_disconnect_label)

	_net_hud_timer = Timer.new()
	_net_hud_timer.wait_time = NET_HUD_UPDATE_INTERVAL
	_net_hud_timer.autostart = true
	_net_hud_timer.timeout.connect(_update_net_hud_text)
	add_child(_net_hud_timer)

	_update_net_hud_text()

func _update_net_hud_text() -> void:
	if not is_instance_valid(_net_status_label):
		return
	if NetworkManager.is_server():
		_net_status_label.text = "联机状态: Host"
		return

	var ping_ms = NetworkManager.get_net_ping_ms()
	var loss = NetworkManager.get_net_packet_loss() * 100.0
	var ping_text = "--"
	if ping_ms >= 0:
		ping_text = "%dms" % ping_ms
	_net_status_label.text = "Ping: %s  丢包: %.1f%%" % [ping_text, loss]

func _on_net_stats_updated(_ping_ms: int, _packet_loss: float) -> void:
	_update_net_hud_text()

## 客户端：主机断开连接 → 显示提示并自动返回主菜单
func _on_host_disconnected() -> void:
	if is_instance_valid(_disconnect_label):
		_disconnect_label.text = "主机已断开连接，3秒后返回主菜单..."
		_disconnect_label.visible = true
	NetworkManager.disconnect_from_server()
	# 3 秒后自动返回主菜单
	var timer := get_tree().create_timer(3.0)
	timer.timeout.connect(func():
		TreePauseManager.end_tree_pause_clear_all_pause_factors()
		Global.time_scale = 1.0
		Engine.time_scale = Global.time_scale
		get_tree().change_scene_to_file(Global.main_scene_registry.MainScenesMap[MainSceneRegistry.MainScenes.StartMenu])
	)

## 主机端：客户端断开连接 → 显示提示
func _on_client_disconnected(peer_id: int, player_name: String) -> void:
	if not NetworkManager.is_server():
		return
	if is_instance_valid(_disconnect_label):
		_disconnect_label.text = "玩家 \"%s\" 已断开连接" % player_name
		_disconnect_label.visible = true
		# 5 秒后自动隐藏提示
		var timer := get_tree().create_timer(5.0)
		timer.timeout.connect(func():
			if is_instance_valid(_disconnect_label):
				_disconnect_label.visible = false
		)

#region 本地光标状态发送
## 定时发送本地光标状态
func _on_sync_timer_timeout() -> void:
	if not NetworkManager.is_multiplayer:
		return

	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	# 只在游戏阶段同步光标
	if main_game.main_game_progress != MainGameManager.E_MainGameProgress.MAIN_GAME:
		return

	var local_pos = get_global_mouse_position()
	var hand_manager = main_game.hand_manager
	var held_type = "none"
	var held_plant_type = 0
	var hovered_row = -1
	var hovered_col = -1

	match hand_manager.curr_hm_status:
		HandManager.E_HandManagerStatus.Character:
			if hand_manager.hm_character.curr_card:
				held_type = "plant"
				held_plant_type = hand_manager.hm_character.curr_card.card_plant_type
		HandManager.E_HandManagerStatus.Item:
			held_type = "shovel"

	if hand_manager.curr_plant_cell:
		hovered_row = hand_manager.curr_plant_cell.row_col.x
		hovered_col = hand_manager.curr_plant_cell.row_col.y

	var state = {
		"pos_x": local_pos.x,
		"pos_y": local_pos.y,
		"hovered_row": hovered_row,
		"hovered_col": hovered_col,
		"held_type": held_type,
		"held_plant_type": held_plant_type,
	}

	var peer_id = multiplayer.get_unique_id()
	NetworkManager.sync_cursor_state.rpc(peer_id, state)
#endregion

#region 远端光标更新
## 远端光标状态更新
func _on_remote_cursor_update(peer_id: int, state: Dictionary) -> void:
	# 不显示自己的光标
	if peer_id == multiplayer.get_unique_id():
		return

	if not remote_cursors.has(peer_id):
		_create_remote_cursor(peer_id)

	var cursor_node: Node2D = remote_cursors[peer_id]

	# 1. 插值移动光标位置
	var target_pos = Vector2(state.get("pos_x", 0), state.get("pos_y", 0))
	# 先杀旧 tween 防止叠加
	if _peer_tweens.has(peer_id) and is_instance_valid(_peer_tweens[peer_id]):
		_peer_tweens[peer_id].kill()
	var tween = cursor_node.create_tween()
	tween.tween_property(cursor_node, "global_position", target_pos, SYNC_INTERVAL).set_trans(Tween.TRANS_LINEAR)
	_peer_tweens[peer_id] = tween

	# 2. 更新手持状态显示（植物预览 / 铲子 / 空闲）
	var held_type: String = state.get("held_type", "none")
	var held_plant_type: int = state.get("held_plant_type", 0)
	_update_held_display(cursor_node, peer_id, held_type, held_plant_type)

	# 3. 更新玩家名标签
	var label: Label = cursor_node.get_node("NameLabel")
	label.text = NetworkManager.get_player_name(peer_id)

	# 4. 更新悬停格子高亮 / 植物虚影
	var hovered_row: int = state.get("hovered_row", -1)
	var hovered_col: int = state.get("hovered_col", -1)
	_update_cell_highlight(peer_id, hovered_row, hovered_col, held_type, held_plant_type)
#endregion

#region 标点显示
func _on_remote_ping_marker(peer_id: int, world_pos: Vector2) -> void:
	if peer_id <= 0:
		return

	if _peer_ping_nodes.has(peer_id) and is_instance_valid(_peer_ping_nodes[peer_id]):
		_peer_ping_nodes[peer_id].queue_free()

	var marker_root = Node2D.new()
	marker_root.name = "PingMarker_%d" % peer_id
	marker_root.global_position = world_pos
	marker_root.z_index = 180
	marker_root.modulate = Color(1, 1, 1, 0)
	add_child(marker_root)

	var color = NetworkManager.get_player_color(peer_id)

	var marker = Label.new()
	marker.text = "!"
	marker.position = Vector2(-6, -30)
	marker.add_theme_font_size_override("font_size", 36)
	marker.add_theme_color_override("font_color", color)
	marker_root.add_child(marker)

	var name_label = Label.new()
	name_label.text = NetworkManager.get_player_name(peer_id)
	name_label.position = Vector2(-40, -46)
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", color)
	marker_root.add_child(name_label)

	_peer_ping_nodes[peer_id] = marker_root

	var tween = create_tween()
	tween.tween_property(marker_root, "modulate:a", 1.0, 0.08)
	tween.parallel().tween_property(marker_root, "scale", Vector2(1.15, 1.15), 0.12).from(Vector2(0.35, 0.35))
	tween.tween_interval(PING_KEEP_TIME)
	tween.tween_property(marker_root, "modulate:a", 0.0, 0.22)
	tween.finished.connect(func():
		if is_instance_valid(marker_root):
			marker_root.queue_free()
		if _peer_ping_nodes.get(peer_id, null) == marker_root:
			_peer_ping_nodes.erase(peer_id)
	)
#endregion

#region 光标节点创建
## 创建远程光标节点
func _create_remote_cursor(peer_id: int) -> void:
	var cursor = Node2D.new()
	cursor.z_index = 100
	cursor.name = "RemoteCursor_%d" % peer_id
	var player_color = NetworkManager.get_player_color(peer_id)

	# --- 光标箭头（三角形 Polygon2D，带玩家颜色）---
	var arrow = Polygon2D.new()
	arrow.name = "CursorArrow"
	# 小三角箭头：顶点(0,0)→左下→右
	arrow.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(0, 16), Vector2(5, 13), Vector2(10, 20), Vector2(13, 18), Vector2(8, 11), Vector2(12, 8)
	])
	arrow.color = player_color
	cursor.add_child(arrow)

	# --- 植物预览容器 ---
	var plant_preview = Node2D.new()
	plant_preview.name = "PlantPreview"
	plant_preview.position = Vector2(14, 2)
	plant_preview.visible = false
	cursor.add_child(plant_preview)

	# --- 铲子图标 ---
	var shovel_sprite = Sprite2D.new()
	shovel_sprite.name = "ShovelIcon"
	shovel_sprite.texture = SHOVEL_TEXTURE
	shovel_sprite.scale = Vector2(0.5, 0.5)
	shovel_sprite.position = Vector2(20, 10)
	shovel_sprite.modulate = Color(player_color, 0.8)
	shovel_sprite.visible = false
	cursor.add_child(shovel_sprite)

	# --- 玩家名标签 ---
	var label = Label.new()
	label.name = "NameLabel"
	label.position = Vector2(14, -14)
	label.text = NetworkManager.get_player_name(peer_id)
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", player_color)
	label.modulate.a = 0.75
	cursor.add_child(label)

	add_child(cursor)
	remote_cursors[peer_id] = cursor
#endregion

#region 手持状态显示
## 更新远端光标的手持状态显示
func _update_held_display(cursor: Node2D, peer_id: int, held_type: String, plant_type: int) -> void:
	var plant_preview: Node2D = cursor.get_node("PlantPreview")
	var shovel_icon: Sprite2D = cursor.get_node("ShovelIcon")

	match held_type:
		"plant":
			shovel_icon.visible = false
			_show_plant_preview(plant_preview, peer_id, plant_type)
		"shovel":
			shovel_icon.visible = true
			_clear_plant_preview(plant_preview, peer_id)
		_:
			shovel_icon.visible = false
			_clear_plant_preview(plant_preview, peer_id)

## 显示植物预览
func _show_plant_preview(container: Node2D, peer_id: int, plant_type: int) -> void:
	# 如果已经是同一种植物，跳过
	if _peer_held_plant_type.get(peer_id, -1) == plant_type:
		container.visible = true
		return

	# 清除旧预览
	for child in container.get_children():
		child.queue_free()

	# 从 AllCards 获取植物卡片的静态角色图
	var card: Card = AllCards.all_plant_card_prefabs.get(plant_type as CharacterRegistry.PlantType)
	if card and is_instance_valid(card) and is_instance_valid(card.character_static):
		var preview = card.character_static.duplicate()
		preview.modulate.a = 0.55
		preview.scale = Vector2(0.65, 0.65)
		container.add_child(preview)
		container.visible = true
	else:
		container.visible = false

	_peer_held_plant_type[peer_id] = plant_type

## 清除植物预览
func _clear_plant_preview(container: Node2D, peer_id: int) -> void:
	container.visible = false
	_peer_held_plant_type.erase(peer_id)
	for child in container.get_children():
		child.queue_free()
#endregion

#region 植物虚影
## 更新悬停格子植物虚影
func _update_cell_highlight(peer_id: int, row: int, col: int, held_type: String, held_plant_type: int) -> void:
	# 格子变化时清除旧虚影
	if _peer_highlighted_cells.has(peer_id):
		var old = _peer_highlighted_cells[peer_id]
		if old.x != row or old.y != col:
			_hide_cell_ghost(peer_id)
			_peer_highlighted_cells.erase(peer_id)

	# 无有效悬停格子
	if row < 0 or col < 0:
		_hide_cell_ghost(peer_id)
		return

	# 持有植物 → 显示植物虚影
	if held_type == "plant" and held_plant_type > 0:
		_show_cell_ghost(peer_id, row, col, held_plant_type)
	else:
		_hide_cell_ghost(peer_id)

	_peer_highlighted_cells[peer_id] = Vector2i(row, col)
## 显示远端玩家的植物虚影（和本机种植预览一样的半透明植物）
func _show_cell_ghost(peer_id: int, row: int, col: int, plant_type: int) -> void:
	# 如果已有相同的虚影，跳过
	if _peer_cell_ghosts.has(peer_id):
		var info = _peer_cell_ghosts[peer_id]
		if info["plant_type"] == plant_type and info["row"] == row and info["col"] == col:
			return
		_hide_cell_ghost(peer_id)

	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var pcm = main_game.plant_cell_manager
	if row < 0 or col < 0 or row >= pcm.row_col.x or col >= pcm.row_col.y:
		return
	var cell: PlantCell = pcm.all_plant_cells[row][col]

	# 获取植物卡片
	var card: Card = AllCards.all_plant_card_prefabs.get(plant_type as CharacterRegistry.PlantType)
	if not card or not is_instance_valid(card) or not is_instance_valid(card.character_static):
		return

	# 创建虚影 —— 和本机一样：取 character_static 子节点的副本
	var source = card.character_static.duplicate()
	var ghost: Node2D
	if source.get_child_count() > 0:
		source.get_child(0).scale = Vector2.ONE
		ghost = source.get_child(0).duplicate()
		source.free()
	else:
		ghost = source
	ghost.modulate.a = 0.5

	# 获取植物放置位置
	var plant_condition = Global.character_registry.get_plant_info(
		plant_type as CharacterRegistry.PlantType,
		CharacterRegistry.PlantInfoAttribute.PlantConditionResource
	)
	var place_pos := CharacterRegistry.PlacePlantInCell.Norm
	if plant_condition:
		place_pos = plant_condition.place_plant_in_cell

	add_child(ghost)
	ghost.global_position = cell.get_new_plant_static_shadow_global_position(place_pos)

	_peer_cell_ghosts[peer_id] = {"node": ghost, "plant_type": plant_type, "row": row, "col": col}

## 隐藏远端玩家的植物虚影
func _hide_cell_ghost(peer_id: int) -> void:
	if _peer_cell_ghosts.has(peer_id):
		var info = _peer_cell_ghosts[peer_id]
		if is_instance_valid(info["node"]):
			info["node"].queue_free()
		_peer_cell_ghosts.erase(peer_id)
#endregion

#region 玩家离开
## 玩家离开时移除光标和高亮
func _on_player_left(peer_id: int) -> void:
	if remote_cursors.has(peer_id):
		remote_cursors[peer_id].queue_free()
		remote_cursors.erase(peer_id)
	if _peer_tweens.has(peer_id):
		_peer_tweens.erase(peer_id)
	_peer_held_plant_type.erase(peer_id)
	# 移除该玩家的虚影
	_hide_cell_ghost(peer_id)
	_peer_highlighted_cells.erase(peer_id)
	if _peer_ping_nodes.has(peer_id):
		if is_instance_valid(_peer_ping_nodes[peer_id]):
			_peer_ping_nodes[peer_id].queue_free()
		_peer_ping_nodes.erase(peer_id)
#endregion
