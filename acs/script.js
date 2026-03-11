const DUPLICATE_WINDOW_MS = 15000;
const BOARD_POLL_MS = 5000;
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

const $ = id => document.getElementById(id);

let boardTimerId = null;
let activeBoardView = "status";
let boardLogs = [];
const recentScans = {};

const fetchJson = async (url, options) => {
  const res = await fetch(url, options);
  const text = await res.text();
  let data = null;

  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = null;
    }
  }

  if (!res.ok) {
    const err = new Error(data?.message || `HTTP ${res.status}`);
    err.status = res.status;
    err.payload = data;
    throw err;
  }

  return data;
};

const showMessage = (text, tone) => {
  const el = $("message-text");
  if (!el) return;

  el.textContent = text;
  el.className = "message-text";
  if (tone) el.classList.add(`tone-${tone}`);
};

const focusBarcodeInput = () => {
  window.setTimeout(() => {
    const loc = $("location-input");
    const input = $("barcode-input");

    if (!input || document.activeElement === loc) return;

    input.focus();
    input.select();
  }, 0);
};

const parseBarcode = rawValue => {
  const value = String(rawValue || "").replace(/\r/g, "").replace(/\n/g, "").trim();
  const upper = value.slice(0, 2).toUpperCase();
  const id = value.slice(2).trim();

  if (!value || !id) return { ok: false, message: "바코드를 다시 확인해 주세요." };
  if (upper === "EN") return { ok: true, type: "entry", id, raw: value };
  if (upper === "EX") return { ok: true, type: "exit", id, raw: value };

  return { ok: false, message: "지원하지 않는 바코드입니다." };
};

const getDuplicateKey = (location, rawBarcode) => `${String(location || "")}|${String(rawBarcode || "")}`;

const shouldIgnoreDuplicate = (location, rawBarcode) => {
  const lastAt = recentScans[getDuplicateKey(location, rawBarcode)];
  if (!lastAt) return false;

  return Date.now() - lastAt < DUPLICATE_WINDOW_MS;
};

const markRecentScan = (location, rawBarcode) => {
  recentScans[getDuplicateKey(location, rawBarcode)] = Date.now();
};

const fetchAllStatus = () => fetchJson("/status");
const fetchLogs = day => fetchJson(`/logs?day=${encodeURIComponent(day)}`);

const postAccess = payload =>
  fetchJson("/access", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });

const createElement = (tagName, className, text) => {
  const el = document.createElement(tagName);

  if (className) el.className = className;
  if (typeof text !== "undefined") el.textContent = text;

  return el;
};

const padNumber = value => String(value).padStart(2, "0");

const toKstDate = value => new Date(new Date(value).getTime() + KST_OFFSET_MS);

const getCurrentKstDay = () => {
  const now = new Date(Date.now() + KST_OFFSET_MS);
  const year = now.getUTCFullYear();
  const month = padNumber(now.getUTCMonth() + 1);
  const day = padNumber(now.getUTCDate());

  return `${year}-${month}-${day}`;
};

const formatLogTime = value => {
  const date = toKstDate(value);

  if (Number.isNaN(date.getTime())) return String(value || "-");

  const year = date.getUTCFullYear();
  const month = padNumber(date.getUTCMonth() + 1);
  const day = padNumber(date.getUTCDate());
  const hour = padNumber(date.getUTCHours());
  const minute = padNumber(date.getUTCMinutes());
  const second = padNumber(date.getUTCSeconds());

  return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
};

const clearInput = input => {
  if (input) input.value = "";
};

const resetInput = input => {
  clearInput(input);
  focusBarcodeInput();
};

const showDuplicateResult = ({ type, id }) => {
  const action = type === "entry" ? "입영" : "퇴영";
  showMessage(`${id}님 이미 ${action} 처리되었습니다`, "warn");
};

const showAccessResult = ({ type, id }) => {
  const action = type === "entry" ? "입영" : "퇴영";
  showMessage(`${id}님 ${action}입니다`, "ok");
};

const handleDuplicateSubmit = (parsed, location, input) => {
  if (!shouldIgnoreDuplicate(location, parsed.raw)) return false;

  showDuplicateResult(parsed);
  resetInput(input);
  return true;
};

const renderBoard = groups => {
  const root = $("board-groups");
  if (!root) return;

  const items = Array.isArray(groups) ? groups : [];
  const frag = document.createDocumentFragment();

  if (items.length === 0) {
    const card = createElement("article", "board-card empty-card");
    card.appendChild(createElement("h2", "", "현황 없음"));
    card.appendChild(createElement("p", "", "아직 데이터가 없습니다."));
    frag.appendChild(card);
    root.replaceChildren(frag);
    return;
  }

  for (const group of items) {
    const location = group?.location ? String(group.location) : "unknown";
    const ids = Array.isArray(group?.ids) ? group.ids : [];
    const card = createElement("article", "board-card");
    const list = createElement("ul", "id-list");

    card.appendChild(createElement("h2", "", location));
    card.appendChild(createElement("div", "board-count", `인원 ${ids.length}명`));

    if (ids.length === 0) {
      list.appendChild(createElement("li", "empty-item", "현재 인원 없음"));
    } else {
      for (const id of ids) list.appendChild(createElement("li", "id-item", id));
    }

    card.appendChild(list);
    frag.appendChild(card);
  }

  root.replaceChildren(frag);
};

