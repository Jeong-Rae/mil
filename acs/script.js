const DUPLICATE_WINDOW_MS = 15000;
const BOARD_POLL_MS = 5000;

function $(id) {
  return document.getElementById(id);
}

let boardTimerId = null;
const recentScans = {};

async function fetchJson(url, options) {
  const response = await fetch(url, options);
  const text = await response.text();
  let payload = null;

  if (text) {
    try {
      payload = JSON.parse(text);
    } catch (error) {
      payload = null;
    }
  }

  if (!response.ok) {
    const message = payload && payload.message ? payload.message : "HTTP " + response.status;
    const requestError = new Error(message);
    requestError.status = response.status;
    requestError.payload = payload;
    throw requestError;
  }

  return payload;
}

function showMessage(text, tone) {
  const el = $("message-text");
  if (!el) {
    return;
  }

  el.textContent = text;
  el.className = "message-text";
  if (tone) {
    el.classList.add("tone-" + tone);
  }
}

function focusBarcodeInput() {
  const input = $("barcode-input");
  if (!input) {
    return;
  }

  window.setTimeout(function () {
    const location = $("location-input");
    const next = $("barcode-input");

    if (!next) {
      return;
    }

    if (document.activeElement === location) {
      return;
    }

    next.focus();
    next.select();
  }, 0);
}

function parseBarcode(rawValue) {
  const value = String(rawValue || "").replace(/\r/g, "").replace(/\n/g, "").trim();
  const upper = value.slice(0, 2).toUpperCase();
  const id = value.slice(2).trim();

  if (!value || !id) {
    return { ok: false, message: "바코드를 다시 확인해 주세요." };
  }

  if (upper === "EN") {
    return { ok: true, type: "entry", id: id, raw: value };
  }

  if (upper === "EX") {
    return { ok: true, type: "exit", id: id, raw: value };
  }

  return { ok: false, message: "지원하지 않는 바코드입니다." };
}

function getDuplicateKey(location, rawBarcode) {
  return String(location || "") + "|" + String(rawBarcode || "");
}

function shouldIgnoreDuplicate(location, rawBarcode) {
  const key = getDuplicateKey(location, rawBarcode);
  const lastAt = recentScans[key];
  if (!lastAt) {
    return false;
  }

  return Date.now() - lastAt < DUPLICATE_WINDOW_MS;
}

function markRecentScan(location, rawBarcode) {
  recentScans[getDuplicateKey(location, rawBarcode)] = Date.now();
}

function fetchAllStatus() {
  return fetchJson("/status");
}

function postAccess(payload) {
  return fetchJson("/access", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify(payload)
  });
}

function createElement(tagName, className, text) {
  const el = document.createElement(tagName);

  if (className) {
    el.className = className;
  }

  if (typeof text !== "undefined") {
    el.textContent = text;
  }

  return el;
}

function clearInput(input) {
  if (input) {
    input.value = "";
  }
}

function resetInput(input) {
  clearInput(input);
  focusBarcodeInput();
}

function showDuplicateResult(parsed) {
  const action = parsed.type === "entry" ? "입영" : "퇴영";
  showMessage(`${parsed.id}님 이미 ${action} 처리되었습니다`, "warn");
}

function showAccessResult(parsed) {
  const action = parsed.type === "entry" ? "입영" : "퇴영";
  showMessage(`${parsed.id}님 ${action}입니다`, "ok");
}

function handleDuplicateSubmit(parsed, location, input) {
  if (shouldIgnoreDuplicate(location, parsed.raw)) {
    showDuplicateResult(parsed);
    resetInput(input);
    return true;
  }

  return false;
}

function renderBoard(groups) {
  const root = $("board-groups");
  if (!root) {
    return;
  }

  const items = Array.isArray(groups) ? groups : [];
  const fragment = document.createDocumentFragment();

  if (items.length === 0) {
    const card = createElement("article", "board-card empty-card");
    card.appendChild(createElement("h2", "", "현황 없음"));
    card.appendChild(createElement("p", "", "아직 데이터가 없습니다."));
    fragment.appendChild(card);
    root.replaceChildren(fragment);
    return;
  }

  items.forEach(function (group) {
    const location = group && group.location ? String(group.location) : "unknown";
    const ids = Array.isArray(group && group.ids) ? group.ids : [];
    const card = createElement("article", "board-card");
    const list = createElement("ul", "id-list");

    card.appendChild(createElement("h2", "", location));
    card.appendChild(createElement("div", "board-count", "인원 " + ids.length + "명"));

    if (ids.length === 0) {
      list.appendChild(createElement("li", "empty-item", "현재 인원 없음"));
    } else {
      ids.forEach(function (id) {
        list.appendChild(createElement("li", "id-item", id));
      });
    }

    card.appendChild(list);
    fragment.appendChild(card);
  });

  root.replaceChildren(fragment);
}

async function refreshBoard() {
  const root = $("board-groups");
  if (!root) {
    return;
  }

  try {
    const payload = await fetchAllStatus();
    const status = $("board-status");
    const updated = $("board-updated");

    renderBoard(payload);
    if (status) {
      status.textContent = "정상";
    }
    if (updated) {
      updated.textContent = new Date().toLocaleString();
    }
  } catch (error) {
    const status = $("board-status");

    if (status) {
      status.textContent = "실패";
    }
  }
}

function startBoardPolling() {
  const root = $("board-groups");
  if (!root) {
    return;
  }

  if (boardTimerId !== null) {
    clearInterval(boardTimerId);
  }

  boardTimerId = window.setInterval(function () {
    void refreshBoard();
  }, BOARD_POLL_MS);
}

async function handleSubmit(event) {
  event.preventDefault();

  const loc = $("location-input");
  const input = $("barcode-input");
  const location = loc ? loc.value.trim() : "";
  const parsed = parseBarcode(input ? input.value : "");

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

  if (handleDuplicateSubmit(parsed, location, input)) {
    return;
  }

  try {
    await postAccess({
      type: parsed.type,
      id: parsed.id,
      location: location
    });

    markRecentScan(location, parsed.raw);
    showAccessResult(parsed);
    clearInput(input);
  } catch (error) {
    showMessage(error.message || "처리에 실패했습니다.", "error");
    clearInput(input);
  } finally {
    focusBarcodeInput();
  }
}

function initScannerPage() {
  const form = $("scan-form");
  const input = $("barcode-input");

  if (!form || !input) {
    return;
  }

  form.addEventListener("submit", handleSubmit);

  input.addEventListener("keydown", function (event) {
    if (event.key !== "Enter") {
      return;
    }

    event.preventDefault();
    form.requestSubmit();
  });

  input.addEventListener("input", function () {
    if (!input.value.includes("\n") && !input.value.includes("\r")) {
      return;
    }

    input.value = input.value.replace(/[\r\n]+/g, "");
    form.requestSubmit();
  });

  input.addEventListener("blur", function () {
    focusBarcodeInput();
  });

  document.addEventListener("click", function (event) {
    const location = $("location-input");

    if (event.target === location) {
      return;
    }

    focusBarcodeInput();
  });

  focusBarcodeInput();
}

function initBoardPage() {
  const root = $("board-groups");
  const button = $("refresh-board-button");

  if (!root) {
    return;
  }

  if (button) {
    button.addEventListener("click", function () {
      void refreshBoard();
    });
  }

  void refreshBoard();
  startBoardPolling();
}

initScannerPage();
initBoardPage();
