// server/server.js
// ------------------------------------------------------------
// Twin Core Blasters - Step 12 Lobby + Room Server
//
// 日本語コメント付きの最小WebSocketサーバーです。
// 役割:
// - ルーム作成 / 参加
// - ユーザー名登録
// - P1 / P2 選択
// - Ready状態管理
// - Start Game通知
// - inputメッセージの中継
// ------------------------------------------------------------

const WebSocket = require("ws");

const PORT = Number(process.env.PORT || 8080);
const HOST = process.env.HOST || "0.0.0.0";

const MESSAGE = {
  HELLO: "hello",
  CREATE_ROOM: "create_room",
  JOIN_ROOM: "join_room",
  LEAVE_ROOM: "leave_room",
  INPUT: "input",
  SET_NAME: "set_name",
  SELECT_ROLE: "select_role",
  READY: "ready",
  START_GAME: "start_game",
  ROOM_CREATED: "room_created",
  JOINED_ROOM: "joined_room",
  PLAYER_ASSIGNED: "player_assigned",
  ROOM_STATE: "room_state",
  GAME_START: "game_start",
  ERROR: "error",
  PEER_JOINED: "peer_joined",
  PEER_LEFT: "peer_left",
  PING: "ping",
  PONG: "pong",
  GAME_EVENT: "game_event",
};

const rooms = new Map();

function createRoomId() {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  for (let attempt = 0; attempt < 100; attempt++) {
    let id = "";
    for (let i = 0; i < 4; i++) id += alphabet[Math.floor(Math.random() * alphabet.length)];
    if (!rooms.has(id)) return id;
  }
  return String(Date.now()).slice(-6);
}

function send(ws, data) {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(data));
}

function sendError(ws, message) {
  send(ws, { type: MESSAGE.ERROR, message });
}

function createEmptyRoom(roomId, stage = "story") {
  return {
    id: roomId,
    stage,
    hostPlayerId: 1,
    players: new Map(), // playerId -> ws
    createdAt: Date.now(),
    started: false,
  };
}

function roomState(room) {
  function playerData(playerId) {
    const ws = room.players.get(playerId);
    return {
      occupied: Boolean(ws),
      name: ws ? ws.playerName || `Player ${playerId}` : "",
      ready: ws ? Boolean(ws.ready) : false,
    };
  }
  const p1Ready = room.players.has(1) && Boolean(room.players.get(1).ready);
  const p2Ready = room.players.has(2) && Boolean(room.players.get(2).ready);
  return {
    room_id: room.id,
    stage: room.stage,
    host_player_id: room.hostPlayerId,
    can_start: p1Ready && p2Ready,
    players: {
      p1: playerData(1),
      p2: playerData(2),
    },
  };
}

function broadcastRoomState(room) {
  const data = { type: MESSAGE.ROOM_STATE, room: roomState(room) };
  for (const socket of room.players.values()) send(socket, data);
}

function removeSocketFromRooms(ws) {
  for (const [roomId, room] of rooms.entries()) {
    for (const [playerId, playerSocket] of room.players.entries()) {
      if (playerSocket === ws) {
        room.players.delete(playerId);
        for (const otherSocket of room.players.values()) {
          send(otherSocket, { type: MESSAGE.PEER_LEFT, room_id: roomId, player_id: playerId });
        }
        console.log(`[room ${roomId}] P${playerId} left`);
        if (room.players.size === 0) {
          rooms.delete(roomId);
          console.log(`[room ${roomId}] deleted`);
        } else {
          broadcastRoomState(room);
        }
        ws.roomId = "";
        ws.playerId = 0;
        return;
      }
    }
  }
}

function assignPlayer(room, ws) {
  if (!room.players.has(1)) {
    room.players.set(1, ws);
    return 1;
  }
  if (!room.players.has(2)) {
    room.players.set(2, ws);
    return 2;
  }
  return 0;
}

