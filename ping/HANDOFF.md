# Handoff

## 2026-02-26

- Fixed worker silent-stop issue in `server.ps1` logging:
  - Root cause: inline `WriteLine("{...}" -f ...)` formatting path in worker raised runtime format exception.
  - Change: build `$logLine` first with `-f`, then call `[Console]::WriteLine($logLine)`.
  - Result: worker no longer dies on first log write; ping logs continue as expected.

- Updated ping logging policy in `server.ps1`:
  - Replaced worker flag semantics from "disable all logs" to "include success logs".
  - `LogSuccess = $true`: logs success + failure.
  - `LogSuccess = $false`: logs failure only.
  - Implemented via `shouldLog = (status != success) OR IncludeSuccessLog`.

- Fixed PowerShell automatic variable collision in `server.ps1`:
  - Replaced loop variable `$host` and parameter `$Host` usages with `$dest` / `-Dest`.
  - Resolved runtime error: `Cannot overwrite variable Host because it is read-only or constant.`
  - Kept API behavior and record schema unchanged.

- `server.ps1` scheduler migration completed on latest edited file:
  - Removed C# `Add-Type` / `PingScheduler` dependency.
  - Added pure PowerShell worker runspace (`StartPingWorker` / `StopPingWorker`) running a 10s loop (`Ping.Send(host, 2000)` per host).
  - Kept in-memory latest-record model (`dest/rtt/status/successedAt`) and API shape (`/pings`, `/ping`) intact.
  - Added thread-safe shared state via synchronized hashtables for cross-runspace read/write.
- Listener conflict/cleanup hardening:
  - Added explicit guidance log when `HttpListener.Start()` fails (possible existing process on same bind/port).
  - Ensured worker/runspace is stopped in `finally` even when listener start/runtime fails.
- Validation:
  - `server.ps1` parser check passed (`PARSE_OK`).

- 경로 기준 변경:
  - `server.ps1`의 `config.json` 탐색 기준을 스크립트 위치(`$PSScriptRoot`)에서 실행 위치(`cwd`)로 변경.
  - `$CfgPath = Join-Path (Get-Location).Path "config.json"` 형태로 고정.
  - 파서 검사 결과 `PARSE_OK`.

- 주석 정리:
  - `server.ps1`에서 입력 가이드 주석 4개(`Port`, `BindAddress`, `NoPingLog`, `ConfigPath`)만 남기고 나머지 주석 제거.
  - `Add-Type` C# 블록 내 타입/함수 설명 주석도 모두 제거.
  - 정리 후 파서 검사 결과 `PARSE_OK`.

- 사용자 의도 보정 반영:
  - `server.ps1`의 `Main` 설정 변수 주석을 타입 설명에서 입력 가이드 형식으로 변경.
  - 예시 포함: `Port 입력, e.g: 8080`, `BindAddress 입력, e.g: localhost`, `ConfigPath 입력, e.g: ./config.json`.

- `server.ps1`의 가독성 보강:
  - PowerShell 함수 선언 위에 함수 시그니처/반환 형태를 한 줄 주석으로 추가.
  - PowerShell 변수 선언 위에 예상 타입 한 줄 주석을 추가.
  - `Add-Type` C# 블록 내 주요 필드/로컬 변수/메서드에도 타입 주석을 추가.
- 수정 후 `server.ps1` 파서 검사 결과 `PARSE_OK` 확인.

- `server.ps1`에서 `Main -Argv $args` 호출과 `Main` 내부 인자 파싱(`-Port`, `-BindAddress`, `-ConfigPath`, `-NoPingLog`)을 제거함.
  - 포트/바인드/설정파일 경로/로그 여부는 실행시 주입하지 않고 스크립트 내부 변수로만 관리하도록 고정.
- 입력 형식 검증 단순화:
  - `GetHosts`의 `config.json` 존재/형식/빈 배열 검증 분기 제거.
  - `/ping` API의 `host` 공백/누락(400) 검증 제거 후, 구성 host 포함 여부만 확인(미포함 시 404).
- `server.ps1` 파서 검사 수행: `PARSE_OK`.

- Discussed pure PowerShell 5.1 scheduler options without C# (`Add-Type`) and compared:
  - `Runspace + while { ping tick; Start-Sleep 10 }` (recommended for stability/operability).
  - `System.Threading.Timer` (possible but fragile due to runspace binding/reentrancy/cleanup complexity in PS 5.1).
  - `System.Timers.Timer + Register-ObjectEvent` (simpler than Threading.Timer but adds event queue/cleanup overhead).
- Agreed to prioritize "single listener instance" operation to avoid port conflicts while server is already running:
  - Never start a second `HttpListener` on the same port.
  - For migration, use graceful stop/start or temporary alternate port cutover.
- No code change applied yet in this step; this entry records the implementation direction decision.

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
- Refactored `server.ps1` for manual typing in isolated environments:
  - Removed long explanatory comments and non-essential inline comments.
  - Shortened internal function/variable names (`GetHosts`, `SendJson`, `SendEmpty`, `$Bind`, `$CfgPath`, `$base`) while keeping CLI args unchanged (`-BindAddress`, `-ConfigPath`).
  - Simplified startup log/error text to reduce typing burden.
  - Behavior/API contract unchanged.
- Wrapped runtime flow into `Main` in `server.ps1` and moved execution to the final `Main -Argv $args` call.
  - Prevents partial execution while users are still pasting/typing code in interactive `pwsh`.
  - Preserves both usage modes: interactive paste and `pwsh -File`.
- Applied the same manual-typing optimization to frontend files:
  - `index.html`: shortened ids/classes and removed optional footer/help text.
  - `script.js`: shortened variable/function names, kept behavior (initial fetch + 10s polling + refresh button + auto-refresh toggle).
  - `style.css`: renamed selectors to match compact HTML and compressed rule formatting while preserving Confluence-like visual style.
  - Verified `script.js` syntax parse (`node --check`) and HTML/JS id wiring.
- Reformatted `style.css` back to readable block-style formatting (non-minified) while keeping the compact selector names used by current `index.html`/`script.js`.
- Changed default server bind address in `server.ps1` from `127.0.0.1` to `localhost` to match frontend endpoint usage and reduce host-header mismatch (`localhost` vs `127.0.0.1`) during local testing.
- Fixed frontend endpoint resolution for non-local browser contexts:
  - `script.js` no longer hardcodes `http://localhost:${port}/pings`.
  - It now derives host/protocol from page context (`location`) and supports overrides via query params (`?host=...&proto=...&port=...`).
  - Prevents `ERR_CONNECTION_REFUSED` when browser and PowerShell server are not in the same localhost namespace.
- Added Codespaces/GitHub port-forwarding aware endpoint logic in `script.js`:
  - Detects `*.app.github.dev` host pattern and rewrites to `...-<apiPort>.app.github.dev` instead of appending `:<port>`.
  - Example fix: avoids broken `...-5500.app.github.dev:8080/pings` and generates `...-8080.app.github.dev/pings`.
  - Added `?api=<full-url>` override for explicit endpoint control.
- Per user direction, simplified frontend back to `file://`-only usage:
  - `script.js` endpoint is fixed to `http://localhost:${port}/pings`.
  - Added explicit guard error when opened over non-`file:` protocol (`Open this page with file://`).
  - Removed remote/codespaces endpoint auto-detection logic.

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
