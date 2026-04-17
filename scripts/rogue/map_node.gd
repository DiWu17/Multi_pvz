extends TextureButton
class_name RogueMapNode

## 地图节点 - 代表地图上一个可点击的房间

signal node_clicked(map_node: RogueMapNode)
signal node_enter_room(map_node: RogueMapNode)

enum RoomType {
	MONSTER,
	ELITE,
	REST,
	SHOP,
	EVENT,
	TREASURE,
	BOSS,
}

## 房间类型对应的图标资源路径
const ROOM_ICONS: Dictionary = {
	RoomType.MONSTER: "res://assets/icons/map_monster.tres",
	RoomType.ELITE: "res://assets/icons/map_elite.tres",
	RoomType.REST: "res://assets/icons/map_rest.tres",
	RoomType.SHOP: "res://assets/icons/map_shop.tres",
	RoomType.EVENT: "res://assets/icons/map_unknown.tres",
	RoomType.TREASURE: "res://assets/icons/map_chest.tres",
	RoomType.BOSS: "res://assets/icons/doormaker_boss_icon.png",
}

## 房间类型名称（用于 tooltip）
const ROOM_NAMES: Dictionary = {
	RoomType.MONSTER: "普通战斗",
	RoomType.ELITE: "精英战斗",
	RoomType.REST: "篝火休息",
	RoomType.SHOP: "商店",
	RoomType.EVENT: "未知事件",
	RoomType.TREASURE: "宝箱",
	RoomType.BOSS: "BOSS",
}

## 房间类型
var room_type: RoomType = RoomType.MONSTER
## 在网格中的列索引 (0-6)
var col: int = 0
## 在网格中的行索引 (0-14, 0=第1层)
var row: int = 0
## 连接到的下一层节点列表
var next_nodes: Array[RogueMapNode] = []
## 是否可以被玩家选择
var selectable: bool = false:
	set(value):
		selectable = value
		modulate.a = 1.0 if selectable else 0.5
		disabled = not selectable
## 是否已经访问过
var visited: bool = false

const NODE_SIZE_NORMAL: Vector2 = Vector2(64, 64)
const NODE_SIZE_BOSS: Vector2 = Vector2(128, 128)

## Hover 效果参数
const HOVER_SCALE: Vector2 = Vector2(1.15, 1.15)
const NORMAL_SCALE: Vector2 = Vector2(1.0, 1.0)
const HOVER_TWEEN_DURATION: float = 0.12
const HOVER_MODULATE: Color = Color(1.2, 1.2, 1.2, 1.0)

## 双击检测
const DOUBLE_CLICK_INTERVAL: float = 0.35
var _last_click_time: float = 0.0
var _hover_tween: Tween = null

@onready var icon_sprite: TextureRect = $IconSprite

func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	texture_normal = load("res://assets/icons/map_node_background.tres")
	_apply_size()
	_update_icon()
	# 设置 tooltip
	if ROOM_NAMES.has(room_type):
		tooltip_text = ROOM_NAMES[room_type]

func setup(p_room_type: RoomType, p_col: int, p_row: int) -> void:
	room_type = p_room_type
	col = p_col
	row = p_row
	_apply_size()
	if is_inside_tree():
		_update_icon()
		if ROOM_NAMES.has(room_type):
			tooltip_text = ROOM_NAMES[room_type]

func _apply_size() -> void:
	var node_size: Vector2 = NODE_SIZE_BOSS if room_type == RoomType.BOSS else NODE_SIZE_NORMAL
	custom_minimum_size = node_size
	size = node_size
	pivot_offset = node_size / 2.0

func _update_icon() -> void:
	if icon_sprite and ROOM_ICONS.has(room_type):
		icon_sprite.texture = load(ROOM_ICONS[room_type])

func _on_pressed() -> void:
	if not selectable:
		return
	# 单击即选择并进入房间
	node_clicked.emit(self)
	node_enter_room.emit(self)

func _on_mouse_entered() -> void:
	if not selectable:
		return
	_animate_hover(true)

func _on_mouse_exited() -> void:
	_animate_hover(false)

func _animate_hover(hovering: bool) -> void:
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	if hovering:
		_hover_tween.tween_property(self, "scale", HOVER_SCALE, HOVER_TWEEN_DURATION)
		self_modulate = HOVER_MODULATE
	else:
		_hover_tween.tween_property(self, "scale", NORMAL_SCALE, HOVER_TWEEN_DURATION)
		self_modulate = Color.WHITE

func add_next_node(node: RogueMapNode) -> void:
	if node not in next_nodes:
		next_nodes.append(node)

func mark_visited() -> void:
	visited = true
	modulate = Color(0.6, 0.6, 0.6, 0.8)
