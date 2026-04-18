extends Control
class_name RogueMap

## 肉鸽地图 - 生成类似杀戮尖塔的随机地图
## 算法分两阶段：1.生成网格与路径  2.分配房间类型
## 交互：鼠标滚轮或左键拖拽上下滚动整张地图

signal node_selected(map_node: RogueMapNode)
signal enter_room(map_node: RogueMapNode)

const MAP_NODE_SCENE: PackedScene = preload("res://scenes/rogue/map_node.tscn")

## 房间场景映射
const ROOM_SCENES: Dictionary = {
	RogueMapNode.RoomType.EVENT: preload("res://scenes/rogue/event_room.tscn"),
	RogueMapNode.RoomType.REST: preload("res://scenes/rogue/rest_room.tscn"),
	RogueMapNode.RoomType.SHOP: preload("res://scenes/rogue/shop_room.tscn"),
	RogueMapNode.RoomType.MONSTER: preload("res://scenes/rogue/battle_room.tscn"),
	RogueMapNode.RoomType.ELITE: preload("res://scenes/rogue/battle_room.tscn"),
	RogueMapNode.RoomType.BOSS: preload("res://scenes/rogue/battle_room.tscn"),
	# TREASURE 暂时复用 EVENT
	RogueMapNode.RoomType.TREASURE: preload("res://scenes/rogue/event_room.tscn"),
}

const GRID_COLS: int = 7       ## 网格列数
const GRID_ROWS: int = 16      ## 网格行数 (含Boss层，row 0~14为普通层，row 15为Boss)
const PATH_COUNT: int = 6      ## 生成路径数量
const BOSS_ROW: int = 15       ## Boss层的行索引

## 房间类型概率池百分比
const ROOM_RATIOS: Dictionary = {
	RogueMapNode.RoomType.EVENT: 0.15,
	RogueMapNode.RoomType.MONSTER: 0.20,
	RogueMapNode.RoomType.REST: 0.12,
	RogueMapNode.RoomType.ELITE: 0.08,
	RogueMapNode.RoomType.SHOP: 0.05,
}

## 布局参数
const NODE_MARGIN_X: float = 0.25      ## 节点区域左右留白占宽度的比例
const NODE_MARGIN_Y: float = 0.3       ## 节点区域上下留白占对应背景图高度的比例
const NODE_RANDOM_OFFSET: float = 15.0 ## 节点位置随机偏移量（像素）
const BG_OVERLAP: float = 20.0         ## 背景图片之间的重叠像素数

## 滚动参数
const SCROLL_SPEED: float = 60.0       ## 鼠标滚轮滚动速度
const SCROLL_SMOOTH: float = 8.0       ## 滚动平滑系数
const DRAG_THRESHOLD: float = 5.0      ## 拖拽判定阈值（像素），小于此值视为点击而非拖拽

@onready var map_content: Control = $MapContent
@onready var bg_top: TextureRect = $MapContent/BgTop
@onready var bg_middle: TextureRect = $MapContent/BgMiddle
@onready var bg_bottom: TextureRect = $MapContent/BgBottom
@onready var lines_node: MapLines = $MapContent/Lines
@onready var nodes_container: Control = $MapContent/Nodes

## 网格数据: grid[row][col] = RogueMapNode 或 null
var grid: Array = []
## 所有边 (连线): Array of [Vector2i, Vector2i] 其中 Vector2i = (col, row)
var edges: Array = []
## 当前玩家所在行 (-1 表示还未开始)
var current_row: int = -1
## 当前可选节点列表
var available_nodes: Array[RogueMapNode] = []
## 当前房间实例
var _current_room: Control = null

## 滚动状态
var _scroll_offset: float = 0.0
var _current_scroll: float = 0.0
var _is_dragging: bool = false
var _drag_started: bool = false       ## 实际开始拖拽（超过阈值）
var _drag_start_y: float = 0.0
var _drag_start_scroll: float = 0.0
var _content_height: float = 0.0

## 节点布局（由背景尺寸反推）
var _node_top_y: float = 0.0          ## 第15层节点的Y坐标（最上方）
var _node_bottom_y: float = 0.0       ## 第1层节点的Y坐标（最下方）
var _node_left_x: float = 0.0         ## 最左列节点的X坐标
var _node_spacing_x: float = 0.0      ## 节点水平间距
var _node_spacing_y: float = 0.0      ## 节点垂直间距

