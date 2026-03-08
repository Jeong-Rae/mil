const SERVER_IP = window.location.hostname || "localhost";
const SERVER_PORT = window.location.port || "9999";
const SERVER_PATH = "/api/";
const RECONNECT_DELAY_MS = 2000;

let socket = null;
let reconnectTimer = null;
let messageCount = 0;

function $id(id) {
  return document.getElementById(id);
}

function initializeApp() {
  attachEventListeners();
  updateConnectionState("connecting", "서버에 연결을 시도합니다.");
  updateMessageFormState();
  updateChatMeta();
  connectSocket();
}

function attachEventListeners() {
  $id("messageForm").addEventListener("submit", handleMessageSubmit);
}

function handleMessageSubmit(event) {
  event.preventDefault();

  if (!isSocketOpen()) {
    updateConnectionState("offline", "연결이 복구되면 다시 전송하세요.");
    updateMessageFormState();
    scheduleReconnect();
    return;
  }

  const messageInput = $id("messageInput");
  const text = messageInput.value.trim();

  if (!text) {
    return;
  }

  socket.send(JSON.stringify({ text: text }));
  messageInput.value = "";
  messageInput.focus();
}

function connectSocket() {
  const url = "ws://" + SERVER_IP + ":" + SERVER_PORT + SERVER_PATH;

  if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
    return;
  }

  clearReconnectTimer();
  disposeSocket();
  updateConnectionState("connecting", "서버에 연결 중입니다: " + url);
  updateMessageFormState();

  socket = new WebSocket(url);
  socket.addEventListener("open", handleSocketOpen);
  socket.addEventListener("message", handleSocketMessage);
  socket.addEventListener("close", handleSocketClose);
  socket.addEventListener("error", handleSocketError);
}

function disposeSocket() {
  if (!socket) {
    return;
  }

  socket.removeEventListener("open", handleSocketOpen);
  socket.removeEventListener("message", handleSocketMessage);
  socket.removeEventListener("close", handleSocketClose);
  socket.removeEventListener("error", handleSocketError);
  socket = null;
}

function scheduleReconnect() {
  if (reconnectTimer) {
    return;
  }

  reconnectTimer = window.setTimeout(function () {
    reconnectTimer = null;
    connectSocket();
  }, RECONNECT_DELAY_MS);
}

function clearReconnectTimer() {
  if (!reconnectTimer) {
    return;
  }

  window.clearTimeout(reconnectTimer);
  reconnectTimer = null;
}

function handleSocketOpen(event) {
  if (event.target !== socket) {
    return;
  }

  clearReconnectTimer();
  updateConnectionState("online", "연결되었습니다. 메시지를 보낼 수 있습니다.");
  updateMessageFormState();
  $id("messageInput").focus();
}

function handleSocketMessage(event) {
  let payload;

  try {
    payload = JSON.parse(event.data);
  } catch (error) {
    updateConnectionState("online", "메시지를 받았지만 JSON 파싱에 실패했습니다.");
    return;
  }

  appendMessage(payload);
}

function handleSocketClose(event) {
  if (event.target !== socket) {
    return;
  }

  disposeSocket();
  updateConnectionState("offline", "연결이 종료되었습니다. 2초 후 다시 시도합니다.");
  updateMessageFormState();
  scheduleReconnect();
}

function handleSocketError(event) {
  if (event.target !== socket) {
    return;
  }

  updateConnectionState("offline", "연결에 실패했습니다. 종료 후 다시 시도합니다.");
  updateMessageFormState();
  scheduleReconnect();
}

function isSocketOpen() {
  return !!socket && socket.readyState === WebSocket.OPEN;
}

function updateConnectionState(state, text) {
  const connectionStatusElement = $id("connectionStatus");
  const statusTextElement = $id("statusText");

  connectionStatusElement.textContent = getStatusLabel(state);
  connectionStatusElement.className = "status-badge " + state;
  statusTextElement.textContent = text;
}

function updateMessageFormState() {
  const enabled = isSocketOpen();
  const messageInputElement = $id("messageInput");
  const sendButtonElement = $id("sendButton");

  messageInputElement.disabled = !enabled;
  sendButtonElement.disabled = !enabled;
}

function getStatusLabel(state) {
  if (state === "online") {
    return "Connected";
  }

  if (state === "connecting") {
    return "Connecting";
  }

  return "Disconnected";
}

function appendMessage(payload) {
  const item = document.createElement("li");
  const header = document.createElement("div");
  const name = document.createElement("strong");
  const time = document.createElement("span");
  const text = document.createElement("p");

  item.className = "message-item";
  header.className = "message-header";
  time.className = "message-time";
  text.className = "message-text";

  name.textContent = payload.name || "unknown";
  time.textContent = formatTime(payload.sentAt);
  text.textContent = payload.text || "";

  header.appendChild(name);
  header.appendChild(time);
  item.appendChild(header);
  item.appendChild(text);

  const messageListElement = $id("messageList");
  messageListElement.appendChild(item);

  messageCount += 1;
  updateChatMeta();
  messageListElement.scrollTop = messageListElement.scrollHeight;
}

function updateChatMeta() {
  const chatMetaElement = $id("chatMeta");

  if (messageCount === 0) {
    chatMetaElement.textContent = "메시지 없음";
    return;
  }

  chatMetaElement.textContent = "총 " + messageCount + "개 메시지";
}

function formatTime(value) {
  if (!value) {
    return "";
  }

  const date = new Date(value);

  if (Number.isNaN(date.getTime())) {
    return value;
  }

  return date.toLocaleTimeString();
}

window.addEventListener("load", initializeApp);
