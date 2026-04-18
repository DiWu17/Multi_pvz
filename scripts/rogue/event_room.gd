extends Control
class_name EventRoom

## 事件房间 — 从 res://resources/events/ 加载 RogueEventData 资源，
## 随机抽取一个事件展示给玩家，执行选项效果。

signal room_completed()

@onready var background: TextureRect = $Background
@onready var continue_button: Button = $ContinueButton
@onready var title_label: Label = $TitleLabel
@onready var description_label: RichTextLabel = $DescriptionLabel
@onready var choice_container: Node = $ChoiceContainer
@onready var result_label: RichTextLabel = $ResultLabel

## 事件资源路径列表（打包后 DirAccess 无法枚举 res://，需显式列出）
const EVENT_PATHS: Array[String] = [
	"res://resources/events/event_buff_selection.tres",
	"res://resources/events/event_relic_selection.tres",
]

const RELIC_PATHS: Array[String] = [
	"res://resources/relics/vajra.tres",
	"res://resources/relics/gremlin_horn.tres",
	"res://resources/relics/happy_flower.tres",
	"res://resources/relics/starting_sun_bonus.tres",
	"res://resources/relics/auto_collect_sun.tres",
	"res://resources/relics/sky_sun_speed_up.tres",
]

const ENCHANT_PATHS: Array[String] = [
	"res://resources/enchants/pumpkin.tres",
	"res://resources/enchants/inherent.tres",
	"res://resources/enchants/consumable.tres",
]

## 当前事件
var _event: RogueEventData
## 已加载的事件池
var _event_pool: Array[RogueEventData] = []
## 本次 run 中各事件出现次数
var _occurrence_counts: Dictionary = {}
var _choice_made: bool = false

# ══════════════════════════════════════════
#  生命周期
# ══════════════════════════════════════════

func _ready() -> void:
	continue_button.pressed.connect(_on_continue_pressed)
	continue_button.visible = false
	result_label.visible = false

	_load_event_pool()
	_roll_event()

# ══════════════════════════════════════════
#  事件池加载 — 自动扫描 events 目录
# ══════════════════════════════════════════

func _load_event_pool() -> void:
	_event_pool.clear()
	for path in EVENT_PATHS:
		var res := load(path)
		if res is RogueEventData:
			_event_pool.append(res)

# ══════════════════════════════════════════
#  事件抽取 — 加权随机 + 条件过滤
# ══════════════════════════════════════════

func _roll_event() -> void:
	var candidates: Array[RogueEventData] = []
	var weights: Array[int] = []

	for evt in _event_pool:
		if not _check_conditions(evt):
			continue
		candidates.append(evt)
		weights.append(evt.weight)

	if candidates.is_empty():
		_show_fallback()
		return

	_event = _weighted_random_pick(candidates, weights)
	_occurrence_counts[_event.id] = _occurrence_counts.get(_event.id, 0) + 1
	_display_event()

func _check_conditions(evt: RogueEventData) -> bool:
	# 出现次数上限
	if evt.max_occurrences > 0:
		if _occurrence_counts.get(evt.id, 0) >= evt.max_occurrences:
			return false
	# 楼层限制
	if evt.min_floor > 0 and RogueState.current_floor < evt.min_floor:
		return false
	if evt.max_floor >= 0 and RogueState.current_floor > evt.max_floor:
		return false
	# 需要拥有的遗物
	for relic_id in evt.required_relics:
		if not RogueBuffManager.has_relic(StringName(relic_id)):
			return false
	# 排除的遗物
	for relic_id in evt.excluded_relics:
		if RogueBuffManager.has_relic(StringName(relic_id)):
			return false
	return true

func _weighted_random_pick(items: Array[RogueEventData], weights: Array[int]) -> RogueEventData:
	var total := 0
	for w in weights:
		total += w
	var roll := randi() % total
	var cumulative := 0
	for i in range(items.size()):
		cumulative += weights[i]
		if roll < cumulative:
			return items[i]
	return items[items.size() - 1]

# ══════════════════════════════════════════
#  UI 展示
# ══════════════════════════════════════════