const renderLogs = () => {
  const body = $("log-table-body");
  if (!body) return;

  const query = $("log-search-input")?.value.trim().toLowerCase() || "";
  const order = $("log-sort-select")?.value || "desc";
  const items = boardLogs
    .filter(item => {
      if (!query) return true;

      const id = String(item?.id || "").toLowerCase();
      const location = String(item?.location || "").toLowerCase();
      return id.includes(query) || location.includes(query);
    })
    .sort((left, right) => {
      const diff = String(left?.time || "").localeCompare(String(right?.time || ""));
      return order === "asc" ? diff : diff * -1;
    });

  const frag = document.createDocumentFragment();

  if (items.length === 0) {
    const row = createElement("tr");
    const cell = createElement("td", "empty-cell", "로그가 없습니다.");

    cell.colSpan = 4;
    row.appendChild(cell);
    frag.appendChild(row);
    body.replaceChildren(frag);
    return;
  }

  for (const item of items) {
    const row = createElement("tr");

    row.appendChild(createElement("td", "", formatLogTime(item?.time)));
    row.appendChild(createElement("td", "", item?.type === "entry" ? "입영" : "퇴영"));
    row.appendChild(createElement("td", "", String(item?.location || "-")));
    row.appendChild(createElement("td", "", String(item?.id || "-")));
    frag.appendChild(row);
  }

  body.replaceChildren(frag);
};

const refreshBoard = async () => {
  const root = $("board-groups");
  if (!root) return;

  const status = $("board-status");
  const updated = $("board-updated");

  try {
    const data = await fetchAllStatus();

    renderBoard(data);
    if (status) status.textContent = "정상";
    if (updated) updated.textContent = new Date().toLocaleString();
  } catch {
    if (status) status.textContent = "실패";
  }
};

const refreshLogs = async () => {
  const body = $("log-table-body");
  if (!body) return;

  const status = $("board-status");
  const updated = $("board-updated");
  const dayInput = $("log-day-input");
  const day = dayInput?.value || getCurrentKstDay();

  try {
    const data = await fetchLogs(day);

    boardLogs = Array.isArray(data) ? data : [];
    renderLogs();
    if (status) status.textContent = "정상";
    if (updated) updated.textContent = new Date().toLocaleString();
  } catch {
    if (status) status.textContent = "실패";
  }
};

const refreshActiveBoardView = () => {
  if (activeBoardView === "logs") return refreshLogs();
  return refreshBoard();
};

const setBoardView = view => {
  activeBoardView = view === "logs" ? "logs" : "status";

  const statusView = $("board-status-view");
  const logsView = $("board-logs-view");
  const statusButton = $("show-status-view-button");
  const logsButton = $("show-logs-view-button");
  const isLogsView = activeBoardView === "logs";

  if (statusView) statusView.hidden = isLogsView;
  if (logsView) logsView.hidden = !isLogsView;
  if (statusButton) statusButton.classList.toggle("is-active", !isLogsView);
  if (logsButton) logsButton.classList.toggle("is-active", isLogsView);
};

const startBoardPolling = () => {
  const root = $("board-groups");
  if (!root) return;

  if (boardTimerId !== null) clearInterval(boardTimerId);

  boardTimerId = window.setInterval(() => {
    void refreshActiveBoardView();
  }, BOARD_POLL_MS);
};

const submitAccess = async () => {
  const loc = $("location-input");
  const input = $("barcode-input");
  const location = loc?.value.trim() || "";
  const parsed = parseBarcode(input?.value);

  if (!location) {
    showMessage("location을 입력해 주세요.", "error");
    focusBarcodeInput();
    return;
  }

  if (!parsed.ok) {
    showMessage(parsed.message, "error");
    resetInput(input);
    return;
  }

  if (handleDuplicateSubmit(parsed, location, input)) return;

  try {
    const { type, id, raw } = parsed;

    await postAccess({ type, id, location });
    markRecentScan(location, raw);
    showAccessResult(parsed);
    clearInput(input);
  } catch (err) {
    showMessage(err.message || "처리에 실패했습니다.", "error");
    clearInput(input);
  } finally {
    focusBarcodeInput();
  }
};

const initScannerPage = () => {
  const input = $("barcode-input");
  if (!input) return;

  input.addEventListener("keydown", event => {
    if (event.key !== "Enter") return;

    event.preventDefault();
    void submitAccess();
  });

  input.addEventListener("input", () => {
    if (!input.value.includes("\n") && !input.value.includes("\r")) return;

    input.value = input.value.replace(/[\r\n]+/g, "");
    void submitAccess();
  });

  input.addEventListener("blur", () => {
    focusBarcodeInput();
  });

  document.addEventListener("click", event => {
    const loc = $("location-input");
    if (event.target === loc) return;

    focusBarcodeInput();
  });

  focusBarcodeInput();
};

const initBoardPage = () => {
  const root = $("board-groups");
  const button = $("refresh-board-button");
  const statusButton = $("show-status-view-button");
  const logsButton = $("show-logs-view-button");
  const dayInput = $("log-day-input");
  const searchInput = $("log-search-input");
  const sortInput = $("log-sort-select");

  if (!root) return;

  if (dayInput && !dayInput.value) dayInput.value = getCurrentKstDay();

  if (button) button.addEventListener("click", () => void refreshActiveBoardView());
  if (statusButton) statusButton.addEventListener("click", () => {
    setBoardView("status");
    void refreshActiveBoardView();
  });
  if (logsButton) logsButton.addEventListener("click", () => {
    setBoardView("logs");
    void refreshActiveBoardView();
  });
  if (dayInput) dayInput.addEventListener("change", () => void refreshLogs());
  if (searchInput) searchInput.addEventListener("input", () => renderLogs());
  if (sortInput) sortInput.addEventListener("change", () => renderLogs());

  setBoardView("status");
  void refreshActiveBoardView();
  startBoardPolling();
};

initScannerPage();
initBoardPage();