func _ready() -> void:
	clip_contents = true
	lines_node.map = self

	var has_snapshot: bool = not RogueState.map_snapshot.is_empty()
	if has_snapshot:
		_restore_map_from_snapshot()
	else:
		generate_map()

	# 等待一帧让 Control 完成布局，获得正确的 size
	await get_tree().process_frame
	_setup_backgrounds()
	_layout_nodes()

	if has_snapshot:
		_restore_node_states()
	else:
		_set_initial_selectable()

	# 再等待一帧确保布局完全完成
	await get_tree().process_frame

	if has_snapshot:
		# 恢复时滚动到玩家当前所在层附近
		_scroll_to_row(current_row)
	else:
		# 初始滚动到底部（玩家从底部开始）
		_scroll_offset = _get_max_scroll()
		_current_scroll = _scroll_offset
	_apply_scroll()

	# Check if returning from a battle
	if not RogueState.pending_battle_config.is_empty():
		_handle_post_battle.call_deferred()

func _process(delta: float) -> void:
	# 平滑滚动
	if not is_equal_approx(_current_scroll, _scroll_offset):
		_current_scroll = lerpf(_current_scroll, _scroll_offset, minf(SCROLL_SMOOTH * delta, 1.0))
		if absf(_current_scroll - _scroll_offset) < 0.5:
			_current_scroll = _scroll_offset
		_apply_scroll()

func _input(event: InputEvent) -> void:
	# 鼠标滚轮
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_scroll_offset = clampf(_scroll_offset - SCROLL_SPEED, 0.0, _get_max_scroll())
			get_viewport().set_input_as_handled()
			return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_scroll_offset = clampf(_scroll_offset + SCROLL_SPEED, 0.0, _get_max_scroll())
			get_viewport().set_input_as_handled()
			return
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_dragging = true
				_drag_started = false
				_drag_start_y = mb.global_position.y
				_drag_start_scroll = _scroll_offset
				# 不立即标记为已处理，让节点可以处理点击事件
				return
			else:
				if _drag_started:
					# 只在实际拖拽后才标记为已处理
					get_viewport().set_input_as_handled()
				_is_dragging = false
				_drag_started = false
				return

	# 鼠标拖拽
	if event is InputEventMouseMotion and _is_dragging:
		var mm: InputEventMouseMotion = event
		var delta_y: float = _drag_start_y - mm.global_position.y
		# 超过阈值才开始拖拽，避免误触
		if not _drag_started:
			if absf(delta_y) > DRAG_THRESHOLD:
				_drag_started = true
			else:
				return
		if _drag_started:
			_scroll_offset = clampf(_drag_start_scroll + delta_y, 0.0, _get_max_scroll())
			_current_scroll = _scroll_offset  # 拖拽时不做平滑，直接跟随
			_apply_scroll()
			get_viewport().set_input_as_handled()
		return

func _get_max_scroll() -> float:
	return maxf(0.0, _content_height - size.y)

func _apply_scroll() -> void:
	map_content.position.y = -_current_scroll

#region ===== 背景拼接与全局坐标系 =====

func _setup_backgrounds() -> void:
	## 三张背景图纵向拼接，宽度与窗口对齐，高度等比缩放
	## 然后根据总高度反推节点的间距和位置
	var view_width: float = size.x if size.x > 0 else 1024.0

	# 获取每张图的原始尺寸，按宽度等比缩放
	var top_tex: Texture2D = bg_top.texture
	var mid_tex: Texture2D = bg_middle.texture
	var bot_tex: Texture2D = bg_bottom.texture

	var top_h: float = _scaled_height(top_tex, view_width)
	var mid_h: float = _scaled_height(mid_tex, view_width)
	var bot_h: float = _scaled_height(bot_tex, view_width)

	# 布局：Top -> Middle -> Bottom，相邻图片轻微重叠避免接缝
	bg_top.position = Vector2.ZERO
	bg_top.size = Vector2(view_width, top_h)

	bg_middle.position = Vector2(0, top_h - BG_OVERLAP)
	bg_middle.size = Vector2(view_width, mid_h)

	bg_bottom.position = Vector2(0, top_h - BG_OVERLAP + mid_h - BG_OVERLAP)
	bg_bottom.size = Vector2(view_width, bot_h)

	_content_height = bg_bottom.position.y + bot_h

	# 计算节点分布区域：在整个内容高度内留出上下边距
	var margin_top: float = top_h * NODE_MARGIN_Y
	var margin_bottom: float = bot_h * NODE_MARGIN_Y
	_node_top_y = margin_top                 # 第15层（最高层）的Y
	_node_bottom_y = _content_height - margin_bottom  # 第1层（最底层）的Y

	# 反推节点间距
	_node_spacing_y = (_node_bottom_y - _node_top_y) / float(GRID_ROWS - 1)

	# 水平方向：在视口宽度内按比例留白后均分
	var margin_x: float = view_width * NODE_MARGIN_X
	_node_left_x = margin_x
	_node_spacing_x = (view_width - margin_x * 2.0) / float(GRID_COLS - 1)

	map_content.custom_minimum_size = Vector2(view_width, _content_height)