function setSocketRole(room, ws, desiredRole) {
  const playerId = desiredRole === "p2" ? 2 : 1;
  const currentHolder = room.players.get(playerId);
  if (currentHolder && currentHolder !== ws) return 0;
  for (const [id, socket] of room.players.entries()) {
    if (socket === ws) room.players.delete(id);
  }
  room.players.set(playerId, ws);
  ws.playerId = playerId;
  return playerId;
}

function broadcastToRoom(room, data, exceptSocket = null) {
  for (const socket of room.players.values()) {
    if (socket !== exceptSocket) send(socket, data);
  }
}

function handleCreateRoom(ws, msg) {
  removeSocketFromRooms(ws);
  const roomId = createRoomId();
  const stage = String(msg.stage || "story");
  const room = createEmptyRoom(roomId, stage);
  rooms.set(roomId, room);
  const playerId = assignPlayer(room, ws);
  ws.roomId = roomId;
  ws.playerId = playerId;
  ws.ready = false;
  send(ws, { type: MESSAGE.ROOM_CREATED, room_id: roomId, stage });
  send(ws, { type: MESSAGE.JOINED_ROOM, room_id: roomId, stage, player_id: playerId });
  send(ws, { type: MESSAGE.PLAYER_ASSIGNED, room_id: roomId, player_id: playerId });
  broadcastRoomState(room);
  console.log(`[room ${roomId}] created, P${playerId} joined`);
}

function handleJoinRoom(ws, msg) {
  const roomId = String(msg.room_id || "").trim().toUpperCase();
  if (!roomId) return sendError(ws, "room_id is required.");
  if (!rooms.has(roomId)) return sendError(ws, `Room not found: ${roomId}`);
  const room = rooms.get(roomId);
  // 同じ部屋に入り直すだけなら削除しない。別部屋なら移動前に外す。
  if (ws.roomId && ws.roomId !== roomId) removeSocketFromRooms(ws);
  if (ws.roomId === roomId && ws.playerId) {
    send(ws, { type: MESSAGE.JOINED_ROOM, room_id: roomId, stage: room.stage, player_id: ws.playerId });
    send(ws, { type: MESSAGE.PLAYER_ASSIGNED, room_id: roomId, player_id: ws.playerId });
    broadcastRoomState(room);
    return;
  }
  const playerId = assignPlayer(room, ws);
  if (playerId === 0) return sendError(ws, "Room is full.");
  ws.roomId = roomId;
  ws.playerId = playerId;
  ws.ready = false;
  send(ws, { type: MESSAGE.JOINED_ROOM, room_id: roomId, stage: room.stage, player_id: playerId });
  send(ws, { type: MESSAGE.PLAYER_ASSIGNED, room_id: roomId, player_id: playerId });
  broadcastToRoom(room, { type: MESSAGE.PEER_JOINED, room_id: roomId, player_id: playerId }, ws);
  broadcastRoomState(room);
  console.log(`[room ${roomId}] P${playerId} joined`);
}

function handleSetName(ws, msg) {
  ws.playerName = String(msg.name || "Player").slice(0, 20);
  if (ws.roomId && rooms.has(ws.roomId)) broadcastRoomState(rooms.get(ws.roomId));
}

function handleSelectRole(ws, msg) {
  const role = String(msg.role || "p1").toLowerCase();
  if (!ws.roomId || !rooms.has(ws.roomId)) return sendError(ws, "Join a room first.");
  const room = rooms.get(ws.roomId);
  const playerId = setSocketRole(room, ws, role);
  if (playerId === 0) return sendError(ws, `${role.toUpperCase()} is already selected.`);
  send(ws, { type: MESSAGE.PLAYER_ASSIGNED, room_id: room.id, player_id: playerId });
  broadcastRoomState(room);
}

function handleReady(ws, msg) {
  ws.ready = Boolean(msg.ready);
  if (ws.roomId && rooms.has(ws.roomId)) broadcastRoomState(rooms.get(ws.roomId));
}

