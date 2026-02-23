<#
Paste-friendly server script.

Usage examples:
- Paste the whole file into an interactive `pwsh` session (it will start immediately with defaults).
- Run as a file: `pwsh -File ./server.ps1 -Port 8080`

Supported args (all optional):
-Port <int>
-BindAddress <string>   # default: 127.0.0.1
-ConfigPath <string>    # default: <script dir>/config.json (or <cwd>/config.json when pasted)
-NoPingLog              # disables per-ping console logs
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($null -eq $args) { $args = @() }

$Port = 8080
$BindAddress = "127.0.0.1"
$NoPingLog = $false

$baseDir = if ($PSScriptRoot -and (Test-Path -LiteralPath $PSScriptRoot)) { $PSScriptRoot } else { (Get-Location).Path }

$ConfigPath = (Join-Path $baseDir "config.json")

for ($i = 0; $i -lt $args.Count; $i++) {
  $a = [string]$args[$i]
  switch ($a) {
    "-Port" {
      if ($i + 1 -ge $args.Count) { throw "Missing value for -Port" }
      $Port = [int]$args[$i + 1]
      $i++
      continue
    }
    "-BindAddress" {
      if ($i + 1 -ge $args.Count) { throw "Missing value for -BindAddress" }
      $BindAddress = [string]$args[$i + 1]
      $i++
      continue
    }
    "-ConfigPath" {
      if ($i + 1 -ge $args.Count) { throw "Missing value for -ConfigPath" }
      $ConfigPath = [string]$args[$i + 1]
      $i++
      continue
    }
    "-NoPingLog" {
      $NoPingLog = $true
      continue
    }
    default { }
  }
}