func _scaled_height(tex: Texture2D, target_width: float) -> float:
	if tex == null:
		return 400.0
	var tex_size: Vector2 = tex.get_size()
	return tex_size.y * (target_width / tex_size.x)

#endregion

#region ===== 阶段一：生成网格与路径 =====

## 网格数据在此阶段使用坐标而非节点实例，节点实例延迟到 _layout_nodes 时创建
## _grid_data[row][col] = true/false 表示该位置是否有节点
var _grid_data: Array = []

func generate_map() -> void:
	_init_grid()
	_generate_paths()
	_merge_start_node()
	_prune_early_convergence()
	_remove_isolated_cells()
	_assign_room_types()
	_add_boss_node()

func _init_grid() -> void:
	grid.clear()
	edges.clear()
	_grid_data.clear()
	for row in range(GRID_ROWS):
		var row_arr: Array = []
		var data_row: Array = []
		for col in range(GRID_COLS):
			row_arr.append(null)
			data_row.append(false)
		grid.append(row_arr)
		_grid_data.append(data_row)

func _generate_paths() -> void:
	var used_first_starts: Array[int] = []

	for path_idx in range(PATH_COUNT):
		var col: int = _pick_start_col(path_idx, used_first_starts)
		if path_idx < 2:
			used_first_starts.append(col)
		_mark_cell(0, col)

		for row in range(1, BOSS_ROW):
			var next_col: int = _pick_next_col(col, row)
			_mark_cell(row, next_col)
			_add_edge(col, row - 1, next_col, row)
			col = next_col

func _merge_start_node() -> void:
	## 将所有第1层的起点合并为一个，居中放置
	var start_cols: Array[int] = []
	for col in range(GRID_COLS):
		if _grid_data[0][col]:
			start_cols.append(col)

	if start_cols.size() <= 1:
		return

	var keep_col: int = start_cols[start_cols.size() / 2]

	for col in start_cols:
		if col == keep_col:
			continue
		for edge in edges:
			if edge[0] == Vector2i(col, 0):
				edge[0] = Vector2i(keep_col, 0)
		_grid_data[0][col] = false

	_deduplicate_edges()

func _deduplicate_edges() -> void:
	var unique_edges: Array = []
	for edge in edges:
		var found: bool = false
		for ue in unique_edges:
			if ue[0] == edge[0] and ue[1] == edge[1]:
				found = true
				break
		if not found:
			unique_edges.append(edge)
	edges = unique_edges

func _pick_start_col(path_idx: int, used_starts: Array[int]) -> int:
	var candidates: Array[int] = []
	for c in range(GRID_COLS):
		candidates.append(c)

	if path_idx < 2 and used_starts.size() > 0:
		for s in used_starts:
			candidates.erase(s)

	return candidates[randi() % candidates.size()]

func _pick_next_col(current_col: int, next_row: int) -> int:
	var candidates: Array[int] = []
	for dc in [-1, 0, 1]:
		var nc: int = current_col + dc
		if nc >= 0 and nc < GRID_COLS:
			candidates.append(nc)

	candidates.shuffle()
	for nc in candidates:
		if not _would_cross(current_col, next_row - 1, nc, next_row):
			return nc

	return clampi(current_col, 0, GRID_COLS - 1)

func _would_cross(from_col: int, from_row: int, to_col: int, to_row: int) -> bool:
	for edge in edges:
		var e_from: Vector2i = edge[0]
		var e_to: Vector2i = edge[1]
		if e_from.y == from_row and e_to.y == to_row:
			if (from_col < e_from.x and to_col > e_to.x) or \
			   (from_col > e_from.x and to_col < e_to.x):
				return true
	return false

func _add_edge(from_col: int, from_row: int, to_col: int, to_row: int) -> void:
	var edge: Array = [Vector2i(from_col, from_row), Vector2i(to_col, to_row)]
	for e in edges:
		if e[0] == edge[0] and e[1] == edge[1]:
			return
	edges.append(edge)

