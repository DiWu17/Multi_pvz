extends Control
## 多人大厅 UI
## 创建房间、输入 IP、玩家列表、准备/开始

@onready var panel_main: PanelContainer = $PanelMain
@onready var tab_container: TabContainer = $PanelMain/MarginContainer/VBoxContainer/TabContainer

# 创建/加入 tab
@onready var input_player_name: LineEdit = $PanelMain/MarginContainer/VBoxContainer/TabContainer/创建房间/VBoxContainer/InputPlayerName
@onready var input_port: SpinBox = $PanelMain/MarginContainer/VBoxContainer/TabContainer/创建房间/VBoxContainer/InputPort
@onready var btn_create: Button = $PanelMain/MarginContainer/VBoxContainer/TabContainer/创建房间/VBoxContainer/BtnCreate

@onready var input_join_name: LineEdit = $PanelMain/MarginContainer/VBoxContainer/TabContainer/加入房间/VBoxContainer/InputJoinName
@onready var input_address: LineEdit = $PanelMain/MarginContainer/VBoxContainer/TabContainer/加入房间/VBoxContainer/InputAddress
@onready var input_join_port: SpinBox = $PanelMain/MarginContainer/VBoxContainer/TabContainer/加入房间/VBoxContainer/InputJoinPort
@onready var btn_join: Button = $PanelMain/MarginContainer/VBoxContainer/TabContainer/加入房间/VBoxContainer/BtnJoin

# 中继 tab
@onready var input_relay_address: LineEdit = $PanelMain/MarginContainer/VBoxContainer/TabContainer/服务器中转/VBoxContainer/InputRelayAddress
@onready var input_relay_port: SpinBox = $PanelMain/MarginContainer/VBoxContainer/TabContainer/服务器中转/VBoxContainer/InputRelayPort
@onready var input_relay_name: LineEdit = $PanelMain/MarginContainer/VBoxContainer/TabContainer/服务器中转/VBoxContainer/InputRelayName
@onready var btn_relay_create: Button = $PanelMain/MarginContainer/VBoxContainer/TabContainer/服务器中转/VBoxContainer/BtnRelayCreate
@onready var input_relay_room_code: LineEdit = $PanelMain/MarginContainer/VBoxContainer/TabContainer/服务器中转/VBoxContainer/InputRelayRoomCode
@onready var btn_relay_join: Button = $PanelMain/MarginContainer/VBoxContainer/TabContainer/服务器中转/VBoxContainer/BtnRelayJoin

# WebRTC tab (新增)
var input_webrtc_signaling_url: LineEdit = null
var input_webrtc_name: LineEdit = null
var btn_webrtc_create: Button = null
var input_webrtc_room_code: LineEdit = null
var btn_webrtc_join: Button = null
var label_webrtc_room_code: Label = null  # 显示生成的房间码
var _webrtc_player_list: VBoxContainer = null  # 显示房间内玩家列表

@onready var btn_back: Button = $PanelMain/MarginContainer/VBoxContainer/HBoxTitle/BtnBack
# 大厅 panel
@onready var panel_lobby: PanelContainer = $PanelLobby
@onready var player_list: VBoxContainer = $PanelLobby/MarginContainer/VBoxContainer/ScrollContainer/PlayerList
@onready var btn_ready: Button = $PanelLobby/MarginContainer/VBoxContainer/HBoxContainer/BtnReady
@onready var btn_start: Button = $PanelLobby/MarginContainer/VBoxContainer/HBoxContainer/BtnStart
@onready var btn_leave: Button = $PanelLobby/MarginContainer/VBoxContainer/HBoxContainer/BtnLeave
@onready var label_status: Label = $PanelLobby/MarginContainer/VBoxContainer/LabelStatus

## 游戏模式选择器（动态创建，仅 Host 可见）
var _mode_selector: OptionButton = null
## 模式映射表 (OptionButton index → MainScenes)
const GAME_MODE_OPTIONS: Array[Dictionary] = [
	{"label": "冒险模式", "mode": MainSceneRegistry.MainScenes.ChooseLevelAdventure},
	{"label": "生存模式", "mode": MainSceneRegistry.MainScenes.ChooseLevelSurvival},
	{"label": "迷你游戏", "mode": MainSceneRegistry.MainScenes.ChooseLevelMiniGame},
	{"label": "解密模式", "mode": MainSceneRegistry.MainScenes.ChooseLevelPuzzle},
	{"label": "自定义关卡", "mode": MainSceneRegistry.MainScenes.ChooseLevelCustom},
]

