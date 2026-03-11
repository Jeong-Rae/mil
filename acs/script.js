const DUPLICATE_WINDOW_MS = 15000;
const BOARD_POLL_MS = 5000;
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

const $ = id => document.getElementById(id);

let boardTimerId = null;
let boardLogs = [];
let currentStatusById = new Map();
let scannerLocation = "";
let configuredLocations = [];
let configuredLocationSet = new Set();
let allowedMembers = [];
let allowedMemberById = new Map();
let locationsLoadPromise = null;
let membersLoadPromise = null;
const recentScans = {};

const createRequestError = (status, text) => {
  let data = null;

  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = null;
    }
  }

  const err = new Error(data?.message || `HTTP ${status}`);
  err.status = status;
  err.payload = data;
  return err;
};

const fetchText = async (url, options) => {
  const res = await fetch(url, options);
  const text = await res.text();

  if (!res.ok) throw createRequestError(res.status, text);
  return text;
};

const fetchJson = async (url, options) => {
  const text = await fetchText(url, options);

  if (!text) return null;

  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
};

const showMessage = (text, tone) => {
  const el = $("msg-txt");
  if (!el) return;

  el.textContent = text;
  el.className = "msg-txt";
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

const normalizeMembers = items => {
  if (!Array.isArray(items)) return [];

  return items
    .map(item => {
      const id = String(item?.id || "").trim();
      if (!id) return null;

      return {
        id,
        name: String(item?.name || "").trim(),
        unit: String(item?.unit || "").trim()
      };
    })
    .filter(Boolean);
};

const setAllowedMembers = items => {
  allowedMembers = normalizeMembers(items);
  allowedMemberById = new Map(allowedMembers.map(item => [item.id, item]));
};

const isConfiguredLocation = value => configuredLocationSet.has(String(value || ""));
const getMember = id => allowedMemberById.get(String(id || "")) || null;
const getMemberName = id => getMember(id)?.name || "";
const getMemberLabel = id => {
  const member = getMember(id);
  if (!member?.name) return String(id || "-");
  return `${String(id || "-")} / ${member.name}`;
};

const focusBarcodeInput = () => {
  window.setTimeout(() => {
    const panel = $("scan-pnl");
    const input = $("barcode");

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

const fetchLocations = () => fetchJson("/location.json");
const fetchMembers = () => fetchJson("/list.json");
const fetchLogsCsv = () => fetchText(`/logs/access-log.csv?ts=${Date.now()}`, { cache: "no-store" });

const loadLocations = () => {
  if (locationsLoadPromise) return locationsLoadPromise;

  locationsLoadPromise = fetchLocations()
    .then(data => {
      setConfiguredLocations(data);
      return configuredLocations;
    })
    .catch(err => {
      locationsLoadPromise = null;
      throw err;
    });

  return locationsLoadPromise;
};

const loadMembers = () => {
  if (membersLoadPromise) return membersLoadPromise;

  membersLoadPromise = fetchMembers()
    .then(data => {
      setAllowedMembers(data);
      return allowedMembers;
    })
    .catch(err => {
      membersLoadPromise = null;
      throw err;
    });

  return membersLoadPromise;
};

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

const getKstDateParts = value => {
  const date = toKstDate(value);
  if (Number.isNaN(date.getTime())) return null;

  return {
    year: date.getUTCFullYear(),
    month: padNumber(date.getUTCMonth() + 1),
    day: padNumber(date.getUTCDate()),
    hour: padNumber(date.getUTCHours()),
    minute: padNumber(date.getUTCMinutes()),
    second: padNumber(date.getUTCSeconds())
  };
};

const getCurrentKstDay = () => {
  const parts = getKstDateParts(Date.now());
  return `${parts.year}-${parts.month}-${parts.day}`;
};

const getKstDay = value => {
  const parts = getKstDateParts(value);
  if (!parts) return "";
  return `${parts.year}-${parts.month}-${parts.day}`;
};

const formatLogTime = value => {
  const parts = getKstDateParts(value);
  if (!parts) return String(value || "-");

  return `${parts.year}-${parts.month}-${parts.day} ${parts.hour}:${parts.minute}:${parts.second}`;
};

const parseAccessLogLine = line => {
  const values = String(line || "").split(",");
  if (values.length < 4) return null;

  const time = String(values[0] || "").trim();
  const type = String(values[1] || "").trim();
  const location = String(values[2] || "").trim();
  const id = String(values[3] || "").trim();

  if (!time || !type || !location || !id) return null;
  return { time, type, location, id };
};

const parseAccessLogsCsv = text => {
  const rows = String(text || "").replace(/\r/g, "").split("\n");
  const items = [];

  for (const row of rows) {
    const trimmed = row.trim();
    if (!trimmed || trimmed === "time,type,location,id") continue;

    const item = parseAccessLogLine(trimmed);
    if (!item) continue;

    items.push(item);
  }

  return items;
};

const buildCurrentStatusById = items => {
  const next = new Map();
  const sorted = Array.isArray(items)
    ? [...items].sort((left, right) => String(left?.time || "").localeCompare(String(right?.time || "")))
    : [];

  for (const item of sorted) {
    const id = String(item?.id || "").trim();
    const type = String(item?.type || "").trim();
    if (!id || !type) continue;
    next.set(id, {
      id,
      type,
      location: String(item?.location || "").trim(),
      time: String(item?.time || "").trim()
    });
  }

  return next;
};

const getBoardMode = () => $("log-current")?.value || "all";
const isCurrentListMode = () => getBoardMode() !== "all";
const getCurrentTargetType = () => {
  const mode = getBoardMode();
  if (mode === "current-entry") return "entry";
  if (mode === "current-exit") return "exit";
  return "";
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

const showAccessResult = ({ type, id, name }) => {
  const action = type === "entry" ? "입영" : "퇴영";
  const label = String(name || "").trim() || String(id || "-");
  showMessage(`${label}님 ${action}입니다`, "ok");
};

const handleDuplicateSubmit = (parsed, location, input) => {
  if (!shouldIgnoreDuplicate(location, parsed.raw)) return false;

  showDuplicateResult(parsed);
  resetInput(input);
  return true;
};

const populateLocationSelect = items => {
  const select = $("loc-select");
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
  select.value = scannerLocation && isConfiguredLocation(scannerLocation) ? scannerLocation : "";
};

const closeLocationDialog = () => {
  const dialog = $("loc-dlg");
  if (dialog?.open) dialog.close();
};

const openLocationDialog = () => {
  if (configuredLocations.length === 0) {
    showMessage("선택할 location이 없습니다.", "error");
    return false;
  }

  const dialog = $("loc-dlg");
  const select = $("loc-select");
  if (!dialog || !select) return false;

  populateLocationSelect(configuredLocations);
  dialog.showModal();
  window.setTimeout(() => {
    select.focus();
  }, 0);
  return true;
};

const activateScannerLocation = location => {
  scannerLocation = String(location || "").trim();

  const locationPanel = $("loc-pnl");
  const scannerPanel = $("scan-pnl");
  const selectedText = $("sel-loc-txt");

  if (selectedText) selectedText.textContent = scannerLocation || "-";
  if (locationPanel) locationPanel.hidden = !!scannerLocation;
  if (scannerPanel) scannerPanel.hidden = !scannerLocation;

  if (scannerLocation) {
    showMessage("바코드를 스캔해 주세요.", null);
    focusBarcodeInput();
  }
};

const setTableColumns = labels => {
  const columns = [
    $("log-col-1"),
    $("log-col-2"),
    $("log-col-3"),
    $("log-col-4"),
    $("log-col-5")
  ];

  for (let index = 0; index < columns.length; index += 1) {
    const cell = columns[index];
    const label = labels[index] || "";
    if (!cell) continue;
    cell.hidden = !label;
    cell.textContent = label;
  }
};

const getEmptyMessage = () => {
  const mode = getBoardMode();
  if (mode === "current-entry") return "현재 입영자가 없습니다.";
  if (mode === "current-exit") return "현재 퇴영자가 없습니다.";
  return "로그가 없습니다.";
};

const renderEmptyRow = colSpan => {
  const row = createElement("tr");
  const cell = createElement("td", "empty-cell", getEmptyMessage());

  cell.colSpan = colSpan;
  row.appendChild(cell);
  return row;
};

const renderCurrentList = () => {
  const body = $("log-body");
  if (!body) return;

  const query = $("log-q")?.value.trim().toLowerCase() || "";
  const order = $("log-sort")?.value || "desc";
  const targetType = getCurrentTargetType();
  const items = [...currentStatusById.values()]
    .filter(item => {
      if (!targetType || item?.type !== targetType) return false;
      if (!query) return true;

      const id = String(item?.id || "").toLowerCase();
      const name = getMemberName(item?.id).toLowerCase();
      const location = String(item?.location || "").toLowerCase();
      return id.includes(query) || name.includes(query) || location.includes(query);
    })
    .sort((left, right) => {
      const diff = String(left?.time || "").localeCompare(String(right?.time || ""));
      return order === "asc" ? diff : diff * -1;
    });

  setTableColumns(["군번", "이름", "최근 위치", "최근 시각", ""]);

  const frag = document.createDocumentFragment();

  if (items.length === 0) {
    frag.appendChild(renderEmptyRow(4));
    body.replaceChildren(frag);
    return;
  }

  for (const item of items) {
    const row = createElement("tr");

    row.appendChild(createElement("td", "", String(item?.id || "-")));
    row.appendChild(createElement("td", "", getMemberName(item?.id) || "-"));
    row.appendChild(createElement("td", "", String(item?.location || "-")));
    row.appendChild(createElement("td", "", formatLogTime(item?.time)));
    frag.appendChild(row);
  }

  body.replaceChildren(frag);
};

const renderLogs = () => {
  const body = $("log-body");
  if (!body) return;

  const day = $("log-day")?.value || getCurrentKstDay();
  const query = $("log-q")?.value.trim().toLowerCase() || "";
  const order = $("log-sort")?.value || "desc";
  const items = boardLogs
    .filter(item => {
      if (!isConfiguredLocation(item?.location)) return false;
      if (getKstDay(item?.time) !== day) return false;
      if (!query) return true;

      const id = String(item?.id || "").toLowerCase();
      const name = getMemberName(item?.id).toLowerCase();
      const location = String(item?.location || "").toLowerCase();
      return id.includes(query) || name.includes(query) || location.includes(query);
    })
    .sort((left, right) => {
      const diff = String(left?.time || "").localeCompare(String(right?.time || ""));
      return order === "asc" ? diff : diff * -1;
    });

  setTableColumns(["시간", "구분", "위치", "군번", "이름"]);

  const frag = document.createDocumentFragment();

  if (items.length === 0) {
    frag.appendChild(renderEmptyRow(5));
    body.replaceChildren(frag);
    return;
  }

  for (const item of items) {
    const row = createElement("tr");

    row.appendChild(createElement("td", "", formatLogTime(item?.time)));
    row.appendChild(createElement("td", "", item?.type === "entry" ? "입영" : "퇴영"));
    row.appendChild(createElement("td", "", String(item?.location || "-")));
    row.appendChild(createElement("td", "", String(item?.id || "-")));
    row.appendChild(createElement("td", "", getMemberName(item?.id) || "-"));
    frag.appendChild(row);
  }

  body.replaceChildren(frag);
};

const renderBoard = () => {
  if (isCurrentListMode()) {
    renderCurrentList();
    return;
  }

  renderLogs();
};

const syncBoardControls = () => {
  const dayField = $("log-day-fld");
  const dayInput = $("log-day");
  const isCurrentMode = isCurrentListMode();

  if (dayField) dayField.hidden = isCurrentMode;
  if (dayInput) dayInput.disabled = isCurrentMode;
};

const refreshLogs = async () => {
  const body = $("log-body");
  if (!body) return;

  const status = $("bd-stat");
  const updated = $("bd-upd");

  try {
    const membersTask = loadMembers().catch(() => null);
    const [locations, csvText] = await Promise.all([loadLocations(), fetchLogsCsv()]);

    setConfiguredLocations(locations);
    boardLogs = parseAccessLogsCsv(csvText);
    currentStatusById = buildCurrentStatusById(boardLogs);
    await membersTask;
    syncBoardControls();
    renderBoard();
    if (status) status.textContent = "정상";
    if (updated) updated.textContent = new Date().toLocaleString();
  } catch {
    if (status) status.textContent = "실패";
  }
};

const startBoardPolling = () => {
  const root = $("log-body");
  if (!root) return;

  if (boardTimerId !== null) clearInterval(boardTimerId);

  boardTimerId = window.setInterval(() => {
    void refreshLogs();
  }, BOARD_POLL_MS);
};

const submitAccess = async () => {
  const input = $("barcode");
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
    showAccessResult({ type, id, name: getMemberName(id) });
    clearInput(input);
  } catch (err) {
    showMessage(err.message || "처리에 실패했습니다.", "error");
    clearInput(input);
  } finally {
    focusBarcodeInput();
  }
};

const initScannerPage = async () => {
  const input = $("barcode");
  const button = $("loc-btn");
  const dialog = $("loc-dlg");
  const dialogForm = $("loc-form");
  const select = $("loc-select");
  const cancelButton = $("loc-cancel");

  if (!input || !button || !dialog || !dialogForm || !select || !cancelButton) return;

  void loadMembers().catch(() => null);

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
    openLocationDialog();
  });

  dialogForm.addEventListener("submit", event => {
    event.preventDefault();

    const location = select.value.trim();
    if (!location) {
      showMessage("위치를 선택해 주세요.", "error");
      select.focus();
      return;
    }

    dialog.returnValue = "selected";
    closeLocationDialog();
    activateScannerLocation(location);
  });

  cancelButton.addEventListener("click", () => {
    closeLocationDialog();
    showMessage("위치 선택이 취소되었습니다.", "error");
  });

  dialog.addEventListener("close", () => {
    if (scannerLocation || dialog.returnValue === "selected") return;
    showMessage("위치 선택이 취소되었습니다.", "error");
  });

  document.addEventListener("click", event => {
    if (!scannerLocation) return;
    if (event.target === button) return;

    focusBarcodeInput();
  });

  try {
    await loadLocations();
    populateLocationSelect(configuredLocations);

    if (configuredLocations.length === 0) {
      showMessage("선택할 location이 없습니다.", "error");
      button.disabled = true;
      return;
    }

    showMessage("위치를 선택해 주세요.", null);
    button.focus();
    openLocationDialog();
  } catch (err) {
    showMessage(err.message || "location 목록을 불러오지 못했습니다.", "error");
    button.disabled = true;
  }
};

const initBoardPage = () => {
  const root = $("log-body");
  const button = $("bd-refresh");
  const dayInput = $("log-day");
  const currentInput = $("log-current");
  const searchInput = $("log-q");
  const sortInput = $("log-sort");

  if (!root) return;

  if (dayInput && !dayInput.value) dayInput.value = getCurrentKstDay();

  if (button) button.addEventListener("click", () => void refreshLogs());
  if (dayInput) dayInput.addEventListener("change", () => renderBoard());
  if (currentInput) currentInput.addEventListener("change", () => {
    syncBoardControls();
    renderBoard();
  });
  if (searchInput) searchInput.addEventListener("input", () => renderBoard());
  if (sortInput) sortInput.addEventListener("change", () => renderBoard());

  void loadMembers().catch(() => null);
  syncBoardControls();
  void refreshLogs();
  startBoardPolling();
};

void initScannerPage();
initBoardPage();
