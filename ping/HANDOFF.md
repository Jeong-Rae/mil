# Handoff

## 2026-02-23

- Fixed interactive paste failure in `server.ps1`: changed `$baseDir` initialization from a multiline assignment+`if/else` form to a single-line expression so `else` is not executed as a separate command when pasting into `pwsh`.
- Root cause observed in interactive sessions: line-by-line paste could split
  - `$baseDir =`
  - `if (...) { ... }`
  - `else { ... }`
  causing `else: The term 'else' is not recognized...` and cascading `$ConfigPath`/`$hosts` unbound errors under `Set-StrictMode -Version Latest`.
- Existing behaviors (`-File` execution, CORS/API contract, scheduler) are unchanged.
- Improved ping diagnostics in `server.ps1` logs:
  - Added `error=<detail>` to each ping log line.
  - For exceptions, logs fully-qualified exception type + message.
  - For non-timeout/non-success replies, logs `replyStatus=<IPStatus>`.
  - API response shape is unchanged (diagnostics are console-log only).

## 2026-02-15

- Fixed `pwsh` crash: replaced `System.Threading.Timer` + ScriptBlock callback in `server.ps1` with a pure-.NET `PingScheduler` (C# via `Add-Type`) so the ping loop runs on background threads without requiring a PowerShell runspace.
- Added per-ping console logging (timestamp/host/status/rtt/successedAt/elapsedMs). Logging is enabled by default and can be disabled with `-NoPingLog`.
- Added `-BindAddress` (default: `127.0.0.1`) to control the `HttpListener` prefix host.
- Made `server.ps1` paste-friendly by removing the top-level `param(...)` block and parsing options from `$args`, so it can be pasted into an interactive `pwsh` terminal and still work with `-File`.
- API behavior preserved:
  - `GET /pings` returns results in `config.json` host order.
  - `GET /ping?host=...` returns the single host record.
  - CORS headers unchanged.
- Note: In this sandboxed environment, binding/listening on ports is blocked (e.g. `HttpListener.Start()` can throw "Permission denied"), so end-to-end HTTP testing was not possible here.
