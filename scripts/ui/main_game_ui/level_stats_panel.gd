extends CanvasLayer
class_name LevelStatsPanel
## 关卡结算统计面板，显示每个玩家收集的阳光数量

signal stats_confirmed

@onready var _root: Control = %Root
@onready var _player_rows: VBoxContainer = %PlayerRows
@onready var _confirm_btn: Button = %ConfirmBtn

## ---- 肉鸽Buff卡牌（暂未启用） ----
#const BUFF_CARD_SCENE = preload("res://scenes/ui/roguelike_buff_card.tscn")
#const BUFF_CARD_COUNT := 3  # 每次展示的卡牌数量
#
## 示例Buff数据池，后续可从资源文件加载
#var _buff_pool: Array[Dictionary] = [
#	{"id": "sun_boost", "name": "阳光加成", "description": "每次收集阳光额外获得25阳光", "rarity": 0},
#	{"id": "fast_plant", "name": "快速种植", "description": "植物种植冷却减少30%", "rarity": 0},
#	{"id": "tough_wall", "name": "坚壁", "description": "坚果类植物生命值+50%", "rarity": 1},
#	{"id": "double_pea", "name": "双重射击", "description": "豌豆射手每次发射2颗子弹", "rarity": 1},
#	{"id": "cherry_rain", "name": "天降樱桃", "description": "每波开始随机炸一个区域", "rarity": 2},
#	{"id": "sun_rain", "name": "阳光雨", "description": "每波开始额外掉落200阳光", "rarity": 2},
#]
#
#func _show_buff_selection() -> void:
#	var cards_data := _pick_random_buffs(BUFF_CARD_COUNT)
#	var card_container := HBoxContainer.new()
#	card_container.name = "BuffCardContainer"
#	card_container.alignment = BoxContainer.ALIGNMENT_CENTER
#	card_container.add_theme_constant_override("separation", 20)
#	card_container.anchor_left = 0.0
#	card_container.anchor_right = 1.0
#	card_container.anchor_top = 0.5
#	card_container.anchor_bottom = 0.5
#	card_container.grow_horizontal = Control.GROW_DIRECTION_BOTH
#	card_container.grow_vertical = Control.GROW_DIRECTION_BOTH
#	_root.add_child(card_container)
#
#	for data in cards_data:
#		var card: RoguelikeBuffCard = BUFF_CARD_SCENE.instantiate()
#		card_container.add_child(card)
#		card.setup(data)
#		card.card_selected.connect(_on_buff_card_selected)
#
#func _pick_random_buffs(count: int) -> Array[Dictionary]:
#	var pool := _buff_pool.duplicate()
#	pool.shuffle()
#	var result: Array[Dictionary] = []
#	for i in mini(count, pool.size()):
#		result.append(pool[i])
#	return result
#
#func _on_buff_card_selected(card: RoguelikeBuffCard) -> void:
#	print("[Roguelike] 选择Buff: ", card.buff_data.get("name", ""))
#	# TODO: 将选中的buff应用到玩家/全局状态
#	# 移除卡牌容器
#	var container = _root.get_node_or_null("BuffCardContainer")
#	if container:
#		var tween = create_tween()
#		tween.tween_property(container, "modulate:a", 0.0, 0.3)
#		await tween.finished
#		container.queue_free()
## ---- 肉鸽Buff卡牌 END ----

func _ready() -> void:
	var stats = _get_sun_stats()
	_populate_rows(stats)
	# 淡入动画
	_root.modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(_root, "modulate:a", 1.0, 0.5)

## 获取阳光统计数据：返回 [{peer_id, name, color, sun}]
func _get_sun_stats() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var sun_data: Dictionary = {}

	if is_instance_valid(Global.main_game):
		sun_data = Global.main_game.day_suns_manager.sun_collected_per_player

	if NetworkManager.is_multiplayer:
		for peer_id in NetworkManager.players:
			var info = NetworkManager.players[peer_id]
			var color_idx = info.get("color_index", 0)
			var color = NetworkManager.PLAYER_COLORS[color_idx] if color_idx < NetworkManager.PLAYER_COLORS.size() else Color.WHITE
			result.append({
				"peer_id": peer_id,
				"name": info.get("name", "P%d" % peer_id),
				"color": color,
				"sun": sun_data.get(peer_id, 0),
			})
	else:
		result.append({
			"peer_id": 1,
			"name": "玩家",
			"color": Color(1.0, 0.9, 0.3),
			"sun": sun_data.get(1, 0),
		})

	# 按阳光数量降序排列
	result.sort_custom(func(a, b): return a["sun"] > b["sun"])
	return result

## 根据统计数据动态填充玩家行
func _populate_rows(stats: Array[Dictionary]) -> void:
	var max_sun := 0
	for s in stats:
		if s["sun"] > max_sun:
			max_sun = s["sun"]

	for s in stats:
		var is_top = s["sun"] == max_sun and max_sun > 0
		var display_name = ("👑 " + s["name"]) if is_top else s["name"]
		var row = _create_row(display_name, str(s["sun"]), s["color"], 22, is_top)
		_player_rows.add_child(row)

func _create_row(left_text: String, right_text: String, color: Color, font_size: int, bold: bool) -> HBoxContainer:
	var row := HBoxContainer.new()

	var lbl_name := Label.new()
	lbl_name.text = left_text
	lbl_name.add_theme_font_size_override("font_size", font_size)
	lbl_name.add_theme_color_override("font_color", color)
	lbl_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl_name)

	var lbl_sun := Label.new()
	lbl_sun.text = right_text
	lbl_sun.add_theme_font_size_override("font_size", font_size)
	lbl_sun.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3) if bold else color)
	lbl_sun.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_sun.custom_minimum_size = Vector2(120, 0)
	row.add_child(lbl_sun)

	return row

func _on_confirm() -> void:
	stats_confirmed.emit()
	var tween = create_tween()
	tween.tween_property(_root, "modulate:a", 0.0, 0.3)
	await tween.finished
	queue_free()
