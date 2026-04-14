#!/usr/bin/env python3
"""
PVZ Godot Dream - WebSocket 中继服务器
用于在没有公网 IP 的情况下进行联机游戏。

使用方法:
    pip install websockets
    python relay_server.py [端口号]

默认端口: 27016

工作原理:
    1. 房主"创建中转房间" → 服务器分配房间码(如 A3X9), 房主成为 peer 1 (Host)
    2. 其他玩家输入房间码"加入中转房间" → 服务器分配 peer 2/3/4
    3. 所有游戏数据通过此服务器中转, 对游戏逻辑完全透明
"""

import asyncio
import json
import random
import string
import struct
import sys
import time

try:
    import websockets
except ImportError:
    print("错误: 请先安装 websockets 库")
    print("  pip install websockets")
    sys.exit(1)

ROOM_CODE_CHARS = string.ascii_uppercase + string.digits
ROOM_CODE_LENGTH = 4
MAX_PLAYERS_PER_ROOM = 4


class Player:
    __slots__ = ("ws", "peer_id", "name", "room")

    def __init__(self, ws, peer_id: int, name: str, room):
        self.ws = ws
        self.peer_id = peer_id
        self.name = name
        self.room = room


class Room:
    def __init__(self, code: str):
        self.code = code
        self.players: dict[int, Player] = {}
        self._next_id = 1
        self.created_at = time.time()

    def add_player(self, ws, name: str) -> Player:
        pid = self._next_id
        self._next_id += 1
        p = Player(ws, pid, name, self)
        self.players[pid] = p
        return p

    def remove_player(self, pid: int):
        self.players.pop(pid, None)


