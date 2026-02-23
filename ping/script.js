(() => {
  const q = (s) => document.querySelector(s);
  const el = {
    rows: q("#rows"),
    lf: q("#lf"),
    fs: q("#fs"),
    ep: q("#ep"),
    rf: q("#rf"),
    ar: q("#ar")
  };

  const qs = new URLSearchParams(location.search);
  const port = Number(qs.get("port") || "8080");
  const url = `http://localhost:${port}/pings`;
  el.ep.textContent = url;

  let timer = null;
  let okAt = null;

  const fmt = (v) => {
    if (!v) return "—";
    const d = new Date(v);
    return Number.isNaN(d.getTime()) ? "—" : d.toLocaleString();
  };

  const h = (v) =>
    String(v)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");

  const badge = (s) => `<span class="b ${s === "success" ? "s" : s === "timeout" ? "t" : "x"}">${h(s || "error")}</span>`;

  const draw = (arr) => {
    const now = h(new Date().toLocaleString());
    if (!Array.isArray(arr) || arr.length === 0) {
      el.rows.innerHTML = `<tr><td colspan="5" class="e">No data.</td></tr>`;
      return;
    }
    el.rows.innerHTML = arr.map((r) => `
      <tr>
        <td class="mono">${h(r?.dest ?? "—")}</td>
        <td>${badge(r?.status)}</td>
        <td class="num">${r?.rtt == null ? "—" : h(String(r.rtt))}</td>
        <td>${h(fmt(r?.successedAt))}</td>
        <td>${now}</td>
      </tr>`).join("");
  };

  const run = async () => {
    try {
      el.fs.textContent = "Fetching...";
      el.fs.className = "";
      const res = await fetch(url, { method: "GET" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      draw(await res.json());
      okAt = new Date();
      el.lf.textContent = okAt.toLocaleString();
      el.fs.textContent = "OK";
      el.fs.className = "ok";
    } catch (e) {
      el.fs.textContent = `Error: ${e?.message || String(e)}`;
      el.fs.className = "bad";
      el.lf.textContent = okAt ? okAt.toLocaleString() : "—";
    }
  };

  const start = () => { stop(); timer = setInterval(run, 10000); };
  const stop = () => { if (timer != null) { clearInterval(timer); timer = null; } };

  el.rf.addEventListener("click", () => void run());
  el.ar.addEventListener("change", () => (el.ar.checked ? start() : stop()));
  void run();
  start();
})();
