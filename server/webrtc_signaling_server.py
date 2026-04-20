#!/usr/bin/env python3
"""
WebRTC 信令服务器 - 用于处理 Godot WebRTC 多人游戏的连接
支持房间管理、offer/answer 交换、ICE 候选交换
"""

import asyncio
import json
import logging
import uuid
from datetime import datetime, timedelta
import websockets
from websockets.legacy.server import WebSocketServerProtocol, serve

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 房间管理
rooms = {}  # {room_code: {"room_id": str, "host_id": str, "players": {peer_id: ws}, ...}}
client_to_room = {}  # {client_id: room_code}
client_to_peer_id = {}  # {client_id: peer_id}

# 客户端信息
class ClientInfo:
    def __init__(self, client_id: str, ws: WebSocketServerProtocol):
        self.client_id = client_id
        self.ws = ws
        self.peer_id = None
        self.player_name = "Player"
        self.room_code = None
        self.is_host = False

clients = {}  # {client_id: ClientInfo}

def allocate_peer_id(room: dict) -> int | None:
    """为房间分配最小的未使用 peer_id。"""
    used_peer_ids = {
        info["peer_id"]
        for info in room.get("player_info", {}).values()
        if isinstance(info, dict) and "peer_id" in info
    }

    for peer_id in range(2, room.get("max_players", 4) + 1):
        if peer_id not in used_peer_ids:
            return peer_id

    return None

async def close_room(room_code: str, reason: str) -> None:
    """关闭整个房间，并通知剩余客户端。"""
    room = rooms.get(room_code)
    if not room:
        return

    for client_id in list(room.get("players", {}).keys()):
        if client_id in clients:
            await send_to_client(client_id, {
                "type": "room_closed",
                "message": reason,
            })
        client_to_room.pop(client_id, None)
        client_to_peer_id.pop(client_id, None)

    del rooms[room_code]
    logger.info(f"房间已关闭: {room_code}, 原因: {reason}")

async def broadcast_to_room(room_code: str, message: dict, exclude_client_id: str = None) -> None:
    """广播消息到房间内的所有客户端"""
    if room_code not in rooms:
        return
    
    room = rooms[room_code]
    message_str = json.dumps(message)
    
    for client_id, ws in room.get("players", {}).items():
        if exclude_client_id and client_id == exclude_client_id:
            continue
        try:
            await ws.send(message_str)
        except Exception as e:
            logger.error(f"广播失败 - 客户端 {client_id}: {e}")

async def send_to_client(client_id: str, message: dict) -> bool:
    """发送消息到指定客户端"""
    if client_id not in clients:
        return False
    
    try:
        await clients[client_id].ws.send(json.dumps(message))
        return True
    except Exception as e:
        logger.error(f"发送失败 - 客户端 {client_id}: {e}")
        return False

async def generate_room_code() -> str:
    """生成房间码"""
    return str(uuid.uuid4())[:8].upper()

async def handle_create_room(client_id: str, message: dict) -> None:
    """处理创建房间请求"""
    logger.info(f"handle_create_room 被调用: client_id={client_id}, message={message}")
    
    if client_id not in clients:
        logger.error(f"客户端不存在: {client_id}")
        return
    
    room_code = await generate_room_code()
    room_id = str(uuid.uuid4())
    
    logger.info(f"生成房间码: {room_code}, 房间ID: {room_id}")
    
    room = {
        "room_id": room_id,
        "room_code": room_code,
        "host_id": client_id,
        "players": {client_id: clients[client_id].ws},
        "created_at": datetime.now(),
        "max_players": message.get("max_players", 4),
        "player_info": {
            client_id: {
                "peer_id": 1,
                "name": clients[client_id].player_name,
                "color_index": 0,
                "is_ready": False,
                "is_card_chosen": False,
                "is_restart_voted": False,
            }
        }
    }
    
    rooms[room_code] = room
    client_to_room[client_id] = room_code
    client_to_peer_id[client_id] = 1
    clients[client_id].is_host = True
    
    # 发送房间创建成功消息给 Host
    response = {
        "type": "room_created",
        "room_code": room_code,
        "room_id": room_id,
        "peer_id": 1,
    }
    logger.info(f"发送 room_created 消息给客户端 {client_id}: {response}")
    
    await send_to_client(client_id, response)
    
    logger.info(f"房间创建成功: {room_code} (主机: {client_id})")

