## 网络模式选择器示例脚本
## 展示如何在游戏中使用不同的网络模式
## 放在: scenes/start_menu/ 目录

extends Control
## 网络模式选择器

@onready var network_mode_buttons = %NetworkModeButtons  # VBoxContainer
@onready var server_address_input = %ServerAddressInput
@onready var port_input = %PortInput
@onready var player_name_input = %PlayerNameInput
@onready var room_code_input = %RoomCodeInput
@onready var connect_button = %ConnectButton
@onready var host_button = %HostButton
@onready var join_button = %JoinButton
@onready var status_label = %StatusLabel

var selected_network_mode: int = NetworkManager.NetworkMode.ENET
var signaling_url: String = "ws://localhost:8080"

func _ready() -> void:
    # 创建网络模式按钮
    _create_network_mode_buttons()
    
    # 连接信号
    connect_button.pressed.connect(_on_connect_pressed)
    host_button.pressed.connect(_on_host_pressed)
    join_button.pressed.connect(_on_join_pressed)
    
    # 连接 NetworkManager 信号
    NetworkManager.server_connected.connect(_on_server_connected)
    NetworkManager.connection_failed.connect(_on_connection_failed)
    NetworkManager.relay_room_created.connect(_on_relay_room_created)
    NetworkManager.webrtc_room_created.connect(_on_webrtc_room_created)
    
    # 初始状态
    player_name_input.text = "Player_%d" % randi() % 1000
    server_address_input.text = "127.0.0.1"
    port_input.text = "27015"
    
    _update_ui_for_mode()

func _create_network_mode_buttons() -> void:
    """创建网络模式选择按钮"""
    
    # ENet 直连
    var enet_button = Button.new()
    enet_button.text = "🔗 ENet 直连 (局域网)"
    enet_button.custom_minimum_size = Vector2(400, 60)
    enet_button.pressed.connect(func(): _select_network_mode(NetworkManager.NetworkMode.ENET))
    network_mode_buttons.add_child(enet_button)
    
    # 中继服务器
    var relay_button = Button.new()
    relay_button.text = "🌐 中继服务器 (跨域)"
    relay_button.custom_minimum_size = Vector2(400, 60)
    relay_button.pressed.connect(func(): _select_network_mode(NetworkManager.NetworkMode.RELAY))
    network_mode_buttons.add_child(relay_button)
    
    # WebRTC
    var webrtc_button = Button.new()
    webrtc_button.text = "🔴 WebRTC P2P (点对点)"
    webrtc_button.custom_minimum_size = Vector2(400, 60)
    webrtc_button.pressed.connect(func(): _select_network_mode(NetworkManager.NetworkMode.WEBRTC))
    network_mode_buttons.add_child(webrtc_button)

func _select_network_mode(mode: int) -> void:
    """选择网络模式"""
    selected_network_mode = mode
    _update_ui_for_mode()

func _update_ui_for_mode() -> void:
    """根据选中的网络模式更新UI"""
    
    match selected_network_mode:
        NetworkManager.NetworkMode.ENET:
            status_label.text = "已选择: ENet 直连\n[适合局域网，需要IP地址和端口]"
            server_address_input.visible = true
            port_input.visible = true
            room_code_input.visible = false
            connect_button.visible = true
            host_button.visible = false
            join_button.visible = false
        
        NetworkManager.NetworkMode.RELAY:
            status_label.text = "已选择: 中继服务器\n[跨域连接，需要中继服务器地址]"
            server_address_input.visible = true
            port_input.visible = false
            room_code_input.visible = false
            connect_button.visible = true
            host_button.visible = false
            join_button.visible = false
        
        NetworkManager.NetworkMode.WEBRTC:
            status_label.text = "已选择: WebRTC P2P\n[点对点通信，需要信令服务器]"
            server_address_input.visible = true
            port_input.visible = false
            room_code_input.visible = true
            connect_button.visible = false
            host_button.visible = true
            join_button.visible = true