signal signal_lobby_closed

func _ready() -> void:
	panel_lobby.visible = false
	panel_main.visible = true

	btn_back.pressed.connect(_on_btn_back_pressed)
	btn_create.pressed.connect(_on_btn_create_pressed)
	btn_join.pressed.connect(_on_btn_join_pressed)
	btn_relay_create.pressed.connect(_on_btn_relay_create_pressed)
	btn_relay_join.pressed.connect(_on_btn_relay_join_pressed)
	btn_ready.pressed.connect(_on_btn_ready_pressed)
	btn_start.pressed.connect(_on_btn_start_pressed)
	btn_leave.pressed.connect(_on_btn_leave_pressed)

	# 创建 WebRTC tab UI
	_create_webrtc_tab()
	_refresh_webrtc_ui_state()

	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.player_list_updated.connect(_on_player_list_updated)
	NetworkManager.server_connected.connect(_on_server_connected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)
	NetworkManager.connection_failed.connect(_on_connection_failed)
	NetworkManager.all_players_ready.connect(_on_all_players_ready)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.relay_room_created.connect(_on_relay_room_created)
	
	# WebRTC 信号监听 (新增)
	NetworkManager.webrtc_room_created.connect(_on_webrtc_room_created)

	input_port.value = NetworkManager.DEFAULT_PORT
	input_join_port.value = NetworkManager.DEFAULT_PORT

## 返回主菜单
func _on_btn_back_pressed() -> void:
	queue_free()

## 创建房间
func _on_btn_create_pressed() -> void:
	var player_name = input_player_name.text.strip_edges()
	if player_name.is_empty():
		player_name = "Host"
	var port = int(input_port.value)
	var error = NetworkManager.create_server(port, player_name)
	if error == OK:
		_show_lobby()
		btn_start.visible = true  # Host 可见开始按钮
	else:
		label_status.text = "创建失败: %d" % error

## 创建中转房间
func _on_btn_relay_create_pressed() -> void:
	var player_name = input_relay_name.text.strip_edges()
	if player_name.is_empty():
		player_name = "Host"
	var address = input_relay_address.text.strip_edges()
	if address.is_empty():
		label_status.text = "请输入服务器地址"
		return
	var port = int(input_relay_port.value)
	var url = "ws://%s:%d" % [address, port]
	var error = NetworkManager.create_relay_host(url, player_name)
	if error == OK:
		label_status.text = "正在连接中继服务器..."
	else:
		label_status.text = "连接失败: %d" % error

## 加入中转房间
func _on_btn_relay_join_pressed() -> void:
	var player_name = input_relay_name.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player"
	var address = input_relay_address.text.strip_edges()
	if address.is_empty():
		label_status.text = "请输入服务器地址"
		return
	var room_code = input_relay_room_code.text.strip_edges().to_upper()
	if room_code.is_empty():
		label_status.text = "请输入房间码"
		return
	var port = int(input_relay_port.value)
	var url = "ws://%s:%d" % [address, port]
	var error = NetworkManager.join_relay_room(url, room_code, player_name)
	if error == OK:
		label_status.text = "正在连接中继服务器..."
	else:
		label_status.text = "连接失败: %d" % error

## 加入房间
func _on_btn_join_pressed() -> void:
	var player_name = input_join_name.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player"
	var address = input_address.text.strip_edges()
	if address.is_empty():
		address = "127.0.0.1"
	var port = int(input_join_port.value)
	var error = NetworkManager.join_server(address, port, player_name)
	if error == OK:
		label_status.text = "正在连接..."
	else:
		label_status.text = "连接失败: %d" % error

#region WebRTC 方法 (新增)

func _refresh_webrtc_ui_state() -> void:
	var available := NetworkManager.is_webrtc_available()
	if btn_webrtc_create:
		btn_webrtc_create.disabled = not available
	if btn_webrtc_join:
		btn_webrtc_join.disabled = not available
	if not label_webrtc_room_code:
		return
	if available:
		label_webrtc_room_code.text = "房间码将显示在这里..."
		return
	var reason := NetworkManager.get_webrtc_unavailable_reason()
	label_webrtc_room_code.text = reason
	label_webrtc_room_code.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))