function Get-ConfigHosts {
  param([Parameter(Mandatory)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    throw "config.json not found: $Path"
  }

  $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  $cfg = $raw | ConvertFrom-Json
  if ($null -eq $cfg -or $null -eq $cfg.hosts) {
    throw "Invalid config.json (missing 'hosts' array)"
  }
  $hosts = @($cfg.hosts | ForEach-Object { [string]$_ })
  if ($hosts.Count -eq 0) {
    throw "Invalid config.json ('hosts' must be a non-empty array)"
  }
  return $hosts
}

function Write-JsonResponse {
  param(
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$BodyObj,
    [int]$StatusCode = 200
  )

  # -Compress is not available in all PowerShell editions.
  $json = $BodyObj | ConvertTo-Json -Depth 6
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

  $res = $Context.Response
  $res.StatusCode = $StatusCode
  $res.ContentType = "application/json; charset=utf-8"
  $res.ContentLength64 = $bytes.Length

  # CORS (for file://)
  $res.Headers["Access-Control-Allow-Origin"] = "*"
  $res.Headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
  $res.Headers["Access-Control-Allow-Headers"] = "Content-Type"

  $res.OutputStream.Write($bytes, 0, $bytes.Length)
  $res.OutputStream.Close()
}

function Write-EmptyResponse {
  param(
    [Parameter(Mandatory)]$Context,
    [int]$StatusCode = 204
  )

  $res = $Context.Response
  $res.StatusCode = $StatusCode

  # CORS (for file://)
  $res.Headers["Access-Control-Allow-Origin"] = "*"
  $res.Headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
  $res.Headers["Access-Control-Allow-Headers"] = "Content-Type"

  $res.OutputStream.Close()
}

$hosts = Get-ConfigHosts -Path $ConfigPath

<#
Why we don't use System.Threading.Timer with ScriptBlocks:
- In PowerShell 7 (pwsh), Timer callbacks run on ThreadPool threads that do not have a PowerShell runspace.
- Executing a ScriptBlock there commonly crashes with:
  "There is no Runspace available to run scripts in this thread."
To stay cross-platform and stable, run the scheduler logic in pure .NET (no ScriptBlock callbacks).
#>
if (-not ("PingScheduler" -as [type])) {
  Add-Type -Language CSharp -TypeDefinition @"
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Net.NetworkInformation;
using System.Threading;
using System.Threading.Tasks;

public sealed class PingRecord
{
    public string dest { get; set; }
    public int? rtt { get; set; }
    public string status { get; set; } // success | timeout | error
    public string successedAt { get; set; } // ISO8601 or null
}

public sealed class PingScheduler : IDisposable
{
    private readonly List<string> _hosts;
    private readonly ConcurrentDictionary<string, PingRecord> _records;
    private readonly int _timeoutMs;
    private readonly int _intervalMs;
    private readonly bool _log;
    private int _inTick;
    private Timer _timer;

    public PingScheduler(IEnumerable<string> hosts, int timeoutMs, int intervalMs, bool log)
    {
        _hosts = hosts.Select(h => h ?? "").ToList();
        _timeoutMs = timeoutMs;
        _intervalMs = intervalMs;
        _log = log;
        _records = new ConcurrentDictionary<string, PingRecord>();
        foreach (var h in _hosts)
        {
            _records[h] = NewDefault(h);
        }
    }

    public IReadOnlyList<string> Hosts => _hosts;

    public PingRecord GetRecord(string host)
    {
        if (host == null) return null;
        PingRecord rec;
        return _records.TryGetValue(host, out rec) ? rec : null;
    }

    public PingRecord[] GetAllInConfigOrder()
    {
        var arr = new PingRecord[_hosts.Count];
        for (int i = 0; i < _hosts.Count; i++)
        {
            arr[i] = GetRecord(_hosts[i]) ?? NewDefault(_hosts[i]);
        }
        return arr;
    }

    public void Start()
    {
        if (_timer != null) return;
        // Fire immediately, then every interval.
        _timer = new Timer(Tick, null, 0, _intervalMs);
    }

    private void Tick(object state)
    {
        // Avoid overlapping ticks.
        if (Interlocked.Exchange(ref _inTick, 1) == 1) return;
        try
        {
            try
            {
                var tasks = new List<Task>(_hosts.Count);
                foreach (var h in _hosts)
                {
                    var hostCopy = h;
                    tasks.Add(Task.Run(() => PingOne(hostCopy)));
                }
                // Keep the tick bounded (interval is 10s by spec).
                Task.WaitAll(tasks.ToArray(), 9000);
            }
            catch
            {
                // Ignore scheduler-level errors.
            }
        }
        finally
        {
            Interlocked.Exchange(ref _inTick, 0);
        }
    }

    private void PingOne(string host)
    {
        var started = DateTimeOffset.UtcNow;
        var rec = NewDefault(host);
        string errDetail = null;
        Ping p = null;
        try
        {
            p = new Ping();
            var reply = p.Send(host, _timeoutMs);
            if (reply != null && reply.Status == IPStatus.Success)
            {
                rec.status = "success";
                rec.rtt = (int)reply.RoundtripTime;
                rec.successedAt = DateTimeOffset.UtcNow.ToString("o");
            }
            else if (reply != null && reply.Status == IPStatus.TimedOut)
            {
                rec.status = "timeout";
            }
            else
            {
                rec.status = "error";
                errDetail = "replyStatus=" + (reply == null ? "null" : reply.Status.ToString());
            }
        }
        catch (Exception ex)
        {
            rec.status = "error";
            errDetail = ex.GetType().FullName + ": " + ex.Message;
        }
        finally
        {
            if (p != null) p.Dispose();
        }

        _records[host] = rec;

        if (_log)
        {
            var rttStr = rec.rtt.HasValue ? rec.rtt.Value.ToString() : "null";
            var atStr = rec.successedAt ?? "null";
            var elapsedMs = (long)(DateTimeOffset.UtcNow - started).TotalMilliseconds;
            Console.WriteLine(string.Format(
                "{0:o} ping dest={1} status={2} rtt={3}ms successedAt={4} elapsedMs={5} error={6}",
                started, host, rec.status, rttStr, atStr, elapsedMs, errDetail ?? "null"));
        }
    }

    private static PingRecord NewDefault(string host)
    {
        return new PingRecord
        {
            dest = host,
            rtt = null,
            status = "error",
            successedAt = null
        };
    }

    public void Stop()
    {
        var t = _timer;
        _timer = null;
        if (t == null) return;
        try { t.Dispose(); } catch { }
    }

    public void Dispose()
    {
        Stop();
    }
}
"@
}

$logEnabled = (-not $NoPingLog)
$scheduler = [PingScheduler]::new([string[]]$hosts, 2000, 10000, [bool]$logEnabled)
$scheduler.Start()

$listener = [System.Net.HttpListener]::new()
$prefix = "http://$BindAddress`:$Port/"
$listener.Prefixes.Add($prefix)

Write-Host "Ping Monitor server listening on $prefix"
Write-Host "Config: $ConfigPath"
Write-Host ("Hosts: " + ($hosts -join ", "))

try {
  $listener.Start()
} catch {
  Write-Error ("Failed to start HttpListener for {0}: {1} (On Windows you may need admin or a URL ACL reservation; on some Linux/containers binding can be blocked.)" -f $prefix, $_.Exception.Message)
  throw
}

try {
  while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request

    # Always add CORS headers even for error paths.
    if ($req.HttpMethod -eq "OPTIONS") {
      Write-EmptyResponse -Context $ctx -StatusCode 200
      continue
    }

    if ($req.HttpMethod -ne "GET") {
      Write-EmptyResponse -Context $ctx -StatusCode 405
      continue
    }

    $path = $req.Url.AbsolutePath

    if ($path -eq "/pings") {
      $arr = $scheduler.GetAllInConfigOrder()
      Write-JsonResponse -Context $ctx -BodyObj $arr -StatusCode 200
      continue
    }

    if ($path -eq "/ping") {
      $hostQ = $req.QueryString["host"]
      if ([string]::IsNullOrWhiteSpace($hostQ)) {
        Write-EmptyResponse -Context $ctx -StatusCode 400
        continue
      }

      if (-not ($hosts -contains $hostQ)) {
        Write-EmptyResponse -Context $ctx -StatusCode 404
        continue
      }

      $rec = $scheduler.GetRecord($hostQ)

      if ($null -eq $rec) {
        Write-EmptyResponse -Context $ctx -StatusCode 404
        continue
      }

      Write-JsonResponse -Context $ctx -BodyObj $rec -StatusCode 200
      continue
    }

    # Optional: simple health page.
    $ctx.Response.StatusCode = 200
    $ctx.Response.ContentType = "text/plain; charset=utf-8"
    $ctx.Response.Headers["Access-Control-Allow-Origin"] = "*"
    $ctx.Response.Headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
    $ctx.Response.Headers["Access-Control-Allow-Headers"] = "Content-Type"
    $msg = [System.Text.Encoding]::UTF8.GetBytes("OK`nTry GET /pings")
    $ctx.Response.OutputStream.Write($msg, 0, $msg.Length)
    $ctx.Response.OutputStream.Close()
  }
} finally {
  if ($null -ne $scheduler) { $scheduler.Dispose() }
  if ($null -ne $listener) {
    try { $listener.Stop() } catch {}
    try { $listener.Close() } catch {}
  }
}
