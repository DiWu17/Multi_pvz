extends PanelContainer
class_name CardSlotRogueConveyor
"""
肉鸽传送带卡槽：
- 卡组有限，按库存随机发牌，送完为止
- 卡牌需要消耗阳光
- 显示阳光槽
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
## 卡片生成时间
@export var create_new_card_cd: float = 5

#region 有限卡组
## 卡组库存：植物类型 -> 剩余数量
var deck_stock: Dictionary = {}  # CharacterRegistry.PlantType -> int
## 卡组顺序队列（打乱后按顺序发牌）
var deck_queue: Array = []  # Array[CharacterRegistry.PlantType]
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

	## 从概率字典构建有限卡组（概率值就是库存数量）
	deck_stock = {}
	for plant_type in game_para.all_card_plant_type_probability:
		var count: int = game_para.all_card_plant_type_probability[plant_type]
		if count > 0:
			deck_stock[plant_type] = count

	## 构建并打乱发牌队列
	_rebuild_deck_queue()

	## 更新阳光收集位置
	EventBus.push_event("update_marker_2d_sun_target", marker_2d_sun_target)

	await get_tree().process_frame
	## 初始化后生成一个卡片
	_create_new_card()

## 根据当前库存构建打乱的发牌队列
func _rebuild_deck_queue():
	deck_queue.clear()
	for plant_type in deck_stock:
		for i in range(deck_stock[plant_type]):
			deck_queue.append(plant_type)
	deck_queue.shuffle()
	print("肉鸽传送带卡组队列（%d张）：%s" % [deck_queue.size(), str(deck_queue)])

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
	curr_cards.erase(card)
	card.queue_free()
	signal_card_end.emit()

func _on_create_new_card_timer_timeout() -> void:
	_create_new_card()

## 生成一张新卡片
func _create_new_card():
	## 卡组已空，不再生成
	if deck_queue.is_empty():
		create_new_card_timer.stop()
		print("肉鸽传送带：卡组已空，停止生成")
		return

	if curr_cards.size() >= num_card_max:
		create_new_card_timer.stop()
		await signal_card_end
		## 再次检查卡组是否为空
		if deck_queue.is_empty():
			return
		create_new_card_timer.start()

	## 从队列中取出下一张
	var plant_type = deck_queue.pop_front()
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

#endregion

#region 传送带开始与结束
func start_conveyor_belt():
	is_working = true
	conveyor_belt_gear.start_gear()
	if not deck_queue.is_empty():
		create_new_card_timer.start()

func stop_conveyor_belt():
	is_working = false
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
