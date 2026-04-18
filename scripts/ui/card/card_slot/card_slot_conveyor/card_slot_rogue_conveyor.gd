extends PanelContainer
class_name CardSlotRogueConveyor
"""
肉鸽传送带卡槽：
- 库存中的植物以固定间隔随机出现在传送带上
- 当所有植物都已发到传送带后，等待恢复时间后重置库存并循环
- 卡牌需要消耗阳光
- 显示阳光槽
- 支持卡牌附魔系统（固有、消耗等）
"""

@onready var conveyor_belt_gear: ConveyorBeltGear = $ConveyorBeltGear
@onready var new_card_area: Panel = $NewCardArea
@onready var create_new_card_timer: Timer = $CreateNewCardTimer
@onready var sun_label_control: Control = $SunLabelControl
@onready var curr_sun_value_label: Label = $SunLabelControl/CurrSunValue
@onready var marker_2d_sun_target: Marker2D = %Marker2DSunTarget

var curr_cards: Array[Card] = []

@export_group("传送带参数")
## 最大卡片数量
@export var num_card_max: int = 10
## 每张卡片最终目标位置x
var all_card_pos_x_target: Array[float] = []
## 卡片移动速度
@export var conveyor_velocity: float = 30
## 卡片生成间隔（秒）
@export var create_new_card_cd: float = 10.0
## 卡组耗尽后恢复等待时间（秒）
@export var deck_restore_cd: float = 30.0

#region 循环卡组
## 卡组原始库存（每次循环重置用）: 植物类型 -> 数量
var deck_stock_original: Dictionary = {}  # CharacterRegistry.PlantType -> int
## 卡组当前库存：植物类型 -> 剩余数量
var deck_stock: Dictionary = {}  # CharacterRegistry.PlantType -> int
## 卡组顺序队列（打乱后按顺序发牌）
## 每个元素为 {plant_type: PlantType, uid: int}
var deck_queue: Array = []
## 本局中被"消耗"附魔排除的 UID
var consumed_uids: Dictionary = {}  # int (uid) -> true
## 是否正在等待恢复库存
var is_waiting_restore: bool = false
#endregion

## 是否正在运行中
var is_working := false
## 创建新卡片倍率
var create_new_card_speed: float = 1.0
## 卡片种植完成后信号
signal signal_card_end

## 阳光值
var sun_value: int = 50:
	set(value):
		sun_value = value
		if is_instance_valid(curr_sun_value_label):
			curr_sun_value_label.text = str(value)
		for card in curr_cards:
			card.judge_sun_enough(value)

#region 初始化

func _ready() -> void:
	_init_card_position_x()
	EventBus.subscribe("test_change_sun_value", func(value): sun_value = value)
	EventBus.subscribe("add_sun_value", _on_add_sun_value)

func _on_add_sun_value(value: int) -> void:
	sun_value += value
	if NetworkManager.is_multiplayer and NetworkManager.is_server():
		NetworkManager.sync_sun_value.rpc(sun_value)

func _init_card_position_x():
	for i in range(num_card_max):
		all_card_pos_x_target.append(0 + i * 50)

## 管理器初始化调用
func init_card_slot_rogue_conveyor(game_para: ResourceLevelData):
	self.create_new_card_speed = game_para.create_new_card_speed
	create_new_card_cd = create_new_card_cd / create_new_card_speed
	create_new_card_timer.wait_time = create_new_card_cd

	## 初始化阳光
	self.sun_value = game_para.start_sun

	## 从概率字典构建卡组原始库存
	deck_stock_original = {}
	for plant_type in game_para.all_card_plant_type_probability:
		var count: int = game_para.all_card_plant_type_probability[plant_type]
		if count > 0:
			deck_stock_original[plant_type] = count

	## 重置消耗记录
	consumed_uids = {}

	## 构建当前库存和发牌队列
	_restore_deck_stock()

	## 更新阳光收集位置
	EventBus.push_event("update_marker_2d_sun_target", marker_2d_sun_target)

	await get_tree().process_frame
	## 先发"固有"附魔的卡牌
	_create_inherent_cards()
	## 然后开始正常发牌
	_create_new_card()

## 恢复卡组库存（循环时调用）
func _restore_deck_stock():
	deck_stock = {}
	for plant_type in deck_stock_original:
		var original_count: int = deck_stock_original[plant_type]
		## 计算该类型中被消耗附魔移除的数量
		var consumed_count: int = 0
		if RogueState.card_uids.has(plant_type):
			for uid in RogueState.card_uids[plant_type]:
				if consumed_uids.has(uid):
					consumed_count += 1
		var remaining: int = original_count - consumed_count
		if remaining > 0:
			deck_stock[plant_type] = remaining
	_rebuild_deck_queue()
	is_waiting_restore = false

