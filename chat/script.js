(function () {
  const stateEl = document.getElementById("conn-state");
  const messagesEl = document.getElementById("messages");
  const formEl = document.getElementById("chat-form");
  const inputEl = document.getElementById("chat-input");
  const buttonEl = document.getElementById("send-button");

  let lastId = 0;

  function setState(kind, text) {
    stateEl.textContent = text;
    stateEl.className = "badge";

    if (kind === "ok") {
      stateEl.classList.add("badge-ok");
      return;
    }

    if (kind === "off") {
      stateEl.classList.add("badge-off");
      return;
    }

    stateEl.classList.add("badge-warn");
  }

  function sleep(ms) {
    return new Promise(function (resolve) {
      window.setTimeout(resolve, ms);
    });
  }

  async function fetchJson(url, options) {
    const response = await fetch(url, options);
    if (!response.ok) {
      throw new Error("HTTP " + response.status);
    }
    return response.json();
  }

  function formatTime(iso) {
    const date = new Date(iso);
    if (Number.isNaN(date.getTime())) {
      return "";
    }
    return date.toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit"
    });
  }

  function addMessage(message) {
    const row = document.createElement("article");
    row.className = "msg";

    const meta = document.createElement("div");
    meta.className = "meta";

    const sender = document.createElement("span");
    sender.className = "sender";
    sender.textContent = message.sender || "unknown";

    const time = document.createElement("time");
    time.className = "time";
    time.textContent = formatTime(message.createdAt);

    const text = document.createElement("div");
    text.className = "text";
    text.textContent = message.text || "";

    meta.appendChild(sender);
    meta.appendChild(time);
    row.appendChild(meta);
    row.appendChild(text);
    messagesEl.appendChild(row);
    messagesEl.scrollTop = messagesEl.scrollHeight;
  }

  async function initCursor() {
    const payload = await fetchJson("/messages/latest");
    lastId = payload.latestId || 0;
  }

  async function pollLoop() {
    while (true) {
      try {
        const payload = await fetchJson("/messages?after=" + encodeURIComponent(lastId));
        const items = Array.isArray(payload) ? payload : (payload ? [payload] : []);

        if (items.length > 0) {
          items.forEach(addMessage);
          lastId = items[items.length - 1].id;
        }

        setState("ok", "connected");
      } catch (_error) {
        setState("off", "disconnected");
        await sleep(2000);
      }
    }
  }

  formEl.addEventListener("submit", async function (event) {
    event.preventDefault();

    const text = inputEl.value.trim();
    if (!text) {
      inputEl.focus();
      return;
    }

    buttonEl.disabled = true;

    try {
      await fetchJson("/messages", {
        method: "POST",
        headers: {
          "Content-Type": "application/json"
        },
        body: JSON.stringify({ text: text })
      });
      inputEl.value = "";
      inputEl.focus();
      setState("ok", "connected");
    } catch (_error) {
      setState("off", "send failed");
    } finally {
      buttonEl.disabled = false;
    }
  });

  (async function start() {
    try {
      setState("warn", "starting");
      await initCursor();
      setState("ok", "connected");
      pollLoop();
    } catch (_error) {
      setState("off", "startup failed");
    }
  })();
})();