function handleStartGame(ws, msg) {
  if (!ws.roomId || !rooms.has(ws.roomId)) return sendError(ws, "Join a room first.");
  const room = rooms.get(ws.roomId);
  if (ws.playerId !== room.hostPlayerId) return sendError(ws, "Only the host can start the game.");
  const state = roomState(room);
  if (!state.can_start) return sendError(ws, "Both players must be ready.");
  const stage = String(msg.stage || room.stage || "story");
  room.started = true;
  broadcastToRoom(room, { type: MESSAGE.GAME_START, room_id: room.id, stage }, null);
  console.log(`[room ${room.id}] game start: ${stage}`);
}

function handleGameEvent(ws, msg) {
  const roomId = String(msg.room_id || ws.roomId || "").trim().toUpperCase();
  if (!rooms.has(roomId)) return;
  const room = rooms.get(roomId);
  const relayMsg = { ...msg, room_id: roomId, player_id: ws.playerId };
  broadcastToRoom(room, relayMsg, ws);
}

function handleInput(ws, msg) {
  const roomId = String(msg.room_id || ws.roomId || "").trim().toUpperCase();
  if (!rooms.has(roomId)) return;
  const room = rooms.get(roomId);
  const safePlayerId = ws.playerId || Number(msg.player_id || 0);
  broadcastToRoom(room, {
    type: MESSAGE.INPUT,
    room_id: roomId,
    player_id: safePlayerId,
    frame: Number(msg.frame || 0),
    input: msg.input || {},
    server_time: Date.now(),
  }, ws);
}

function handleMessage(ws, raw) {
  let msg;
  try { msg = JSON.parse(raw); } catch (_) { return sendError(ws, "Invalid JSON."); }
  switch (String(msg.type || "")) {
    case MESSAGE.HELLO:
      send(ws, { type: MESSAGE.HELLO, message: "hello from server", server_time: Date.now() });
      break;
    case MESSAGE.CREATE_ROOM: handleCreateRoom(ws, msg); break;
    case MESSAGE.JOIN_ROOM: handleJoinRoom(ws, msg); break;
    case MESSAGE.LEAVE_ROOM: removeSocketFromRooms(ws); break;
    case MESSAGE.SET_NAME: handleSetName(ws, msg); break;
    case MESSAGE.SELECT_ROLE: handleSelectRole(ws, msg); break;
    case MESSAGE.READY: handleReady(ws, msg); break;
    case MESSAGE.START_GAME: handleStartGame(ws, msg); break;
    case MESSAGE.INPUT: handleInput(ws, msg); break;
    case MESSAGE.GAME_EVENT: handleGameEvent(ws, msg); break;
    case MESSAGE.PING: send(ws, { type: MESSAGE.PONG, server_time: Date.now() }); break;
    default: sendError(ws, `Unknown message type: ${msg.type}`); break;
  }
}

const wss = new WebSocket.Server({ host: HOST, port: PORT });

wss.on("connection", (ws, req) => {
  ws.roomId = "";
  ws.playerId = 0;
  ws.playerName = "Player";
  ws.ready = false;
  const remoteAddress = req.socket.remoteAddress;
  console.log(`[connect] ${remoteAddress}`);
  send(ws, { type: MESSAGE.HELLO, message: "Twin Core Blasters server ready", server_time: Date.now() });
  ws.on("message", (data) => handleMessage(ws, data.toString()));
  ws.on("close", () => { removeSocketFromRooms(ws); console.log(`[disconnect] ${remoteAddress}`); });
  ws.on("error", (error) => console.warn("[socket error]", error.message));
});

setInterval(() => {
  const summary = Array.from(rooms.values()).map((room) => `${room.id}: ${room.players.size}/2`).join(", ");
  if (summary) console.log(`[rooms] ${summary}`);
}, 30000);

console.log(`Twin Core Blasters WebSocket server listening on ws://${HOST}:${PORT}`);
console.log("Press Ctrl+C to stop.");
