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

## 铲子纹理
const SHOVEL_TEXTURE := preload("res://assets/image/ui/ui_card/Shovel.png")

## 植物预览缓存 {PlantType: Node2D(原型)} — 避免重复实例化
var _plant_preview_cache: Dictionary = {}

## 每个 peer 当前高亮的格子 {peer_id: Vector2i}
var _peer_highlighted_cells: Dictionary = {}

## 每个 peer 当前显示的植物类型 {peer_id: int}
var _peer_held_plant_type: Dictionary = {}

## 光标插值用 Tween {peer_id: Tween}
var _peer_tweens: Dictionary = {}

func _ready() -> void:
	if not NetworkManager.is_multiplayer:
		return

	# 订阅远端光标更新事件
	EventBus.subscribe("remote_cursor_update", _on_remote_cursor_update)
	NetworkManager.player_left.connect(_on_player_left)

	# 创建本地光标同步计时器
	sync_timer = Timer.new()
	sync_timer.wait_time = SYNC_INTERVAL
	sync_timer.autostart = true
	sync_timer.timeout.connect(_on_sync_timer_timeout)
	add_child(sync_timer)

func _exit_tree() -> void:
	if EventBus.has_signal("remote_cursor_update"):
		EventBus.unsubscribe("remote_cursor_update", _on_remote_cursor_update)
	# 清除所有格子高亮
	for pid in _peer_highlighted_cells.keys():
		var old = _peer_highlighted_cells[pid]
		_set_cell_highlight(old.x, old.y, pid, false)
	_peer_highlighted_cells.clear()

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

	# 4. 更新悬停格子高亮
	var hovered_row: int = state.get("hovered_row", -1)
	var hovered_col: int = state.get("hovered_col", -1)
	_update_cell_highlight(peer_id, hovered_row, hovered_col)
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

#region 格子高亮
## 更新悬停格子高亮
func _update_cell_highlight(peer_id: int, row: int, col: int) -> void:
	# 清除旧高亮
	if _peer_highlighted_cells.has(peer_id):
		var old = _peer_highlighted_cells[peer_id]
		if old.x != row or old.y != col:
			_set_cell_highlight(old.x, old.y, peer_id, false)
			_peer_highlighted_cells.erase(peer_id)
		elif old.x == row and old.y == col:
			return  # 同一格子，无需更新

	# 设置新高亮
	if row >= 0 and col >= 0:
		_set_cell_highlight(row, col, peer_id, true)
		_peer_highlighted_cells[peer_id] = Vector2i(row, col)

## 设置指定格子的远端高亮
func _set_cell_highlight(row: int, col: int, peer_id: int, show: bool) -> void:
	var main_game = Global.main_game
	if not is_instance_valid(main_game):
		return
	var pcm = main_game.plant_cell_manager
	if row < 0 or col < 0 or row >= pcm.row_col.x or col >= pcm.row_col.y:
		return
	var cell: PlantCell = pcm.all_plant_cells[row][col]
	if show:
		cell.show_remote_highlight(peer_id, NetworkManager.get_player_color(peer_id))
	else:
		cell.hide_remote_highlight(peer_id)
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
	# 移除该玩家的格子高亮
	if _peer_highlighted_cells.has(peer_id):
		var old = _peer_highlighted_cells[peer_id]
		_set_cell_highlight(old.x, old.y, peer_id, false)
		_peer_highlighted_cells.erase(peer_id)
#endregion
