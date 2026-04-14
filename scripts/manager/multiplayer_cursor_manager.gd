extends Node2D
## 多人模式光标管理器
## 显示其他玩家的选中状态和光标位置

class_name MultiplayerCursorManager

## 远程光标节点 {peer_id: CursorNode}
var remote_cursors: Dictionary = {}

## 本地光标同步计时器
var sync_timer: Timer

## 光标同步频率 (10Hz)
const SYNC_INTERVAL := 0.1

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

## 远端光标状态更新
func _on_remote_cursor_update(peer_id: int, state: Dictionary) -> void:
	# 不显示自己的光标
	if peer_id == multiplayer.get_unique_id():
		return

	if not remote_cursors.has(peer_id):
		_create_remote_cursor(peer_id)

	var cursor_node = remote_cursors[peer_id]
	# 平滑插值移动
	var target_pos = Vector2(state.get("pos_x", 0), state.get("pos_y", 0))
	var tween = cursor_node.create_tween()
	tween.tween_property(cursor_node, "global_position", target_pos, SYNC_INTERVAL).set_trans(Tween.TRANS_LINEAR)

	# 更新状态标签
	var label: Label = cursor_node.get_node("Label")
	var held_type = state.get("held_type", "none")
	match held_type:
		"plant":
			label.text = NetworkManager.get_player_name(peer_id) + " [种植]"
		"shovel":
			label.text = NetworkManager.get_player_name(peer_id) + " [铲子]"
		_:
			label.text = NetworkManager.get_player_name(peer_id)

	# 更新悬停格子高亮
	var hovered_row = state.get("hovered_row", -1)
	var hovered_col = state.get("hovered_col", -1)
	_update_cell_highlight(peer_id, hovered_row, hovered_col)

## 创建远程光标节点
func _create_remote_cursor(peer_id: int) -> void:
	var cursor = Node2D.new()
	cursor.z_index = 100
	cursor.name = "RemoteCursor_%d" % peer_id

	# 光标颜色圆点
	var color_rect = ColorRect.new()
	color_rect.custom_minimum_size = Vector2(12, 12)
	color_rect.size = Vector2(12, 12)
	color_rect.position = Vector2(-6, -6)
	color_rect.color = NetworkManager.get_player_color(peer_id)
	cursor.add_child(color_rect)

	# 玩家名标签
	var label = Label.new()
	label.name = "Label"
	label.position = Vector2(10, -8)
	label.text = NetworkManager.get_player_name(peer_id)
	label.add_theme_font_size_override("font_size", 10)
	label.modulate.a = 0.7
	cursor.add_child(label)

	add_child(cursor)
	remote_cursors[peer_id] = cursor

## 更新格子高亮
func _update_cell_highlight(peer_id: int, row: int, col: int) -> void:
	# 简单实现：暂不绘制格子高亮边框
	# 后续可通过 PlantCell 添加彩色边框
	pass

## 玩家离开时移除光标
func _on_player_left(peer_id: int) -> void:
	if remote_cursors.has(peer_id):
		remote_cursors[peer_id].queue_free()
		remote_cursors.erase(peer_id)