func _display_event() -> void:
	if title_label:
		title_label.text = _event.title
	if description_label:
		description_label.text = _event.description
	if _event.background_image and background:
		background.texture = _event.background_image

	# 清除旧选项按钮
	for child in choice_container.get_children():
		child.queue_free()

	# 动态生成选项按钮
	for i in range(_event.options.size()):
		var option: RogueEventOption = _event.options[i]
		var btn := Button.new()
		btn.text = option.label
		btn.tooltip_text = option.description
		btn.custom_minimum_size = Vector2(200, 40)
		btn.pressed.connect(_on_option_selected.bind(i))
		choice_container.add_child(btn)

func _show_fallback() -> void:
	if title_label:
		title_label.text = "平静的一天"
	if description_label:
		description_label.text = "周围一切风平浪静，什么也没有发生。"
	continue_button.visible = true

# ══════════════════════════════════════════
#  选项选择 & 效果执行
# ══════════════════════════════════════════

func _on_option_selected(option_index: int) -> void:
	if _choice_made:
		return
	_choice_made = true

	var option: RogueEventOption = _event.options[option_index]

	# 隐藏所有选项
	for child in choice_container.get_children():
		if child is Button:
			child.visible = false

	# 执行效果
	var result_text := option.label
	for effect in option.effects:
		var effect_result: String = await _execute_effect(effect)
		if not effect_result.is_empty():
			result_text += "\n" + effect_result

	if result_label:
		result_label.text = result_text
		result_label.visible = true
	continue_button.visible = true

