class_name RelayMultiplayerPeer
extends MultiplayerPeerExtension
## 通过 WebSocket 中继服务器实现的自定义 MultiplayerPeer
## 第一个创建房间的玩家为 Host (peer_id=1), 其余为 Client
## 所有游戏数据经中继服务器转发, 对 Godot RPC 系统完全透明

#region 信号
signal relay_room_created(room_code: String)
signal relay_room_joined(peer_id: int)
signal relay_peer_connected(peer_id: int)
signal relay_peer_disconnected(peer_id: int)
signal relay_error(message: String)
#endregion

#region 内部状态
var _ws := WebSocketPeer.new()
var _unique_id: int = 0
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _target_peer: int = 0
var _transfer_mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _transfer_channel: int = 0
var _refuse_connections: bool = false

## 收到的数据包队列
var _incoming: Array[Dictionary] = []
var _current_pkt_peer: int = 0
var _current_pkt_channel: int = 0
var _current_pkt_mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE

## 延迟发射的 peer 信号 (避免与 SceneMultiplayer 时序冲突)
var _peers_to_connect: Array[int] = []
var _peers_to_disconnect: Array[int] = []
var _known_peers: Dictionary = {}  # {peer_id: name}

## 连接状态机
var _pending_action: String = ""   # "create" 或 "join"
var _pending_name: String = ""
var _pending_room_code: String = ""
var _action_sent: bool = false
#endregion

#region 公开方法
## 创建中继房间 (成为 Host)
func create_relay_host(url: String, player_name: String) -> Error:
	_pending_action = "create"
	_pending_name = player_name
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	var err = _ws.connect_to_url(url)
	if err != OK:
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	return err

## 加入中继房间 (成为 Client)
func join_relay_room(url: String, room_code: String, player_name: String) -> Error:
	_pending_action = "join"
	_pending_name = player_name
	_pending_room_code = room_code
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	var err = _ws.connect_to_url(url)
	if err != OK:
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	return err
#endregion

#region MultiplayerPeerExtension 接口实现

func _poll() -> void:
	_ws.poll()

	match _ws.get_ready_state():
		WebSocketPeer.STATE_CLOSED:
			if _status != MultiplayerPeer.CONNECTION_DISCONNECTED:
				_status = MultiplayerPeer.CONNECTION_DISCONNECTED
			return
		WebSocketPeer.STATE_CONNECTING:
			return

	# STATE_OPEN: WebSocket 已连接, 发送待处理的动作
	if not _action_sent and _pending_action != "":
		_action_sent = true
		if _pending_action == "create":
			_ws.send_text(JSON.stringify({
				"type": "create_room",
				"player_name": _pending_name
			}))
		elif _pending_action == "join":
			_ws.send_text(JSON.stringify({
				"type": "join_room",
				"room_code": _pending_room_code,
				"player_name": _pending_name
			}))
		_pending_action = ""

	# 处理 WebSocket 收到的消息
	while _ws.get_available_packet_count() > 0:
		var pkt = _ws.get_packet()
		if _ws.was_string_packet():
			_on_control(pkt.get_string_from_utf8())
		else:
			_on_data(pkt)

	# 延迟发射 peer 连接/断开信号
	for pid in _peers_to_connect:
		emit_signal("peer_connected", pid)
	_peers_to_connect.clear()

	for pid in _peers_to_disconnect:
		emit_signal("peer_disconnected", pid)
	_peers_to_disconnect.clear()


func _on_control(text: String) -> void:
	var data = JSON.parse_string(text)
	if data == null:
		return

	match data.get("type", ""):
		"room_created":
			_unique_id = data.get("peer_id", 1)
			_known_peers[_unique_id] = "self"
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			relay_room_created.emit(data.get("room_code", ""))

		"room_joined":
			_unique_id = data.get("peer_id", 0)
			var peers = data.get("peers", [])
			for p in peers:
				var pid := int(p.get("peer_id", 0))
				_known_peers[pid] = p.get("name", "")
				# 跳过自己; peer 1 必须保留, SceneMultiplayer 依赖 peer_connected(1) 触发 connected_to_server
				if pid != _unique_id:
					_peers_to_connect.append(pid)
			_status = MultiplayerPeer.CONNECTION_CONNECTED
			relay_room_joined.emit(_unique_id)

		"peer_connected":
			var pid := int(data.get("peer_id", 0))
			_known_peers[pid] = data.get("name", "")
			_peers_to_connect.append(pid)
			relay_peer_connected.emit(pid)

		"peer_disconnected":
			var pid := int(data.get("peer_id", 0))
			_known_peers.erase(pid)
			_peers_to_disconnect.append(pid)
			relay_peer_disconnected.emit(pid)
			# 如果 Host 断开, 我们也断开
			if pid == 1 and _unique_id != 1:
				_status = MultiplayerPeer.CONNECTION_DISCONNECTED

		"error":
			relay_error.emit(data.get("message", "未知错误"))
			if _status == MultiplayerPeer.CONNECTION_CONNECTING:
				_status = MultiplayerPeer.CONNECTION_DISCONNECTED


func _on_data(packet: PackedByteArray) -> void:
	if packet.size() < 4:
		return
	var source := packet.decode_s32(0)
	var payload := packet.slice(4)
	_incoming.append({
		"data": payload,
		"peer": source,
		"channel": 0,
		"mode": MultiplayerPeer.TRANSFER_MODE_RELIABLE,
	})


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	var pkt: Dictionary = _incoming.pop_front()
	_current_pkt_peer = pkt["peer"]
	_current_pkt_channel = pkt["channel"]
	_current_pkt_mode = pkt["mode"]
	return pkt["data"]


func _get_packet_peer() -> int:
	return _current_pkt_peer


func _get_packet_channel() -> int:
	return _current_pkt_channel


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _current_pkt_mode


func _put_packet_script(p_buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return ERR_UNAVAILABLE
	# 数据帧: [4B target_peer (int32 LE)] [payload]
	var header := PackedByteArray()
	header.resize(4)
	header.encode_s32(0, _target_peer)
	_ws.send(header + p_buffer)
	return OK


func _get_unique_id() -> int:
	return _unique_id


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _get_max_packet_size() -> int:
	return 1 << 24  # 16 MB


func _set_target_peer(p_peer: int) -> void:
	_target_peer = p_peer


func _get_transfer_channel() -> int:
	return _transfer_channel


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _transfer_mode


func _set_transfer_channel(p_channel: int) -> void:
	_transfer_channel = p_channel


func _set_transfer_mode(p_mode: MultiplayerPeer.TransferMode) -> void:
	_transfer_mode = p_mode


func _is_server() -> bool:
	return _unique_id == 1


func _is_server_relay_supported() -> bool:
	return false


func _is_refusing_new_connections() -> bool:
	return _refuse_connections


func _set_refuse_new_connections(p_enable: bool) -> void:
	_refuse_connections = p_enable


func _close() -> void:
	_ws.close()
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
	_unique_id = 0
	_known_peers.clear()
	_incoming.clear()
	_peers_to_connect.clear()
	_peers_to_disconnect.clear()
	_action_sent = false
	_pending_action = ""


func _disconnect_peer(p_peer: int, _p_force: bool) -> void:
	_known_peers.erase(p_peer)

#endregion