async def handle_join_room(client_id: str, message: dict) -> None:
    """处理加入房间请求"""
    if client_id not in clients:
        return
    
    room_code = message.get("room_code", "")
    if room_code not in rooms:
        await send_to_client(client_id, {
            "type": "error",
            "message": "房间不存在"
        })
        return
    
    room = rooms[room_code]
    
    # 检查房间是否已满
    if len(room["players"]) >= room["max_players"]:
        await send_to_client(client_id, {
            "type": "error",
            "message": "房间已满"
        })
        return
    
    # 分配 peer_id，避免有人离房后发生重复分配
    peer_id = allocate_peer_id(room)
    if peer_id is None:
        await send_to_client(client_id, {
            "type": "error",
            "message": "房间已满"
        })
        return
    
    # 添加客户端到房间
    room["players"][client_id] = clients[client_id].ws
    client_to_room[client_id] = room_code
    client_to_peer_id[client_id] = peer_id
    
    # 记录玩家信息
    room["player_info"][client_id] = {
        "peer_id": peer_id,
        "name": clients[client_id].player_name,
        "color_index": peer_id - 1,
        "is_ready": False,
        "is_card_chosen": False,
        "is_restart_voted": False,
    }
    
    # 通知新加入的客户端
    await send_to_client(client_id, {
        "type": "room_joined",
        "room_code": room_code,
        "room_id": room["room_id"],
        "peer_id": peer_id,
        "players": list(room["player_info"].values()),
    })
    
    # 广播玩家加入消息
    await broadcast_to_room(room_code, {
        "type": "player_joined",
        "peer_id": peer_id,
        "player_info": room["player_info"][client_id],
    }, exclude_client_id=client_id)
    
    # 向新加入的客户端发送其他玩家的信息
    for other_client_id, other_info in room["player_info"].items():
        if other_client_id != client_id:
            await send_to_client(client_id, {
                "type": "existing_player",
                "peer_id": other_info["peer_id"],
                "player_info": other_info,
            })
    
    logger.info(f"玩家加入房间: {room_code} - 客户端 {client_id} (Peer {peer_id})")

async def handle_peer_offer(client_id: str, message: dict) -> None:
    """处理 WebRTC offer"""
    room_code = client_to_room.get(client_id)
    if not room_code or room_code not in rooms:
        return
    
    to_id = message.get("to_id")
    if not to_id:
        return
    
    # 查找目标客户端
    room = rooms[room_code]
    target_client_id = None
    for cid, info in room["player_info"].items():
        if info["peer_id"] == to_id:
            target_client_id = cid
            break
    
    if target_client_id:
        from_peer_id = client_to_peer_id.get(client_id, 1)
        await send_to_client(target_client_id, {
            "type": "peer_offer",
            "from_id": from_peer_id,
            "offer": message.get("offer", ""),
        })
        logger.debug(f"转发 offer: {from_peer_id} -> {to_id}")

async def handle_peer_answer(client_id: str, message: dict) -> None:
    """处理 WebRTC answer"""
    room_code = client_to_room.get(client_id)
    if not room_code or room_code not in rooms:
        return
    
    to_id = message.get("to_id")
    if not to_id:
        return
    
    # 查找目标客户端
    room = rooms[room_code]
    target_client_id = None
    for cid, info in room["player_info"].items():
        if info["peer_id"] == to_id:
            target_client_id = cid
            break
    
    if target_client_id:
        from_peer_id = client_to_peer_id.get(client_id, 1)
        await send_to_client(target_client_id, {
            "type": "peer_answer",
            "from_id": from_peer_id,
            "answer": message.get("answer", ""),
        })
        logger.debug(f"转发 answer: {from_peer_id} -> {to_id}")

async def handle_ice_candidate(client_id: str, message: dict) -> None:
    """处理 ICE 候选"""
    room_code = client_to_room.get(client_id)
    if not room_code or room_code not in rooms:
        return
    
    to_id = message.get("to_id")
    if not to_id:
        return
    
    # 查找目标客户端
    room = rooms[room_code]
    target_client_id = None
    for cid, info in room["player_info"].items():
        if info["peer_id"] == to_id:
            target_client_id = cid
            break
    
    if target_client_id:
        from_peer_id = client_to_peer_id.get(client_id, 1)
        await send_to_client(target_client_id, {
            "type": "ice_candidate",
            "from_id": from_peer_id,
            "candidate": message.get("candidate", ""),
            "sdp_mid": message.get("sdp_mid", ""),
            "sdp_mline_index": message.get("sdp_mline_index", 0),
        })