## 创建 WebRTC tab UI
func _create_webrtc_tab() -> void:
	# 检查是否已有 WebRTC tab，没有则动态创建
	var webrtc_tab = tab_container.get_node_or_null("WebRTC")
	if webrtc_tab != null:
		# 直接引用现有的 tab
		var vbox = webrtc_tab.get_node("VBoxContainer")
		if vbox:
			input_webrtc_signaling_url = vbox.get_node_or_null("InputSignalingUrl")
			input_webrtc_name = vbox.get_node_or_null("InputName")
			btn_webrtc_create = vbox.get_node_or_null("BtnCreate")
			input_webrtc_room_code = vbox.get_node_or_null("InputRoomCode")
			btn_webrtc_join = vbox.get_node_or_null("BtnJoin")
			label_webrtc_room_code = vbox.get_node_or_null("LabelRoomCode")
			
			if btn_webrtc_create:
				btn_webrtc_create.pressed.connect(_on_btn_webrtc_create_pressed)
			if btn_webrtc_join:
				btn_webrtc_join.pressed.connect(_on_btn_webrtc_join_pressed)
		return
	
	# 如果不存在，则动态创建
	var panel_container = PanelContainer.new()
	panel_container.name = "WebRTC"
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel_container.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	margin.add_child(vbox)
	
	# 标题
	var title = Label.new()
	title.text = "🔴 WebRTC 点对点连接 (低延迟，推荐)"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)
	
	var separator1 = HSeparator.new()
	vbox.add_child(separator1)
	
	# 信令服务器地址
	var signaling_label = Label.new()
	signaling_label.text = "信令服务器 (Signaling URL):"
	vbox.add_child(signaling_label)
	
	input_webrtc_signaling_url = LineEdit.new()
	input_webrtc_signaling_url.name = "InputSignalingUrl"
	input_webrtc_signaling_url.placeholder_text = "ws://localhost:8080"
	input_webrtc_signaling_url.text = "ws://127.0.0.1:8080"
	vbox.add_child(input_webrtc_signaling_url)
	
	# 玩家名
	var name_label = Label.new()
	name_label.text = "玩家名称:"
	vbox.add_child(name_label)
	
	input_webrtc_name = LineEdit.new()
	input_webrtc_name.name = "InputName"
	input_webrtc_name.placeholder_text = "输入你的名字"
	input_webrtc_name.text = "Player"
	vbox.add_child(input_webrtc_name)
	
	var separator2 = HSeparator.new()
	vbox.add_child(separator2)
	
	# 创建房间
	var create_section = Label.new()
	create_section.text = "【创建房间 - 作为主机(Host)】"
	create_section.add_theme_font_size_override("font_size", 12)
	vbox.add_child(create_section)
	
	btn_webrtc_create = Button.new()
	btn_webrtc_create.name = "BtnCreate"
	btn_webrtc_create.text = "创建 WebRTC 房间"
	btn_webrtc_create.pressed.connect(_on_btn_webrtc_create_pressed)
	vbox.add_child(btn_webrtc_create)
	
	# 显示房间码
	label_webrtc_room_code = Label.new()
	label_webrtc_room_code.name = "LabelRoomCode"
	label_webrtc_room_code.text = "房间码将显示在这里..."
	label_webrtc_room_code.add_theme_color_override("font_color", Color.YELLOW)
	vbox.add_child(label_webrtc_room_code)
	
	var separator3 = HSeparator.new()
	vbox.add_child(separator3)
	
	# 加入房间
	var join_section = Label.new()
	join_section.text = "【加入房间 - 作为客户端(Client)】"
	join_section.add_theme_font_size_override("font_size", 12)
	vbox.add_child(join_section)
	
	var room_code_label = Label.new()
	room_code_label.text = "房间码 (从主机处获得):"
	vbox.add_child(room_code_label)
	
	input_webrtc_room_code = LineEdit.new()
	input_webrtc_room_code.name = "InputRoomCode"
	input_webrtc_room_code.placeholder_text = "输入房间码"
	input_webrtc_room_code.text = ""
	vbox.add_child(input_webrtc_room_code)
	
	btn_webrtc_join = Button.new()
	btn_webrtc_join.name = "BtnJoin"
	btn_webrtc_join.text = "加入 WebRTC 房间"
	btn_webrtc_join.pressed.connect(_on_btn_webrtc_join_pressed)
	vbox.add_child(btn_webrtc_join)
	
	var separator4 = HSeparator.new()
	vbox.add_child(separator4)
	
	# 玩家列表（WebRTC 中显示）
	var players_label = Label.new()
	players_label.text = "【房间内玩家】"
	players_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(players_label)
	
	_webrtc_player_list = VBoxContainer.new()
	_webrtc_player_list.name = "WebRTCPlayerList"
	vbox.add_child(_webrtc_player_list)
	
	# 添加到 tab 容器
	tab_container.add_child(panel_container)

