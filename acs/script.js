const DUPLICATE_WINDOW_MS = 15000;
const BOARD_POLL_MS = 5000;

function $(id) {
  return document.getElementById(id);
}

let boardTimerId = null;
const recentScans = {};

function fetchJson(url, options) {
  return fetch(url, options).then(async function (response) {
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
  });
}

function showMessage(text, tone) {
  const messageTextEl = $("message-text");
  if (!messageTextEl) {
    return;
  }

  messageTextEl.textContent = text;
  messageTextEl.className = "message-text";
  if (tone) {
    messageTextEl.classList.add("tone-" + tone);
  }
}

function focusBarcodeInput() {
  const barcodeInputEl = $("barcode-input");
  if (!barcodeInputEl) {
    return;
  }

  window.setTimeout(function () {
    const locationInputEl = $("location-input");
    const nextBarcodeInputEl = $("barcode-input");

    if (!nextBarcodeInputEl) {
      return;
    }

    if (document.activeElement === locationInputEl) {
      return;
    }

    nextBarcodeInputEl.focus();
    nextBarcodeInputEl.select();
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

function fetchStatus(location) {
  return fetchJson("/status?location=" + encodeURIComponent(location));
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

function refreshScannerStatus(location) {
  if (!location) {
    return Promise.resolve([]);
  }

  return fetchStatus(location).then(function (payload) {
    return Array.isArray(payload && payload.ids) ? payload.ids.slice() : [];
  });
}

function createElement(tagName, className, text) {
  const element = document.createElement(tagName);

  if (className) {
    element.className = className;
  }

  if (typeof text !== "undefined") {
    element.textContent = text;
  }

  return element;
}

function renderBoard(groups) {
  const boardGroupsEl = $("board-groups");
  if (!boardGroupsEl) {
    return;
  }

  const items = Array.isArray(groups) ? groups : [];
  const fragment = document.createDocumentFragment();

  if (items.length === 0) {
    const cardEl = createElement("article", "board-card empty-card");
    cardEl.appendChild(createElement("h2", "", "현황 없음"));
    cardEl.appendChild(createElement("p", "", "아직 데이터가 없습니다."));
    fragment.appendChild(cardEl);
    boardGroupsEl.replaceChildren(fragment);
    return;
  }

  items.forEach(function (group) {
    const location = group && group.location ? String(group.location) : "unknown";
    const ids = Array.isArray(group && group.ids) ? group.ids : [];
    const cardEl = createElement("article", "board-card");
    const listEl = createElement("ul", "id-list");

    cardEl.appendChild(createElement("h2", "", location));
    cardEl.appendChild(createElement("div", "board-count", "인원 " + ids.length + "명"));

    if (ids.length === 0) {
      listEl.appendChild(createElement("li", "empty-item", "현재 인원 없음"));
    } else {
      ids.forEach(function (id) {
        listEl.appendChild(createElement("li", "id-item", id));
      });
    }

    cardEl.appendChild(listEl);
    fragment.appendChild(cardEl);
  });

  boardGroupsEl.replaceChildren(fragment);
}

function refreshBoard() {
  const boardGroupsEl = $("board-groups");
  if (!boardGroupsEl) {
    return Promise.resolve();
  }

  return fetchAllStatus().then(function (payload) {
    const boardStatusEl = $("board-status");
    const boardUpdatedEl = $("board-updated");

    renderBoard(payload);
    if (boardStatusEl) {
      boardStatusEl.textContent = "정상";
    }
    if (boardUpdatedEl) {
      boardUpdatedEl.textContent = new Date().toLocaleString();
    }
  }).catch(function () {
    const boardStatusEl = $("board-status");

    if (boardStatusEl) {
      boardStatusEl.textContent = "실패";
    }
  });
}

function startBoardPolling() {
  const boardGroupsEl = $("board-groups");
  if (!boardGroupsEl) {
    return;
  }

  if (boardTimerId !== null) {
    clearInterval(boardTimerId);
  }

  boardTimerId = window.setInterval(function () {
    void refreshBoard();
  }, BOARD_POLL_MS);
}

function handleSubmit(event) {
  event.preventDefault();

  const locationInputEl = $("location-input");
  const barcodeInputEl = $("barcode-input");
  const location = locationInputEl ? locationInputEl.value.trim() : "";
  const parsed = parseBarcode(barcodeInputEl ? barcodeInputEl.value : "");

  if (!location) {
    showMessage("location을 입력해 주세요.", "error");
    focusBarcodeInput();
    return;
  }

  if (!parsed.ok) {
    showMessage(parsed.message, "error");
    if (barcodeInputEl) {
      barcodeInputEl.value = "";
    }
    focusBarcodeInput();
    return;
  }

  refreshScannerStatus(location).then(function (ids) {
    const alreadyEntered = ids.indexOf(parsed.id) >= 0;

    if (shouldIgnoreDuplicate(location, parsed.raw)) {
      if (parsed.type === "entry") {
        showMessage(parsed.id + "님 이미 입영 처리되었습니다", "warn");
      } else {
        showMessage(parsed.id + "님 이미 퇴영 처리되었습니다", "warn");
      }

      if (barcodeInputEl) {
        barcodeInputEl.value = "";
      }
      focusBarcodeInput();
      return;
    }

    if (parsed.type === "entry" && alreadyEntered) {
      markRecentScan(location, parsed.raw);
      showMessage(parsed.id + "님 이미 입영 처리되었습니다", "warn");
      if (barcodeInputEl) {
        barcodeInputEl.value = "";
      }
      focusBarcodeInput();
      return;
    }

    if (parsed.type === "exit" && !alreadyEntered) {
      markRecentScan(location, parsed.raw);
      showMessage(parsed.id + "님 이미 퇴영 처리되었습니다", "warn");
      if (barcodeInputEl) {
        barcodeInputEl.value = "";
      }
      focusBarcodeInput();
      return;
    }

    return postAccess({
      type: parsed.type,
      id: parsed.id,
      location: location
    }).then(function () {
      markRecentScan(location, parsed.raw);
      if (parsed.type === "entry") {
        showMessage(parsed.id + "님 입영입니다", "ok");
      } else {
        showMessage(parsed.id + "님 퇴영입니다", "ok");
      }

      if (barcodeInputEl) {
        barcodeInputEl.value = "";
      }

      return refreshScannerStatus(location);
    }).catch(function (error) {
      showMessage(error.message || "처리에 실패했습니다.", "error");
      if (barcodeInputEl) {
        barcodeInputEl.value = "";
      }
    }).finally(function () {
      focusBarcodeInput();
    });
  }).catch(function (error) {
    showMessage(error.message || "상태 조회에 실패했습니다.", "error");
    if (barcodeInputEl) {
      barcodeInputEl.value = "";
    }
    focusBarcodeInput();
  });
}

function initScannerPage() {
  const scanFormEl = $("scan-form");
  const barcodeInputEl = $("barcode-input");

  if (!scanFormEl || !barcodeInputEl) {
    return;
  }

  scanFormEl.addEventListener("submit", handleSubmit);

  barcodeInputEl.addEventListener("keydown", function (event) {
    if (event.key !== "Enter") {
      return;
    }

    event.preventDefault();
    scanFormEl.requestSubmit();
  });

  barcodeInputEl.addEventListener("input", function () {
    if (!barcodeInputEl.value.includes("\n") && !barcodeInputEl.value.includes("\r")) {
      return;
    }

    barcodeInputEl.value = barcodeInputEl.value.replace(/[\r\n]+/g, "");
    scanFormEl.requestSubmit();
  });

  barcodeInputEl.addEventListener("blur", function () {
    focusBarcodeInput();
  });

  document.addEventListener("click", function (event) {
    const locationInputEl = $("location-input");

    if (event.target === locationInputEl) {
      return;
    }

    focusBarcodeInput();
  });

  focusBarcodeInput();
}

function initBoardPage() {
  const boardGroupsEl = $("board-groups");
  const refreshBoardButtonEl = $("refresh-board-button");

  if (!boardGroupsEl) {
    return;
  }

  if (refreshBoardButtonEl) {
    refreshBoardButtonEl.addEventListener("click", function () {
      void refreshBoard();
    });
  }

  void refreshBoard();
  startBoardPolling();
}

initScannerPage();
initBoardPage();