func _mark_cell(row: int, col: int) -> void:
	_grid_data[row][col] = true

func _prune_early_convergence() -> void:
	var target_counts: Dictionary = {}

	for edge in edges:
		if edge[0].y == 0 and edge[1].y == 1:
			var target_col: int = edge[1].x
			if not target_counts.has(target_col):
				target_counts[target_col] = 0
			target_counts[target_col] += 1

	var edges_to_remove: Array = []
	var kept_per_target: Dictionary = {}

	for edge in edges:
		if edge[0].y == 0 and edge[1].y == 1:
			var target_col: int = edge[1].x
			if target_counts[target_col] > 2:
				if not kept_per_target.has(target_col):
					kept_per_target[target_col] = 0
				kept_per_target[target_col] += 1
				if kept_per_target[target_col] > 2:
					edges_to_remove.append(edge)

	for edge in edges_to_remove:
		edges.erase(edge)

	_ensure_start_connectivity()

func _ensure_start_connectivity() -> void:
	var start_cols: Array[int] = []
	for col in range(GRID_COLS):
		if _grid_data[0][col]:
			start_cols.append(col)

	for start_col in start_cols:
		var has_edge: bool = false
		for edge in edges:
			if edge[0] == Vector2i(start_col, 0):
				has_edge = true
				break

		if not has_edge:
			var best_col: int = -1
			var best_dist: int = GRID_COLS + 1
			for col in range(GRID_COLS):
				if _grid_data[1][col]:
					var dist: int = absi(col - start_col)
					if dist < best_dist:
						best_dist = dist
						best_col = col
			if best_col >= 0:
				_add_edge(start_col, 0, best_col, 1)

func _remove_isolated_cells() -> void:
	var connected: Dictionary = {}

	for edge in edges:
		connected[edge[0]] = true
		connected[edge[1]] = true

	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			if _grid_data[row][col]:
				var key: Vector2i = Vector2i(col, row)
				if not connected.has(key):
					_grid_data[row][col] = false

#endregion

#region ===== 阶段二：分配房间类型 =====

var _room_types: Array = []

func _assign_room_types() -> void:
	_room_types.clear()
	for row in range(GRID_ROWS):
		var row_arr: Array = []
		for col in range(GRID_COLS):
			row_arr.append(-1)
		_room_types.append(row_arr)

	_fill_fixed_rows()

	var unassigned: Array[Vector2i] = []
	for row in range(BOSS_ROW):
		for col in range(GRID_COLS):
			if _grid_data[row][col] and row != 0 and row != 8 and row != 14:
				unassigned.append(Vector2i(col, row))

	var pool: Array = _build_room_pool(unassigned.size())

	for coord in unassigned:
		_assign_coord_from_pool(coord, pool)

func _fill_fixed_rows() -> void:
	for col in range(GRID_COLS):
		if _grid_data[0][col]:
			_room_types[0][col] = RogueMapNode.RoomType.EVENT
	for col in range(GRID_COLS):
		if _grid_data[8][col]:
			_room_types[8][col] = RogueMapNode.RoomType.TREASURE
	for col in range(GRID_COLS):
		if _grid_data[14][col]:
			_room_types[14][col] = RogueMapNode.RoomType.REST

func _build_room_pool(total: int) -> Array:
	var pool: Array = []

	for room_type in ROOM_RATIOS:
		var count: int = roundi(total * ROOM_RATIOS[room_type])
		for i in range(count):
			pool.append(room_type)

	while pool.size() < total:
		pool.append(RogueMapNode.RoomType.MONSTER)

	pool.shuffle()
	return pool

func _assign_coord_from_pool(coord: Vector2i, pool: Array) -> void:
	var col: int = coord.x
	var row: int = coord.y
	var max_attempts: int = pool.size()

	for attempt in range(max_attempts):
		if pool.is_empty():
			break

		var idx: int = randi() % pool.size()
		var room_type: RogueMapNode.RoomType = pool[idx]

		if _validate_room_placement_at(col, row, room_type):
			pool.remove_at(idx)
			_room_types[row][col] = room_type
			return

	_room_types[row][col] = RogueMapNode.RoomType.MONSTER
	var mi: int = pool.find(RogueMapNode.RoomType.MONSTER)
	if mi >= 0:
		pool.remove_at(mi)
	elif not pool.is_empty():
		pool.remove_at(pool.size() - 1)

