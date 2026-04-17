extends Control
class_name RestRoom

## 篝火房间 - 休息节点，可升级植物或恢复阳光

signal room_completed()

@onready var background: TextureRect = $Background
@onready var continue_button: Button = $ContinueButton
@onready var title_label: Label = $TitleLabel
@onready var upgrade_button: Button = $ChoiceContainer/UpgradeButton
@onready var heal_button: Button = $ChoiceContainer/HealButton
@onready var result_label: RichTextLabel = $ResultLabel

var _choice_made: bool = false

func _ready() -> void:
	continue_button.pressed.connect(_on_continue_pressed)
	continue_button.visible = false
	if result_label:
		result_label.visible = false

	if title_label:
		title_label.text = "篝火休息"

	if upgrade_button:
		upgrade_button.text = "升级一张植物"
		upgrade_button.pressed.connect(_on_upgrade)
	if heal_button:
		heal_button.text = "恢复100阳光"
		heal_button.pressed.connect(_on_heal)

func _on_upgrade() -> void:
	if _choice_made:
		return
	_choice_made = true
	_hide_choices()
	# TODO: 打开植物选择界面，选择一张植物升星
	if result_label:
		result_label.text = "你选择升级了一张植物！\n（功能待接入肉鸽状态管理器）"
		result_label.visible = true
	continue_button.visible = true

func _on_heal() -> void:
	if _choice_made:
		return
	_choice_made = true
	_hide_choices()
	# TODO: 增加100初始阳光到肉鸽全局状态
	if result_label:
		result_label.text = "你恢复了100阳光！\n（功能待接入肉鸽状态管理器）"
		result_label.visible = true
	continue_button.visible = true

func _hide_choices() -> void:
	if upgrade_button:
		upgrade_button.visible = false
	if heal_button:
		heal_button.visible = false

func _on_continue_pressed() -> void:
	room_completed.emit()
