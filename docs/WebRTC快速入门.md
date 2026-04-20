# WebRTC 模式快速入门

## 📋 已完成的改动

### 1. 核心网络管理器更新 ✅
**文件**: `scripts/autoload/network_manager.gd`

**新增内容**:
- `NetworkMode` 枚举: ENET | RELAY | WEBRTC
- WebRTC 信号: `webrtc_room_created`
- WebRTC 状态变量
- WebRTC 创建房间函数: `create_webrtc_host()`
- WebRTC 加入房间函数: `join_webrtc_room()`
- WebRTC 信令处理: `_process_webrtc_signal()`
- 新增 `_process()` 回调处理信令消息

### 2. WebRTC 信令服务器 ✅
**文件**: `server/webrtc_signaling_server.py`

**功能**:
- 房间管理 (创建/加入)
- 玩家信息同步
- Offer/Answer 交换转发
- ICE 候选交换
- 过期房间自动清理
- 完整的日志记录

### 3. 使用文档 ✅
**文件**: `docs/WebRTC-网络模式使用指南.md`

**内容**:
- WebRTC 模式优势
- 安装和启动步骤
- API 使用示例
- 网络架构说明
- 故障排除指南
- 性能优化建议
- 生产环境部署

### 4. UI 示例脚本 ✅
**文件**: `scenes/start_menu/network_mode_selector.gd`

**功能**:
- 网络模式选择 UI
- 参数输入 (地址/端口/房间码)
- 连接状态反馈
- 信号处理

---

## 🚀 快速使用步骤

### 第一步：启动信令服务器

```bash
# 进入服务器目录
cd server

# 安装依赖（如果未安装）
pip install -r requirements.txt

# 启动服务器
python3 webrtc_signaling_server.py
```

期望输出：
```
INFO:__main__:启动 WebRTC 信令服务器...
INFO:__main__:WebRTC 信令服务器运行在 ws://0.0.0.0:8080
INFO:__main__:等待客户端连接...
```

### 第二步：在游戏中使用

#### 主机创建房间 (Host)
```gdscript
# 在你的 UI 脚本中调用
var error = NetworkManager.create_webrtc_host(
    "ws://127.0.0.1:8080",  # 本地开发
    "我的房间"
)

# 监听房间创建
await NetworkManager.webrtc_room_created
print("房间码:", NetworkManager.webrtc_room_code)
```

#### 客户端加入房间 (Client)
```gdscript
# 输入房间码后调用
var error = NetworkManager.join_webrtc_room(
    "ws://127.0.0.1:8080",
    "房间码",
    "玩家名字"
)
```

### 第三步：跨不同设备连接

#### 本地测试 (局域网)
```bash
# 服务器地址改为本机 IP
ws://192.168.1.100:8080
```

#### 远程连接 (互联网)
```bash
# 1. 部署信令服务器到云服务器
# 2. 使用服务器地址
ws://your_server_ip:8080

# 或配置域名
ws://yourdomain.com:8080
```

---

## 📊 三种网络模式对比

| 特性 | ENet 直连 | 中继服务器 | WebRTC P2P |
|------|---------|---------|----------|
| 连接方式 | TCP/UDP | 中心转发 | 点对点 |
| NAT穿透 | ❌ | ✅ | ✅ |
| 跨域支持 | ❌ | ✅ | ✅ |
| 延迟 | 低 | 中等 | 低 |
| 服务器负载 | 无 | 高 | 极低 |
| 适用场景 | 局域网 | 测试 | 生产 |
| 建议玩家数 | 1-4 | 1-4 | 1-8 |

---

## 🔌 集成到现有菜单

### 修改 start_menu 场景

1. **打开** `scenes/start_menu/` 相关场景
2. **添加** 网络模式选择按钮:
   ```
   - ENet 直连
   - 中继服务器
   - WebRTC P2P ✨ 新增
   ```
3. **附加** `network_mode_selector.gd` 脚本
4. **配置** UI 元素为:
   - `%PlayerNameInput`
   - `%ServerAddressInput`
   - `%PortInput`
   - `%RoomCodeInput`
   - `%ConnectButton`
   - `%HostButton`
   - `%JoinButton`
   - `%StatusLabel`

