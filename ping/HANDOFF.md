# Handoff

## 2026-02-15

- Fixed `pwsh` crash: replaced `System.Threading.Timer` + ScriptBlock callback in `server.ps1` with a pure-.NET `PingScheduler` (C# via `Add-Type`) so the ping loop runs on background threads without requiring a PowerShell runspace.
- Added per-ping console logging (timestamp/host/status/rtt/successedAt/elapsedMs). Logging is enabled by default and can be disabled with `-NoPingLog`.
- Added `-BindAddress` (default: `127.0.0.1`) to control the `HttpListener` prefix host.
- API behavior preserved:
  - `GET /pings` returns results in `config.json` host order.
  - `GET /ping?host=...` returns the single host record.
  - CORS headers unchanged.
- Note: In this sandboxed environment, binding/listening on ports is blocked (e.g. `HttpListener.Start()` can throw "Permission denied"), so end-to-end HTTP testing was not possible here.