## WebRTC 创建房间
func _on_btn_webrtc_create_pressed() -> void:
	var player_name = input_webrtc_name.text.strip_edges()
	if player_name.is_empty():
		player_name = "Host"
	
	var signaling_url = input_webrtc_signaling_url.text.strip_edges()
	if signaling_url.is_empty():
		signaling_url = "ws://127.0.0.1:8080"
	
	label_status.text = "正在连接 WebRTC 信令服务器: %s..." % signaling_url
	print("WebRTC: 创建房间，玩家名: %s，信令地址: %s" % [player_name, signaling_url])
	
	var error = NetworkManager.create_webrtc_host(signaling_url, player_name)
	if error != OK:
		var detail := NetworkManager.get_last_network_error()
		label_status.text = detail if not detail.is_empty() else "WebRTC 房间创建失败: 错误码 %d" % error
		print("错误: ", error)

## WebRTC 加入房间
func _on_btn_webrtc_join_pressed() -> void:
	var player_name = input_webrtc_name.text.strip_edges()
	if player_name.is_empty():
		player_name = "Player"
	
	var signaling_url = input_webrtc_signaling_url.text.strip_edges()
	if signaling_url.is_empty():
		signaling_url = "ws://127.0.0.1:8080"
	
	var room_code = input_webrtc_room_code.text.strip_edges().to_upper()
	if room_code.is_empty():
		label_status.text = "请输入房间码"
		return
	
	label_status.text = "正在加入 WebRTC 房间: %s..." % room_code
	print("WebRTC: 加入房间，房间码: %s，玩家名: %s" % [room_code, player_name])
	
	var error = NetworkManager.join_webrtc_room(signaling_url, room_code, player_name)
	if error != OK:
		var detail := NetworkManager.get_last_network_error()
		label_status.text = detail if not detail.is_empty() else "加入 WebRTC 房间失败: 错误码 %d" % error

## WebRTC 房间创建成功回调
func _on_webrtc_room_created(room_code: String) -> void:
	print("UI: WebRTC 房间创建成功回调收到，房间码: ", room_code)
	print("UI: label_webrtc_room_code 是否为 null: ", label_webrtc_room_code == null)
	if label_webrtc_room_code:
		print("UI: 更新房间码标签为: ", room_code)
		label_webrtc_room_code.text = "✓ 房间码: [%s]\n(已生成，分享给其他玩家)" % room_code
	else:
		print("UI: 警告！label_webrtc_room_code 为 null，无法显示房间码")

	_show_lobby()
	btn_start.visible = true
	label_status.text = "WebRTC 房间码: %s | 等待玩家加入..." % room_code

#endregion

## 切换到大厅面板
func _show_lobby() -> void:
	panel_main.visible = false
	panel_lobby.visible = true
	btn_start.visible = NetworkManager.is_server()
	btn_start.disabled = true
	_create_mode_selector()
	_refresh_player_list()
	_refresh_webrtc_player_list()

## 创建游戏模式选择器（仅 Host 可操作）
func _create_mode_selector() -> void:
	if is_instance_valid(_mode_selector):
		return
	var hbox = HBoxContainer.new()
	hbox.name = "GameModeRow"
	var mode_label = Label.new()
	mode_label.text = "游戏模式: "
	hbox.add_child(mode_label)

	_mode_selector = OptionButton.new()
	_mode_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for opt in GAME_MODE_OPTIONS:
		_mode_selector.add_item(opt["label"])
	_mode_selector.selected = 0
	_mode_selector.item_selected.connect(_on_mode_selected)
	# 客户端不能修改模式
	if not NetworkManager.is_server():
		_mode_selector.disabled = true
	hbox.add_child(_mode_selector)

	# 插入到 LabelStatus 前面
	var lobby_vbox = label_status.get_parent()
	var status_idx = label_status.get_index()
	lobby_vbox.add_child(hbox)
	lobby_vbox.move_child(hbox, status_idx)

