const DUPLICATE_WINDOW_MS = 15000;
const BOARD_POLL_MS = 5000;
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

const $ = id => document.getElementById(id);

let boardTimerId = null;
let activeBoardView = "status";
let boardLogs = [];
let scannerLocation = "";
let configuredLocations = [];
let configuredLocationSet = new Set();
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

const normalizeLocations = items => {
  if (!Array.isArray(items)) return [];

  return items
    .map(item => {
      const location = String(item?.location || "").trim();
      if (!location) return null;
      return { location };
    })
    .filter(Boolean);
};

const setConfiguredLocations = items => {
  configuredLocations = normalizeLocations(items);
  configuredLocationSet = new Set(configuredLocations.map(item => item.location));
};

const isConfiguredLocation = value => configuredLocationSet.has(String(value || ""));

const focusBarcodeInput = () => {
  window.setTimeout(() => {
    const panel = $("scanner-panel");
    const input = $("barcode-input");

    if (!scannerLocation || !input || panel?.hidden) return;
    if (document.activeElement === input) return;

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

const fetchLocations = () => fetchJson("/locations");
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

const populateLocationSelect = items => {
  const select = $("location-select");
  if (!select) return;

  const frag = document.createDocumentFragment();
  frag.appendChild(createElement("option", "", "위치를 선택해 주세요."));
  frag.firstChild.value = "";

  for (const item of items) {
    const option = createElement("option", "", item.location);
    option.value = item.location;
    frag.appendChild(option);
  }

  select.replaceChildren(frag);
  select.value = "";
};

const activateScannerLocation = location => {
  scannerLocation = String(location || "").trim();

  const locationPanel = $("location-select-panel");
  const scannerPanel = $("scanner-panel");
  const selectedText = $("selected-location-text");

  if (selectedText) selectedText.textContent = scannerLocation || "-";
  if (locationPanel) locationPanel.hidden = !!scannerLocation;
  if (scannerPanel) scannerPanel.hidden = !scannerLocation;

  if (scannerLocation) {
    showMessage("바코드를 스캔해 주세요.", null);
    focusBarcodeInput();
  }
};

const renderBoard = groups => {
  const root = $("board-groups");
  if (!root) return;

  const statusByLocation = new Map();
  const items = Array.isArray(groups) ? groups : [];

  for (const group of items) {
    const location = String(group?.location || "");
    if (!isConfiguredLocation(location)) continue;
    statusByLocation.set(location, Array.isArray(group?.ids) ? group.ids : []);
  }

  const frag = document.createDocumentFragment();

  if (configuredLocations.length === 0) {
    const card = createElement("article", "board-card empty-card");
    card.appendChild(createElement("h2", "", "현황 없음"));
    card.appendChild(createElement("p", "", "등록된 location이 없습니다."));
    frag.appendChild(card);
    root.replaceChildren(frag);
    return;
  }

  for (const item of configuredLocations) {
    const ids = statusByLocation.get(item.location) || [];
    const card = createElement("article", "board-card");
    const list = createElement("ul", "id-list");

    card.appendChild(createElement("h2", "", item.location));
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
      if (!isConfiguredLocation(item?.location)) return false;
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
    const [locations, data] = await Promise.all([fetchLocations(), fetchAllStatus()]);

    setConfiguredLocations(locations);
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
    const [locations, data] = await Promise.all([fetchLocations(), fetchLogs(day)]);

    setConfiguredLocations(locations);
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
  const input = $("barcode-input");
  const location = scannerLocation;
  const parsed = parseBarcode(input?.value);

  if (!location) {
    showMessage("위치를 먼저 선택해 주세요.", "error");
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

const initScannerPage = async () => {
  const input = $("barcode-input");
  const select = $("location-select");
  const button = $("select-location-button");

  if (!input || !select || !button) return;

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

  button.addEventListener("click", () => {
    const location = select.value.trim();

    if (!location) {
      showMessage("위치를 선택해 주세요.", "error");
      select.focus();
      return;
    }

    activateScannerLocation(location);
  });

  select.addEventListener("keydown", event => {
    if (event.key !== "Enter") return;

    event.preventDefault();
    button.click();
  });

  document.addEventListener("click", event => {
    if (!scannerLocation) return;
    if (event.target === button) return;

    focusBarcodeInput();
  });

  try {
    const data = await fetchLocations();

    setConfiguredLocations(data);
    populateLocationSelect(configuredLocations);

    if (configuredLocations.length === 0) {
      showMessage("선택할 location이 없습니다.", "error");
      button.disabled = true;
      select.disabled = true;
      return;
    }

    showMessage("위치를 선택해 주세요.", null);
    select.focus();
  } catch (err) {
    showMessage(err.message || "location 목록을 불러오지 못했습니다.", "error");
    button.disabled = true;
    select.disabled = true;
  }
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

void initScannerPage();
initBoardPage();
