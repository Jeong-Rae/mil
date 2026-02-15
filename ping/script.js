(() => {
  const $ = (sel) => document.querySelector(sel);

  const rowsEl = $("#rows");
  const lastFetchEl = $("#lastFetch");
  const fetchStatusEl = $("#fetchStatus");
  const endpointTextEl = $("#endpointText");
  const refreshBtn = $("#refreshNow");
  const autoRefreshEl = $("#autoRefresh");

  const qs = new URLSearchParams(window.location.search);
  const port = Number(qs.get("port") || "8080");
  const baseUrl = `http://localhost:${port}`;
  const endpoint = `${baseUrl}/pings`;

  endpointTextEl.textContent = endpoint;

  let intervalId = null;
  let lastGoodFetchAt = null;

  function fmtLocal(iso) {
    if (!iso) return "—";
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return "—";
    return d.toLocaleString();
  }

  function escapeHtml(s) {
    return String(s)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function statusBadge(status) {
    const cls =
      status === "success"
        ? "badge success"
        : status === "timeout"
          ? "badge timeout"
          : "badge error";
    const label = status || "error";
    return `<span class="${cls}">${escapeHtml(label)}</span>`;
  }

  function render(data) {
    const now = new Date();
    const lastUpdated = now.toLocaleString();

    if (!Array.isArray(data) || data.length === 0) {
      rowsEl.innerHTML = `<tr><td colspan="5" class="empty">No data.</td></tr>`;
      return;
    }

    rowsEl.innerHTML = data
      .map((r) => {
        const dest = escapeHtml(r?.dest ?? "—");
        const status = statusBadge(r?.status);
        const rtt = r?.rtt == null ? "—" : escapeHtml(String(r.rtt));
        const succeededAt = escapeHtml(fmtLocal(r?.successedAt));
        return `
          <tr>
            <td class="mono">${dest}</td>
            <td>${status}</td>
            <td class="num">${rtt}</td>
            <td>${succeededAt}</td>
            <td>${escapeHtml(lastUpdated)}</td>
          </tr>
        `;
      })
      .join("");
  }

  async function fetchAndRender() {
    try {
      fetchStatusEl.textContent = "Fetching...";
      fetchStatusEl.className = "meta-value";

      const res = await fetch(endpoint, { method: "GET" });
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      const data = await res.json();

      render(data);

      lastGoodFetchAt = new Date();
      lastFetchEl.textContent = lastGoodFetchAt.toLocaleString();
      fetchStatusEl.textContent = "OK";
      fetchStatusEl.className = "meta-value ok";
    } catch (e) {
      fetchStatusEl.textContent = `Error: ${e && e.message ? e.message : String(e)}`;
      fetchStatusEl.className = "meta-value bad";

      if (lastGoodFetchAt) {
        lastFetchEl.textContent = lastGoodFetchAt.toLocaleString();
      } else {
        lastFetchEl.textContent = "—";
      }
    }
  }

  function start() {
    stop();
    intervalId = window.setInterval(fetchAndRender, 10000);
  }

  function stop() {
    if (intervalId != null) {
      window.clearInterval(intervalId);
      intervalId = null;
    }
  }

  refreshBtn.addEventListener("click", () => void fetchAndRender());
  autoRefreshEl.addEventListener("change", () => {
    if (autoRefreshEl.checked) start();
    else stop();
  });

  // Initial fetch on load, then start interval.
  void fetchAndRender();
  start();
})();

