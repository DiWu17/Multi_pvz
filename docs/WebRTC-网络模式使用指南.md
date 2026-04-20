# WebRTC 多人联网模式使用指南

## 概述

本项目现已支持三种网络连接模式：

1. **ENet 直连** - 适用于局域网 (默认)
2. **中继服务器** - Godot 官方中继系统
3. **WebRTC** ✨ **新增** - 点对点通信，支持NAT穿透

## WebRTC 模式的优势

- ✅ **点对点直连**: 无需中心服务器转发游戏数据
- ✅ **NAT穿透**: 自动穿过防火墙和NAT
- ✅ **低延迟**: 相比中继模式更低的延迟
- ✅ **私密性**: 连接完全由对等体管理
- ✅ **跨域**: 支持跨越地理位置的连接
- ✅ **浏览器友好**: 与Web版游戏兼容

## 系统要求

### 服务器端
- Python 3.8+
- websockets >= 12.0

### 客户端
- Godot 4.6+
- WebRTC 支持 (Godot 内置)

## 安装和启动

### 1. 安装 Python 依赖

```bash
cd server
pip install -r requirements.txt
```

### 2. 启动 WebRTC 信令服务器

```bash
python3 webrtc_signaling_server.py
```

输出应该显示：
```
INFO:__main__:启动 WebRTC 信令服务器...
INFO:__main__:WebRTC 信令服务器运行在 ws://0.0.0.0:8080
INFO:__main__:等待客户端连接...
```

### 3. 配置 Godot 游戏

在你的选择连接模式的 UI 中，添加 WebRTC 选项。

## 使用 API

### 在 GDScript 中使用

#### 主机创建房间 (Host)

```gdscript
# 创建 WebRTC 房间（在选择菜单中调用）
var error = NetworkManager.create_webrtc_host(
    "ws://your_server:8080",  # 信令服务器地址
    "主机名字"
)

if error == OK:
    # 监听房间创建信号
    await NetworkManager.webrtc_room_created
    print("房间码: ", NetworkManager.webrtc_room_code)
```

#### 客户端加入房间 (Client)

```gdscript
# 加入 WebRTC 房间（输入房间码后调用）
var error = NetworkManager.join_webrtc_room(
    "ws://your_server:8080",  # 信令服务器地址
    "房间码",                   # 从主机获得的房间码
    "玩家名字"
)

if error == OK:
    print("正在连接到 WebRTC 房间...")
```

#### 监听连接事件

```gdscript
# 玩家加入信号
NetworkManager.player_joined.connect(_on_player_joined)

# 服务器连接信号
NetworkManager.server_connected.connect(_on_server_connected)

# 网络统计更新
NetworkManager.net_stats_updated.connect(_on_net_stats_updated)

func _on_player_joined(peer_id: int, player_info: Dictionary):
    print("玩家加入: %d - %s" % [peer_id, player_info.name])

func _on_net_stats_updated(ping_ms: int, packet_loss: float):
    print("网络质量 - Ping: %dms, 丢包率: %.1f%%" % [ping_ms, packet_loss * 100])
```

#### 断开连接

```gdscript
NetworkManager.disconnect_from_server()
```

## 网络架构

### 信令流程

```
┌─────────────┐                    ┌────────────────────────┐
│  Host 1     │                    │  Signaling Server      │
│ (Godot)     │◄────────WebSocket──────────────────────────►│
└─────────────┘                    └────────────────────────┘
                                            ▲
┌─────────────┐                            │
│  Client 1   │◄───────WebSocket───────────┘
│ (Godot)     │
└─────────────┘

信令完成后：直接 WebRTC 点对点连接 (UDP)
Host 1 ◄────────── WebRTC/ICE ────────────► Client 1
```

### 消息流程

1. **房间创建**
   - Host 连接信令服务器
   - 信令服务器分配房间码
   - Host 显示房间码给玩家

2. **玩家加入**
   - Client 连接信令服务器
   - Client 发送房间码
   - 信令服务器验证房间
   - Host 和 Client 交换 WebRTC offer/answer
   - ICE 候选交换
   - 直接点对点连接建立

3. **游戏通信**
   - 所有游戏数据通过点对点连接
   - Host 负责验证和同步
   - 无需经过中心服务器

## 配置详解

### ICE 服务器 (STUN/TURN)

当前配置使用 Google 的 STUN 服务器：

```gdscript
const WEBRTC_ICE_SERVERS := [
    {"urls": ["stun:stun.l.google.com:19302"]},
    {"urls": ["stun:stun1.l.google.com:19302"]},
    {"urls": ["stun:stun2.l.google.com:19302"]},
]
```

**STUN** (Simple Traversal of UDP through NAT):
- 帮助客户端发现其公网IP地址
- 无需认证

**TURN** (Traversal Using Relays around NAT):
- 当直连失败时，作为中继服务器
- 需要认证和付费

### 自定义 TURN 服务器

如需更好的连接成功率，可配置 TURN 服务器：