async def handle_message(client_id: str, message: dict) -> None:
    """处理客户端消息"""
    action = message.get("action", "")
    msg_type = message.get("type", "")
    
    logger.info(f"处理消息 - client_id={client_id}, action={action}, type={msg_type}, message={message}")
    
    if action == "create":
        logger.info(f"处理 create 请求: {client_id}")
        await handle_create_room(client_id, message)
    elif action == "join":
        logger.info(f"处理 join 请求: {client_id}")
        await handle_join_room(client_id, message)
    elif msg_type == "peer_offer":
        await handle_peer_offer(client_id, message)
    elif msg_type == "peer_answer":
        await handle_peer_answer(client_id, message)
    elif msg_type == "ice_candidate":
        await handle_ice_candidate(client_id, message)
    else:
        logger.warning(f"未知消息类型: action={action}, type={msg_type} (客户端: {client_id})")

async def handler(ws: WebSocketServerProtocol, path: str) -> None:
    """处理客户端连接"""
    client_id = str(uuid.uuid4())
    clients[client_id] = ClientInfo(client_id, ws)
    
    logger.info(f"客户端连接: {client_id} (来自 {ws.remote_address})")
    
    try:
        async for message in ws:
            try:
                data = json.loads(message)
                
                # 更新客户端信息
                if "player_name" in data:
                    clients[client_id].player_name = data["player_name"]
                
                await handle_message(client_id, data)
                
            except json.JSONDecodeError:
                logger.error(f"无效的 JSON 消息 (客户端: {client_id}): {message[:100]}")
            except Exception as e:
                logger.error(f"处理消息失败 (客户端: {client_id}): {e}", exc_info=True)
    
    except websockets.exceptions.ConnectionClosed:
        logger.info(f"客户端断开连接: {client_id}")
    except Exception as e:
        logger.error(f"WebSocket 错误 (客户端: {client_id}): {e}", exc_info=True)
    
    finally:
        # 清理客户端
        if client_id in clients:
            room_code = client_to_room.get(client_id)
            
            # 从房间中移除客户端
            if room_code and room_code in rooms:
                room = rooms[room_code]
                if client_id == room.get("host_id"):
                    await close_room(room_code, "房主已离开，房间已关闭")
                else:
                    if client_id in room["players"]:
                        del room["players"][client_id]
                    if client_id in room["player_info"]:
                        del room["player_info"][client_id]
                    
                    # 广播玩家离开消息
                    peer_id = client_to_peer_id.get(client_id, -1)
                    await broadcast_to_room(room_code, {
                        "type": "player_left",
                        "peer_id": peer_id,
                    })
                    
                    # 如果房间为空，删除房间
                    if not room["players"]:
                        del rooms[room_code]
                        logger.info(f"房间已删除: {room_code}")
                    else:
                        logger.info(f"玩家离开房间: {room_code} - 客户端 {client_id}")
            
            del clients[client_id]
            if client_id in client_to_room:
                del client_to_room[client_id]
            if client_id in client_to_peer_id:
                del client_to_peer_id[client_id]

async def cleanup_expired_rooms() -> None:
    """定期清理过期的房间"""
    while True:
        await asyncio.sleep(60)  # 每60秒检查一次
        
        current_time = datetime.now()
        expired_rooms = []
        
        for room_code, room in rooms.items():
            # 如果房间超过1小时没有活动，删除它
            if (current_time - room["created_at"]) > timedelta(hours=1):
                if not room["players"]:  # 只删除空房间
                    expired_rooms.append(room_code)
        
        for room_code in expired_rooms:
            del rooms[room_code]
            logger.info(f"过期房间已删除: {room_code}")

async def main():
    """启动信令服务器"""
    logger.info("启动 WebRTC 信令服务器...")
    
    # 启动清理任务
    cleanup_task = asyncio.create_task(cleanup_expired_rooms())
    
    # 启动 WebSocket 服务器
    async with serve(handler, "0.0.0.0", 8080):
        logger.info("WebRTC 信令服务器运行在 ws://0.0.0.0:8080")
        logger.info("等待客户端连接...")
        
        try:
            await asyncio.Future()  # run forever
        except KeyboardInterrupt:
            logger.info("关闭服务器...")
            cleanup_task.cancel()

if __name__ == "__main__":
    asyncio.run(main())