## 执行单个效果条目，返回结果描述文本（支持 await）
func _execute_effect(effect: Resource) -> String:
	match effect.type:
		RogueEffectEntry.EffectType.NONE:
			return ""

		RogueEffectEntry.EffectType.ADD_RELIC:
			var relic: RelicData = load(effect.target_resource_path)
			if relic:
				RogueBuffManager.add_relic(relic)
				return "获得遗物: %s" % relic.display_name

		RogueEffectEntry.EffectType.ADD_BUFF:
			## 旧的 buff 已迁移为遗物，走 ADD_RELIC 逻辑
			var relic_compat: RelicData = load(effect.target_resource_path)
			if relic_compat:
				RogueBuffManager.add_relic(relic_compat)
				return "获得遗物: %s" % relic_compat.display_name

		RogueEffectEntry.EffectType.ADD_GOLD:
			RogueState.add_gold(effect.param_int)
			if effect.param_int >= 0:
				return "获得 %d 金币" % effect.param_int
			else:
				return "失去 %d 金币" % (-effect.param_int)

		RogueEffectEntry.EffectType.ADD_STARTING_SUN:
			RogueState.starting_sun += effect.param_int
			return "初始阳光 +%d" % effect.param_int

		RogueEffectEntry.EffectType.ADD_PLANT:
			var plant_type = _parse_plant_type(effect.param_string)
			if plant_type != null:
				RogueState.add_plant(plant_type, effect.param_int)
				return "获得 %d 张植物卡" % effect.param_int

		RogueEffectEntry.EffectType.REMOVE_PLANT:
			var plant_type = _parse_plant_type(effect.param_string)
			if plant_type != null:
				for j in range(effect.param_int):
					RogueState.consume_plant(plant_type)
				return "移除 %d 张植物卡" % effect.param_int

		RogueEffectEntry.EffectType.ADD_RANDOM_PLANT:
			var plant_pool = [
				CharacterRegistry.PlantType.P001PeaShooterSingle,
				CharacterRegistry.PlantType.P002SunFlower,
				CharacterRegistry.PlantType.P004WallNut,
				CharacterRegistry.PlantType.P005PotatoMine,
			]
			for j in range(effect.param_int):
				RogueState.add_plant(plant_pool[randi() % plant_pool.size()])
			return "获得 %d 张随机植物卡" % effect.param_int

		RogueEffectEntry.EffectType.ADD_RANDOM_RELIC:
			var all_relics := _scan_resources("res://resources/relics/")
			all_relics.shuffle()
			var count := mini(effect.param_int, all_relics.size())
			var names: PackedStringArray = []
			for j in range(count):
				var relic: RelicData = load(all_relics[j])
				if relic and not RogueBuffManager.has_relic(relic.id):
					RogueBuffManager.add_relic(relic)
					names.append(relic.display_name)
			return "获得遗物: %s" % ", ".join(names) if not names.is_empty() else "没有可用的遗物"

		RogueEffectEntry.EffectType.ADD_RANDOM_BUFF:
			## 已废弃，等同于 ADD_RANDOM_RELIC
			var compat_relics := _scan_resources("res://resources/relics/")
			compat_relics.shuffle()
			var compat_count := mini(effect.param_int, compat_relics.size())
			var compat_names: PackedStringArray = []
			for j in range(compat_count):
				var r: RelicData = load(compat_relics[j])
				if r and not RogueBuffManager.has_relic(r.id):
					RogueBuffManager.add_relic(r)
					compat_names.append(r.display_name)
			return "获得遗物: %s" % ", ".join(compat_names) if not compat_names.is_empty() else "没有可用的遗物"

		RogueEffectEntry.EffectType.ADD_RANDOM_ENCHANT:
			## 为随机卡牌添加随机附魔
			var all_enchants := _scan_resources("res://resources/enchants/")
			all_enchants.shuffle()
			var deck_plants := RogueState.deck.keys()
			if deck_plants.is_empty() or all_enchants.is_empty():
				return "没有可附魔的卡牌"
			var enchant_count := mini(effect.param_int, all_enchants.size())
			var enchant_names: PackedStringArray = []
			for j in range(enchant_count):
				var enchant: BuffData = load(all_enchants[j])
				if enchant:
					var target_plant = deck_plants[randi() % deck_plants.size()]
					RogueBuffManager.add_card_enchant(target_plant, enchant)
					enchant_names.append(enchant.display_name)
			return "获得附魔: %s" % ", ".join(enchant_names) if not enchant_names.is_empty() else "没有可用的附魔"

		RogueEffectEntry.EffectType.CHANCE:
			if randf() <= effect.param_float:
				var texts: PackedStringArray = []
				for sub in effect.sub_effects_success:
					var t: String = await _execute_effect(sub)
					if not t.is_empty():
						texts.append(t)
				return "成功! " + ", ".join(texts) if not texts.is_empty() else "成功!"
			else:
				var texts: PackedStringArray = []
				for sub in effect.sub_effects_fail:
					var t: String = await _execute_effect(sub)
					if not t.is_empty():
						texts.append(t)
				return "失败... " + ", ".join(texts) if not texts.is_empty() else "失败..."

		RogueEffectEntry.EffectType.CUSTOM:
			if has_method(effect.param_string):
				return call(effect.param_string)

		RogueEffectEntry.EffectType.ADD_ENCHANT_PICK_TARGET:
			var enchant_data: BuffData = load(effect.target_resource_path)
			if not enchant_data:
				return "附魔资源加载失败"
			## 创建附魔目标选择界面
			var picker_scene := preload("res://scenes/rogue/enchant_target_selection.tscn")
			var picker: EnchantTargetSelection = picker_scene.instantiate()
			var pick_count: int = effect.param_int if effect.param_int > 0 else 1
			picker.setup(enchant_data, pick_count)
			add_child(picker)
			## 等待玩家选择
			var selected_uids: Array = await picker.selection_completed
			if selected_uids.is_empty():
				return "取消了附魔"
			return "已为 %d 张卡牌附魔: %s" % [selected_uids.size(), enchant_data.display_name]

	return ""

# ══════════════════════════════════════════
#  工具方法
# ══════════════════════════════════════════

## 根据目录路径返回对应的资源路径列表
func _scan_resources(dir_path: String) -> Array[String]:
	if dir_path.begins_with("res://resources/relics"):
		return RELIC_PATHS.duplicate()
	elif dir_path.begins_with("res://resources/enchants"):
		return ENCHANT_PATHS.duplicate()
	elif dir_path.begins_with("res://resources/buff"):
		## 旧的 buff 目录已迁移到 relics
		return RELIC_PATHS.duplicate()
	return []

## 从字符串解析 PlantType 枚举
func _parse_plant_type(type_name: String) -> Variant:
	if type_name.is_empty():
		return null
	if CharacterRegistry.PlantType.has(type_name):
		return CharacterRegistry.PlantType[type_name]
	push_warning("[EventRoom] 未知的 PlantType: %s" % type_name)
	return null

func _on_continue_pressed() -> void:
	room_completed.emit()