func _on_connect_pressed() -> void:
    """ENet/Relay 连接按钮"""
    var player_name = player_name_input.text
    
    match selected_network_mode:
        NetworkManager.NetworkMode.ENET:
            # ENet 直连
            var address = server_address_input.text
            var port = int(port_input.text)
            status_label.text = "正在连接到 %s:%d..." % [address, port]
            
            var error = NetworkManager.join_server(address, port, player_name)
            if error != OK:
                status_label.text = "连接失败: 错误码 %d" % error
        
        NetworkManager.NetworkMode.RELAY:
            # 中继服务器
            var relay_url = server_address_input.text
            status_label.text = "正在连接到中继服务器: %s..." % relay_url
            
            # 这里应该有 relay_url 输入，假设是完整的 URL
            var error = NetworkManager.create_relay_host(relay_url, player_name)
            if error != OK:
                status_label.text = "连接失败: 错误码 %d" % error

func _on_host_pressed() -> void:
    """WebRTC 创建房间按钮"""
    var player_name = player_name_input.text
    signaling_url = server_address_input.text
    
    status_label.text = "正在创建 WebRTC 房间..."
    
    var error = NetworkManager.create_webrtc_host(signaling_url, player_name)
    if error != OK:
        status_label.text = "创建房间失败: 错误码 %d" % error

func _on_join_pressed() -> void:
    """WebRTC 加入房间按钮"""
    var player_name = player_name_input.text
    var room_code = room_code_input.text
    signaling_url = server_address_input.text
    
    if room_code.is_empty():
        status_label.text = "请输入房间码"
        return
    
    status_label.text = "正在加入 WebRTC 房间: %s..." % room_code
    
    var error = NetworkManager.join_webrtc_room(signaling_url, room_code, player_name)
    if error != OK:
        status_label.text = "加入房间失败: 错误码 %d" % error

func _on_server_connected() -> void:
    """服务器连接成功"""
    status_label.text = "✓ 已连接到服务器\n等待其他玩家加入..."
    connect_button.disabled = true
    host_button.disabled = true

func _on_connection_failed() -> void:
    """连接失败"""
    status_label.text = "✗ 连接失败"
    connect_button.disabled = false
    host_button.disabled = false
    join_button.disabled = false

func _on_relay_room_created(room_code: String) -> void:
    """中继房间创建成功"""
    status_label.text = "✓ 中继房间创建成功\n房间码: %s" % room_code
    room_code_input.text = room_code

func _on_webrtc_room_created(room_code: String) -> void:
    """WebRTC 房间创建成功"""
    status_label.text = "✓ WebRTC 房间创建成功\n房间码: %s" % room_code
    room_code_input.text = room_code
    host_button.disabled = true

# 如果需要在 Scene 中显示此脚本，可以创建如下场景结构：
"""
NetworkModeSelector (Control)
├── VBoxContainer
│   ├── Label "选择网络模式"
│   ├── NetworkModeButtons (VBoxContainer) [%NetworkModeButtons]
│   │   └── (动态创建按钮)
│   ├── HBoxContainer
│   │   ├── Label "玩家名字:"
│   │   └── LineEdit [%PlayerNameInput]
│   ├── HBoxContainer
│   │   ├── Label "服务器地址:"
│   │   └── LineEdit [%ServerAddressInput]
│   ├── HBoxContainer
│   │   ├── Label "端口:"
│   │   └── LineEdit [%PortInput]
│   ├── HBoxContainer
│   │   ├── Label "房间码:"
│   │   └── LineEdit [%RoomCodeInput]
│   ├── HBoxContainer
│   │   ├── Button "连接" [%ConnectButton]
│   │   ├── Button "创建房间" [%HostButton]
│   │   └── Button "加入房间" [%JoinButton]
│   └── Label "状态" [%StatusLabel]
"""