## 根据当前库存构建打乱的发牌队列（排除"固有"卡和已消耗的卡）
func _rebuild_deck_queue():
	deck_queue.clear()
	for plant_type in deck_stock:
		if not RogueState.card_uids.has(plant_type):
			continue
		for uid in RogueState.card_uids[plant_type]:
			## 跳过已被消耗附魔移除的卡
			if consumed_uids.has(uid):
				continue
			## 跳过"固有"附魔的卡（它们单独处理）
			if RogueBuffManager.instance_has_enchant(uid, &"inherent"):
				continue
			deck_queue.append({"plant_type": plant_type, "uid": uid})
	deck_queue.shuffle()
	print("肉鸽传送带卡组队列（%d张）" % deck_queue.size())

## 生成所有"固有"附魔的卡牌（在每个循环开始时立即出现）
func _create_inherent_cards():
	var inherent_entries: Array = []
	for plant_type in deck_stock:
		if not RogueState.card_uids.has(plant_type):
			continue
		for uid in RogueState.card_uids[plant_type]:
			if consumed_uids.has(uid):
				continue
			if RogueBuffManager.instance_has_enchant(uid, &"inherent"):
				inherent_entries.append({"plant_type": plant_type, "uid": uid})
	for entry in inherent_entries:
		if curr_cards.size() >= num_card_max:
			break
		_spawn_card(entry.plant_type, entry.uid)

#endregion

func _process(delta: float) -> void:
	if is_working:
		for i in curr_cards.size():
			if curr_cards[i].position.x > all_card_pos_x_target[i]:
				curr_cards[i].position.x -= delta * conveyor_velocity
			elif curr_cards[i].position.x == all_card_pos_x_target[i]:
				continue
			else:
				curr_cards[i].position.x = all_card_pos_x_target[i]

#region 卡片生成相关
## 卡片种植完成后
func card_use_end(card: Card):
	## 扣除阳光
	sun_value = sun_value - card.sun_cost
	var plant_type = card.card_plant_type
	var card_uid: int = card.get_meta("card_uid", -1)
	curr_cards.erase(card)
	card.queue_free()
	## 如果该卡牌实例有"消耗"附魔，记录消耗（不进入后续循环）
	if card_uid >= 0 and RogueBuffManager.instance_has_enchant(card_uid, &"consumable"):
		consumed_uids[card_uid] = true
		print("肉鸽传送带：uid=%d (%s) 被消耗附魔移出后续循环" % [card_uid, str(plant_type)])
	signal_card_end.emit()

func _on_create_new_card_timer_timeout() -> void:
	_create_new_card()

## 生成一张新卡片
func _create_new_card():
	## 卡组已空 → 开始等待恢复
	if deck_queue.is_empty():
		create_new_card_timer.stop()
		if not is_waiting_restore:
			is_waiting_restore = true
			print("肉鸽传送带：本轮卡组已发完，等待 %.0f 秒后恢复库存" % deck_restore_cd)
			## 等待恢复时间
			await get_tree().create_timer(deck_restore_cd).timeout
			if not is_working:
				return
			## 恢复库存并重新开始循环
			_restore_deck_stock()
			print("肉鸽传送带：库存已恢复，开始新一轮发牌")
			_create_inherent_cards()
			_create_new_card()
			if not deck_queue.is_empty():
				create_new_card_timer.start()
		return

	if curr_cards.size() >= num_card_max:
		create_new_card_timer.stop()
		await signal_card_end
		## 再次检查卡组是否为空
		if deck_queue.is_empty():
			## 卡组空了但传送带满，仍然进入等待恢复流程
			_create_new_card()
			return
		create_new_card_timer.start()

	## 从队列中取出下一张
	var entry = deck_queue.pop_front()
	_spawn_card(entry.plant_type, entry.uid)

## 实际生成卡片实例
func _spawn_card(plant_type, card_uid: int = -1) -> void:
	var new_card_prefabs: Card = AllCards.all_plant_card_prefabs[plant_type]
	var new_card = new_card_prefabs.duplicate()
	new_card_area.add_child(new_card)
	new_card.card_init_rogue_conveyor()
	new_card.position = Vector2(new_card_area.size.x, 0)
	curr_cards.append(new_card)
	new_card.signal_card_use_end.connect(card_use_end.bind(new_card))
	new_card.judge_sun_enough(sun_value)
	var card_bg: TextureRect = new_card.get_node("CardBg")
	card_bg.clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
	## 设置卡牌 UID
	new_card.set_meta("card_uid", card_uid)
	## 检查该实例是否有"南瓜灯"附魔
	if card_uid >= 0 and RogueBuffManager.instance_has_enchant(card_uid, &"pumpkin"):
		new_card.set_meta("enchant_pumpkin", true)

#endregion

#region 传送带开始与结束
func start_conveyor_belt():
	is_working = true
	is_waiting_restore = false
	conveyor_belt_gear.start_gear()
	if not deck_queue.is_empty():
		create_new_card_timer.start()

func stop_conveyor_belt():
	is_working = false
	is_waiting_restore = false
	conveyor_belt_gear.stop_gear()
	create_new_card_timer.stop()

## 移动卡槽（出现或隐藏）
func move_card_slot_conveyor_belt(is_appeal: bool):
	var tween = create_tween()
	if is_appeal:
		tween.tween_property(self, "position:y", 0, 0.2)
	else:
		tween.tween_property(self, "position:y", -100, 0.2)
	await tween.finished
#endregion