class RelayServer:
    def __init__(self):
        self.rooms: dict[str, Room] = {}
        self.ws_map: dict = {}  # ws -> Player

    def _gen_code(self) -> str:
        for _ in range(100):
            code = "".join(random.choices(ROOM_CODE_CHARS, k=ROOM_CODE_LENGTH))
            if code not in self.rooms:
                return code
        raise RuntimeError("无法生成唯一房间码")

    async def handler(self, ws):
        try:
            async for msg in ws:
                if isinstance(msg, str):
                    await self._on_text(ws, msg)
                elif isinstance(msg, bytes):
                    await self._on_binary(ws, msg)
        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            await self._on_close(ws)

    # ── 控制消息 (JSON 文本帧) ──────────────────────────

    async def _on_text(self, ws, text: str):
        try:
            data = json.loads(text)
        except json.JSONDecodeError:
            await ws.send(json.dumps({"type": "error", "message": "无效 JSON"}))
            return

        t = data.get("type", "")
        if t == "create_room":
            await self._create(ws, data)
        elif t == "join_room":
            await self._join(ws, data)
        elif t == "leave_room":
            await self._on_close(ws)
        else:
            await ws.send(json.dumps({"type": "error", "message": f"未知类型: {t}"}))

    async def _create(self, ws, data: dict):
        if ws in self.ws_map:
            await ws.send(json.dumps({"type": "error", "message": "已在房间中"}))
            return

        name = str(data.get("player_name", "Host"))[:20]
        code = self._gen_code()
        room = Room(code)
        self.rooms[code] = room
        player = room.add_player(ws, name)
        self.ws_map[ws] = player

        await ws.send(json.dumps({
            "type": "room_created",
            "room_code": code,
            "peer_id": player.peer_id,
        }))
        print(f"[{code}] 房间创建 by {name} (peer {player.peer_id})")

    async def _join(self, ws, data: dict):
        if ws in self.ws_map:
            await ws.send(json.dumps({"type": "error", "message": "已在房间中"}))
            return

        code = str(data.get("room_code", "")).upper().strip()
        name = str(data.get("player_name", "Player"))[:20]

        room = self.rooms.get(code)
        if not room:
            await ws.send(json.dumps({"type": "error", "message": "房间不存在"}))
            return
        if len(room.players) >= MAX_PLAYERS_PER_ROOM:
            await ws.send(json.dumps({"type": "error", "message": "房间已满"}))
            return

        player = room.add_player(ws, name)
        self.ws_map[ws] = player

        # 告知新玩家: 你的 peer_id 和已有的所有玩家
        peers = [{"peer_id": p.peer_id, "name": p.name}
                 for p in room.players.values()]
        await ws.send(json.dumps({
            "type": "room_joined",
            "peer_id": player.peer_id,
            "peers": peers,
        }))

        # 通知房间里的其他玩家
        for p in room.players.values():
            if p.peer_id != player.peer_id:
                try:
                    await p.ws.send(json.dumps({
                        "type": "peer_connected",
                        "peer_id": player.peer_id,
                        "name": name,
                    }))
                except Exception:
                    pass

        print(f"[{code}] {name} 加入 (peer {player.peer_id}), "
              f"人数: {len(room.players)}")

    # ── 数据转发 (二进制帧) ─────────────────────────────

    async def _on_binary(self, ws, raw: bytes):
        player = self.ws_map.get(ws)
        if not player:
            return
        if len(raw) < 4:
            return

        # 客户端发来: [4B target_peer (int32 LE)] [payload]
        target = struct.unpack_from("<i", raw, 0)[0]
        payload = raw[4:]

        # 转发给目标: [4B source_peer (int32 LE)] [payload]
        header = struct.pack("<i", player.peer_id)
        packet = header + payload
        room = player.room

        if target == 0:
            # 广播给房间内所有其他玩家
            for p in room.players.values():
                if p.peer_id != player.peer_id:
                    try:
                        await p.ws.send(packet)
                    except Exception:
                        pass
        elif target > 0:
            # 发送给指定玩家
            p = room.players.get(target)
            if p:
                try:
                    await p.ws.send(packet)
                except Exception:
                    pass
        else:
            # 负数: 广播给除 abs(target) 以外的所有人
            exclude = -target
            for p in room.players.values():
                if p.peer_id != player.peer_id and p.peer_id != exclude:
                    try:
                        await p.ws.send(packet)
                    except Exception:
                        pass

    # ── 断线处理 ────────────────────────────────────────

    async def _on_close(self, ws):
        player = self.ws_map.pop(ws, None)
        if not player:
            return

        room = player.room
        room.remove_player(player.peer_id)
        print(f"[{room.code}] {player.name} (peer {player.peer_id}) 断开")

        # 通知房间内其他玩家
        for p in room.players.values():
            try:
                await p.ws.send(json.dumps({
                    "type": "peer_disconnected",
                    "peer_id": player.peer_id,
                }))
            except Exception:
                pass

        # 如果房主 (peer 1) 断开, 关闭整个房间
        if player.peer_id == 1 and room.players:
            print(f"[{room.code}] 房主断开, 关闭房间")
            for p in list(room.players.values()):
                try:
                    await p.ws.send(json.dumps({
                        "type": "peer_disconnected",
                        "peer_id": 1,
                    }))
                    await p.ws.close(1000, "房主已断开")
                except Exception:
                    pass
                self.ws_map.pop(p.ws, None)
            room.players.clear()

        # 空房间清理
        if not room.players:
            self.rooms.pop(room.code, None)
            print(f"[{room.code}] 房间关闭")


async def main():
    port = 27016
    if len(sys.argv) > 1:
        try:
            port = int(sys.argv[1])
        except ValueError:
            print(f"无效端口: {sys.argv[1]}")
            sys.exit(1)

    server = RelayServer()
    print(f"=== PVZ 中继服务器 ===")
    print(f"监听: ws://0.0.0.0:{port}")
    print(f"等待连接... (Ctrl+C 停止)")

    async with websockets.serve(server.handler, "0.0.0.0", port):
        await asyncio.Future()  # 永久运行


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n服务器已停止")