### 示例场景结构

```
StartMenu
└── NetworkModePanel (Control)
    └── VBoxContainer
        ├── Title: "选择连接模式"
        ├── ModeButtons (VBoxContainer)
        │   ├── Button "ENet 直连"
        │   ├── Button "中继服务器"
        │   └── Button "WebRTC P2P" ← 新增
        ├── PlayerNameSection
        ├── ServerSection
        ├── RoomSection (新增)
        ├── ButtonsSection
        └── StatusLabel
```

---

## 🧪 测试清单

- [ ] 信令服务器正常启动
- [ ] 本地 WebRTC 房间创建成功
- [ ] 本地 WebRTC 房间加入成功
- [ ] 其他玩家加入时收到信号
- [ ] 网络质量检测正常工作
- [ ] RPC 调用正常执行
- [ ] 断网重连处理正确
- [ ] 房间码显示正确
- [ ] 玩家列表同步正确
- [ ] 游戏内全部功能正常

---

## 🛠️ 常见配置

### 本地开发
```
信令服务器: ws://127.0.0.1:8080
或: ws://localhost:8080
```

### 局域网
```
# 获取本机 IP
ipconfig (Windows)
ifconfig (Linux/Mac)

信令服务器: ws://192.168.x.x:8080
```

### 云服务器 (生产)
```
# 部署到 AWS/阿里云/腾讯云等
信令服务器: ws://your_domain.com:8080

# 推荐配置 HTTPS
信令服务器: wss://your_domain.com:8080
```

---

## 📝 现有代码兼容性

✅ **完全兼容** - 无需修改现有代码

- 所有 RPC 调用保持一致
- 所有信号保持一致
- 玩家管理逻辑一样
- 难度缩放继续工作
- 只是更换连接方式

---

## 🔄 从其他模式迁移

### 从 ENet 迁移

```gdscript
# 旧代码
NetworkManager.create_server(27015, "主机")

# 新代码 (WebRTC)
NetworkManager.create_webrtc_host("ws://localhost:8080", "主机")

# 其他代码完全相同 ✅
```

### 从中继迁移

```gdscript
# 旧代码
NetworkManager.create_relay_host("https://relay.server", "主机")

# 新代码 (WebRTC)
NetworkManager.create_webrtc_host("ws://localhost:8080", "主机")

# 其他代码完全相同 ✅
```

---

## 🚨 故障快速排查

| 问题 | 原因 | 解决 |
|-----|------|------|
| 无法连接到信令服务器 | 服务器未启动 | `python3 webrtc_signaling_server.py` |
| 房间创建失败 | WebSocket 连接错误 | 检查地址和端口 |
| 房间码生成但客户端无法加入 | 网络隔离 | 检查防火墙/NAT 设置 |
| 连接完成但无法通信 | ICE 候选失败 | 配置 TURN 服务器 |
| 间歇性丢包 | UDP 不可靠 | 对关键操作使用 "reliable" RPC |

---

## 📚 相关文件位置

| 文件 | 说明 |
|------|------|
| `scripts/autoload/network_manager.gd` | 核心网络管理 (已更新) |
| `server/webrtc_signaling_server.py` | 信令服务器 (新增) |
| `server/requirements.txt` | Python 依赖 (已更新) |
| `docs/WebRTC-网络模式使用指南.md` | 详细文档 (新增) |
| `scenes/start_menu/network_mode_selector.gd` | UI 示例 (新增) |

---

## 💡 下一步优化

### 短期
1. [ ] 集成到现有 UI 菜单
2. [ ] 测试多玩家场景
3. [ ] 调优网络参数

### 中期
1. [ ] 配置自定义 TURN 服务器
2. [ ] 添加连接加密
3. [ ] 实现自动模式选择

### 长期
1. [ ] WebGL 版本支持
2. [ ] 房间密码保护
3. [ ] 玩家举报/禁言机制
4. [ ] 社交特性集成

---

**更新日期**: 2026-04-21
**版本**: 1.0
**状态**: ✅ 可用于开发/测试
