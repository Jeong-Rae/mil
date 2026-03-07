const SERVER_IP = "127.0.0.1";
const SERVER_PORT = "9999";

let socket = null;
let currentName = "";
let messageCount = 0;

function $id(id) {
  return document.getElementById(id);
}

function initializeApp() {
  attachEventListeners();
  updateConnectionState("offline", "서버에 연결되지 않았습니다.");
  updateMessageFormState();
  updateChatMeta();
}

function attachEventListeners() {
  $id("connectForm").addEventListener("submit", handleConnectSubmit);
  $id("messageForm").addEventListener("submit", handleMessageSubmit);
}

function handleConnectSubmit(event) {
  const name = $id("nameInput").value.trim();

  event.preventDefault();

  if (!name) {
    updateConnectionState("offline", "Name을 입력하세요.");
    return;
  }

  currentName = name;
  connectSocket();
}

function handleMessageSubmit(event) {
  event.preventDefault();

  if (!isSocketOpen()) {
    updateConnectionState("offline", "연결 후 메시지를 전송하세요.");
    updateMessageFormState();
    return;
  }

  const messageInput = $id("messageInput");
  const text = messageInput.value.trim();

  if (!text) {
    return;
  }

  const payload = {
    name: currentName,
    text: text
  };

  socket.send(JSON.stringify(payload));
  messageInput.value = "";
  messageInput.focus();
}

function connectSocket() {
  const url = "ws://" + SERVER_IP + ":" + SERVER_PORT + "/";

  closeExistingSocket();
  updateConnectionState("connecting", "서버에 연결 중입니다: " + url);
  updateMessageFormState();

  socket = new WebSocket(url);
  socket.addEventListener("open", handleSocketOpen);
  socket.addEventListener("message", handleSocketMessage);
  socket.addEventListener("close", handleSocketClose);
  socket.addEventListener("error", handleSocketError);
}

function closeExistingSocket() {
  if (!socket) {
    return;
  }

  socket.removeEventListener("open", handleSocketOpen);
  socket.removeEventListener("message", handleSocketMessage);
  socket.removeEventListener("close", handleSocketClose);
  socket.removeEventListener("error", handleSocketError);

  if (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING) {
    socket.close();
  }

  socket = null;
}

function handleSocketOpen() {
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

function handleSocketClose() {
  updateConnectionState("offline", "연결이 종료되었습니다.");
  updateMessageFormState();
}

function handleSocketError() {
  updateConnectionState("offline", "소켓 오류가 발생했습니다.");
  updateMessageFormState();
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