func _validate_room_placement_at(col: int, row: int, room_type: RogueMapNode.RoomType) -> bool:
	if row < 5:
		if room_type == RogueMapNode.RoomType.ELITE or room_type == RogueMapNode.RoomType.REST:
			return false

	if room_type in [RogueMapNode.RoomType.ELITE, RogueMapNode.RoomType.REST, RogueMapNode.RoomType.SHOP]:
		for edge in edges:
			if edge[1] == Vector2i(col, row):
				var prev_type: int = _room_types[edge[0].y][edge[0].x]
				if prev_type == room_type:
					return false

	return true

func _add_boss_node() -> void:
	var boss_col: int = GRID_COLS / 2
	_mark_cell(BOSS_ROW, boss_col)
	while _room_types.size() <= BOSS_ROW:
		var r: Array = []
		for c in range(GRID_COLS):
			r.append(-1)
		_room_types.append(r)
	_room_types[BOSS_ROW][boss_col] = RogueMapNode.RoomType.BOSS

	for col in range(GRID_COLS):
		if _grid_data[14][col]:
			_add_edge(col, 14, boss_col, BOSS_ROW)

#endregion

#region ===== 布局与UI =====

func _layout_nodes() -> void:
	# 根据 _grid_data 和 _room_types 创建节点实例并放置
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			if _grid_data[row][col]:
				var room_type: RogueMapNode.RoomType = _room_types[row][col] as RogueMapNode.RoomType
				var node: RogueMapNode = MAP_NODE_SCENE.instantiate()
				node.setup(room_type, col, row)
				grid[row][col] = node

	# 建立节点之间的连接关系
	for edge in edges:
		var from_node: RogueMapNode = grid[edge[0].y][edge[0].x]
		var to_node: RogueMapNode = grid[edge[1].y][edge[1].x]
		if from_node != null and to_node != null:
			from_node.add_next_node(to_node)

	# 给节点设置位置并添加到场景树
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			var node: RogueMapNode = grid[row][col]
			if node != null:
				var inverted_row: int = GRID_ROWS - 1 - row
				var base_x: float = _node_left_x + col * _node_spacing_x
				var base_y: float = _node_top_y + inverted_row * _node_spacing_y
				base_x -= node.size.x / 2.0
				base_y -= node.size.y / 2.0
				if node.room_type != RogueMapNode.RoomType.BOSS:
					var rand_x: float = randf_range(-NODE_RANDOM_OFFSET, NODE_RANDOM_OFFSET)
					var rand_y: float = randf_range(-NODE_RANDOM_OFFSET, NODE_RANDOM_OFFSET)
					base_x += rand_x
					base_y += rand_y
				node.position = Vector2(base_x, base_y)
				node.node_clicked.connect(_on_node_clicked)
				node.node_enter_room.connect(_on_node_enter_room)
				nodes_container.add_child(node)

	lines_node.queue_redraw()

func _set_initial_selectable() -> void:
	for col in range(GRID_COLS):
		var node: RogueMapNode = grid[0][col]
		if node != null:
			node.selectable = true
			available_nodes.append(node)

	for row in range(1, GRID_ROWS):
		for col in range(GRID_COLS):
			var node: RogueMapNode = grid[row][col]
			if node != null:
				node.selectable = false

func _on_node_clicked(map_node: RogueMapNode) -> void:
	current_row = map_node.row

	# 标记当前节点为已访问
	map_node.mark_visited()

	for n in available_nodes:
		n.selectable = false
	available_nodes.clear()

	for next_node in map_node.next_nodes:
		next_node.selectable = true
		available_nodes.append(next_node)

	# 更新连线（显示已走过的路径）
	lines_node.queue_redraw()

	node_selected.emit(map_node)

func _on_node_enter_room(map_node: RogueMapNode) -> void:
	enter_room.emit(map_node)

	# 获取对应房间场景
	var scene: PackedScene = ROOM_SCENES.get(map_node.room_type)
	if scene == null:
		push_warning("No room scene for type: %s" % map_node.room_type)
		return

	# 战斗房间会触发 change_scene_to_file，需要提前保存地图快照
	if map_node.room_type in [
		RogueMapNode.RoomType.MONSTER,
		RogueMapNode.RoomType.ELITE,
		RogueMapNode.RoomType.BOSS,
	]:
		_save_map_snapshot()

	# 隐藏地图，实例化房间
	map_content.visible = false
	_current_room = scene.instantiate()

	# 战斗房间需要额外设置
	if _current_room.has_method("setup") and map_node.room_type in [
		RogueMapNode.RoomType.MONSTER,
		RogueMapNode.RoomType.ELITE,
		RogueMapNode.RoomType.BOSS,
	]:
		_current_room.setup(map_node.room_type, map_node.row)

	# 连接房间完成信号
	if _current_room.has_signal("room_completed"):
		_current_room.room_completed.connect(_on_room_completed)

	add_child(_current_room)