## 模式选择变更
func _on_mode_selected(index: int) -> void:
	if index >= 0 and index < GAME_MODE_OPTIONS.size():
		NetworkManager.selected_game_mode = GAME_MODE_OPTIONS[index]["mode"]

## 刷新玩家列表
func _refresh_player_list() -> void:
	# 清空
	for child in player_list.get_children():
		child.queue_free()

	for peer_id in NetworkManager.players:
		var info = NetworkManager.players[peer_id]
		var hbox = HBoxContainer.new()

		# 颜色标记
		var color_rect = ColorRect.new()
		color_rect.custom_minimum_size = Vector2(20, 20)
		color_rect.color = NetworkManager.PLAYER_COLORS[info.get("color_index", 0)]
		hbox.add_child(color_rect)

		# 玩家名
		var name_label = Label.new()
		name_label.text = "  %s" % info.get("name", "Unknown")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(name_label)

		# 准备状态
		var ready_label = Label.new()
		if info.get("is_ready", false):
			ready_label.text = "✔ 已准备"
			ready_label.add_theme_color_override("font_color", Color.GREEN)
		else:
			ready_label.text = "未准备"
			ready_label.add_theme_color_override("font_color", Color.GRAY)
		hbox.add_child(ready_label)

		# Host 标记
		if peer_id == 1:
			var host_label = Label.new()
			host_label.text = " [Host]"
			host_label.add_theme_color_override("font_color", Color.GOLD)
			hbox.add_child(host_label)

		player_list.add_child(hbox)

	var status_text = "玩家数: %d / %d" % [NetworkManager.player_count, NetworkManager.MAX_PLAYERS]

	# 显示房间码（支持 Relay 和 WebRTC）
	if NetworkManager.relay_room_code != "":
		status_text = "中继房间码: %s | %s" % [NetworkManager.relay_room_code, status_text]
	elif NetworkManager.webrtc_room_code != "":
		status_text = "WebRTC 房间码: %s | %s" % [NetworkManager.webrtc_room_code, status_text]

	label_status.text = status_text

## 刷新 WebRTC 玩家列表
func _refresh_webrtc_player_list() -> void:
	if not _webrtc_player_list:
		return
	
	# 清空
	for child in _webrtc_player_list.get_children():
		child.queue_free()
	
	# 添加所有玩家
	for peer_id in NetworkManager.players:
		var info = NetworkManager.players[peer_id]
		var player_label = Label.new()
		var status_text = "✓ 已准备" if info.get("is_ready", false) else "⧖ 未准备"
		player_label.text = "• %s (Peer %d) %s" % [info.get("name", "Unknown"), peer_id, status_text]
		_webrtc_player_list.add_child(player_label)

## 准备
func _on_btn_ready_pressed() -> void:
	NetworkManager.toggle_ready()

## Host 开始游戏
func _on_btn_start_pressed() -> void:
	NetworkManager.start_game()

## 离开房间
func _on_btn_leave_pressed() -> void:
	NetworkManager.disconnect_from_server()
	panel_lobby.visible = false
	panel_main.visible = true
	label_status.text = ""

## 中继房间创建成功
func _on_relay_room_created(room_code: String) -> void:
	_show_lobby()
	btn_start.visible = true
	label_status.text = "房间码: %s | 等待玩家加入..." % room_code

#region 网络回调
func _on_player_joined(_peer_id: int, _info: Dictionary) -> void:
	_refresh_player_list()
	_refresh_webrtc_player_list()

func _on_player_left(_peer_id: int) -> void:
	_refresh_player_list()
	_refresh_webrtc_player_list()

func _on_player_list_updated() -> void:
	_refresh_player_list()
	_refresh_webrtc_player_list()

func _on_server_connected() -> void:
	_show_lobby()
	btn_start.visible = false  # Client 不可见开始按钮

func _on_server_disconnected() -> void:
	panel_lobby.visible = false
	panel_main.visible = true
	label_status.text = "服务器已断开"

func _on_connection_failed() -> void:
	var detail := NetworkManager.get_last_network_error()
	label_status.text = detail if not detail.is_empty() else "连接失败"

func _on_all_players_ready() -> void:
	if NetworkManager.is_server():
		btn_start.disabled = false

func _on_game_started() -> void:
	signal_lobby_closed.emit()
	queue_free()
#endregion