```gdscript
# 在 NetworkManager 中修改
const WEBRTC_ICE_SERVERS := [
    {"urls": ["stun:stun.l.google.com:19302"]},
    {
        "urls": ["turn:your_turn_server.com:3478"],
        "username": "user",
        "credential": "password"
    },
]
```

## 故障排除

### 无法连接到信令服务器

**问题**: WebSocket 连接超时

**解决**:
```bash
# 检查服务器是否运行
netstat -an | grep 8080

# 检查防火墙
# 确保端口 8080 对外开放
```

### 连接建立但无法通信

**问题**: WebRTC 点对点连接失败

**解决**:
1. 检查 NAT/防火墙设置
2. 尝试配置 TURN 服务器
3. 检查 ICE 候选收集

```gdscript
# 在 WebRTCMultiplayerPeer 中启用调试
_webrtc_peer = WebRTCMultiplayerPeer.new()
```

### 间歇性丢包

**问题**: UDP 不可靠

**解决**:
- 对关键操作使用 RPC 的 "reliable" 模式
- 增加数据冗余

```gdscript
# reliable RPC - 保证送达
_plant_rejected.rpc_id(peer_id, "阳光不足")

# unreliable RPC - 快速但可能丢失
sync_cursor_state.rpc("unreliable", peer_id, state)
```

## 性能优化

### 1. 减少 RPC 频率

```gdscript
# 不推荐：每帧发送
func _process(_delta):
    sync_cursor_state.rpc_id(1, get_global_mouse_position())

# 推荐：每 0.1 秒发送一次
var _last_sync_time = 0
func _process(delta):
    _last_sync_time += delta
    if _last_sync_time > 0.1:
        _last_sync_time = 0
        sync_cursor_state.rpc_id(1, get_global_mouse_position())
```

### 2. 压缩数据

```gdscript
# 不推荐：完整字典
sync_data.rpc({"x": 100.5, "y": 200.5, "hp": 50})

# 推荐：紧凑数组
sync_data.rpc([100, 200, 50])
```

### 3. 监控网络质量

```gdscript
func _on_net_stats_updated(ping_ms: int, packet_loss: float):
    # 动态调整游戏速度
    if ping_ms > 200:
        Engine.time_scale = 0.9  # 降速以适应高延迟
    else:
        Engine.time_scale = 1.0
```

## 与现有代码兼容性

WebRTC 模式与现有的 ENet 和 Relay 模式完全兼容：

- ✅ 所有现有 RPC 调用不需修改
- ✅ 事件信号保持一致
- ✅ 玩家管理逻辑相同
- ✅ 难度缩放继续工作

只需切换连接模式即可：

```gdscript
# ENet 直连
NetworkManager.create_server(27015, "主机")

# 中继服务器
NetworkManager.create_relay_host("https://your_relay_server", "主机")

# WebRTC
NetworkManager.create_webrtc_host("ws://your_signaling_server:8080", "主机")
```

## 部署到生产环境

### 在云服务器上运行信令服务器

```bash
# 1. 购买云服务器 (AWS/阿里云/腾讯云等)
# 2. 安装 Python 3.8+
# 3. 上传 webrtc_signaling_server.py

# 4. 后台运行
nohup python3 webrtc_signaling_server.py > signaling.log 2>&1 &

# 5. 或使用 systemd
sudo systemctl start webrtc-signaling
```

### 配置 HTTPS (WSS)

对于生产环境，建议使用 WSS (WebSocket Secure)：

```bash
# 使用 Nginx 反向代理
# 配置 HTTPS 证书
# 转发 wss://yourdomain.com 到 ws://localhost:8080
```

## 常见问题

**Q: WebRTC 需要中心服务器吗？**

A: 只需要信令服务器来初始化连接。连接建立后，数据完全点对点。信令服务器很轻量级。

**Q: 支持多少玩家？**

A: 理论上无限制，但考虑网络带宽，推荐最多 4-8 个点对点连接。

**Q: 可以与 WebGL 版本互联吗？**

A: 可以。WebRTC 同时支持 Godot 4 和 Web 平台。

**Q: 连接不稳定怎么办？**

A: 检查 TURN 服务器配置，或使用中继模式作为备选。

## 进一步改进

未来可以考虑的优化：

- [ ] 自定义信令协议优化
- [ ] 房间密码保护
- [ ] 玩家禁言/踢出机制
- [ ] 连接质量实时显示
- [ ] 自动服务器选择 (ENet/Relay/WebRTC)
- [ ] STUN/TURN 服务器池
- [ ] 连接加密

## 相关资源

- [Godot WebRTC 文档](https://docs.godotengine.org/en/stable/tutorials/networking/webrtc.html)
- [WebRTC 官方](https://webrtc.org/)
- [MDN WebRTC 文档](https://developer.mozilla.org/en-US/docs/Web/API/WebRTC_API)
- [NAT 穿透原理](https://en.wikipedia.org/wiki/Network_address_translation)

---

**更新日期**: 2026-04-21
**支持版本**: Godot 4.6+