func _on_room_completed(args = null) -> void:
	if _current_room != null:
		_current_room.queue_free()
		_current_room = null
	map_content.visible = true

## 战斗胜利后处理奖励
func _handle_post_battle() -> void:
	var config: Dictionary = RogueState.pending_battle_config
	
	# Award gold
	var gold_min: int = config.get("gold_min", 10)
	var gold_max: int = config.get("gold_max", 30)
	RogueState.add_gold(randi_range(gold_min, gold_max))
	RogueState.battles_won += 1
	
	# Show buff selection
	var buff_scene := preload("res://scenes/rogue/buff_selection.tscn")
	var buff_ui: BuffSelection = buff_scene.instantiate()
	buff_ui.setup(config.get("reward_picks", 2))
	add_child(buff_ui)
	await buff_ui.selection_completed
	
	# Clear pending battle
	RogueState.pending_battle_config = {}

func get_node_center(map_node: RogueMapNode) -> Vector2:
	return map_node.position + map_node.size / 2.0

#endregion

#region ===== 地图状态持久化 =====

## 将当前地图状态保存到 RogueState.map_snapshot
func _save_map_snapshot() -> void:
	var visited_coords: Array = []
	var available_coords: Array = []
	for row_idx in range(GRID_ROWS):
		for col_idx in range(GRID_COLS):
			var node: RogueMapNode = grid[row_idx][col_idx]
			if node == null:
				continue
			if node.visited:
				visited_coords.append(Vector2i(col_idx, row_idx))
			if node in available_nodes:
				available_coords.append(Vector2i(col_idx, row_idx))

	# 序列化 edges (Array of [Vector2i, Vector2i])
	var edges_data: Array = []
	for edge in edges:
		edges_data.append([edge[0], edge[1]])

	RogueState.map_snapshot = {
		"grid_data": _grid_data.duplicate(true),
		"edges": edges_data,
		"room_types": _room_types.duplicate(true),
		"current_row": current_row,
		"visited_coords": visited_coords,
		"available_coords": available_coords,
	}

## 从快照恢复网格数据 (不创建节点实例，那是 _layout_nodes 的职责)
func _restore_map_from_snapshot() -> void:
	var snap: Dictionary = RogueState.map_snapshot
	_grid_data = snap["grid_data"].duplicate(true)
	_room_types = snap["room_types"].duplicate(true)
	current_row = snap["current_row"]

	# 恢复 edges
	edges.clear()
	for e in snap["edges"]:
		edges.append([e[0], e[1]])

	# 初始化空 grid (节点实例由 _layout_nodes 创建)
	grid.clear()
	for row_idx in range(GRID_ROWS):
		var row_arr: Array = []
		for col_idx in range(GRID_COLS):
			row_arr.append(null)
		grid.append(row_arr)

## 恢复节点的 visited / selectable 状态 (在 _layout_nodes 之后调用)
func _restore_node_states() -> void:
	var snap: Dictionary = RogueState.map_snapshot
	var visited_coords: Array = snap.get("visited_coords", [])
	var avail_coords: Array = snap.get("available_coords", [])

	# 先把所有节点设为不可选
	for row_idx in range(GRID_ROWS):
		for col_idx in range(GRID_COLS):
			var node: RogueMapNode = grid[row_idx][col_idx]
			if node != null:
				node.selectable = false

	# 恢复已访问
	for coord in visited_coords:
		var node: RogueMapNode = grid[coord.y][coord.x]
		if node != null:
			node.mark_visited()

	# 恢复可选节点
	available_nodes.clear()
	for coord in avail_coords:
		var node: RogueMapNode = grid[coord.y][coord.x]
		if node != null:
			node.selectable = true
			available_nodes.append(node)

## 滚动到指定行附近
func _scroll_to_row(row_idx: int) -> void:
	if row_idx < 0:
		_scroll_offset = _get_max_scroll()
	else:
		var inverted_row: int = GRID_ROWS - 1 - row_idx
		var target_y: float = _node_top_y + inverted_row * _node_spacing_y
		# 将目标行居中显示
		_scroll_offset = clampf(target_y - size.y * 0.5, 0.0, _get_max_scroll())
	_current_scroll = _scroll_offset

#endregion
