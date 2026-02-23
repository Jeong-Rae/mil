Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function GetHosts {
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

function SendJson {
  param(
    [Parameter(Mandatory)]$Context,
    [Parameter(Mandatory)]$BodyObj,
    [int]$StatusCode = 200
  )

  $json = $BodyObj | ConvertTo-Json -Depth 6
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)

  $res = $Context.Response
  $res.StatusCode = $StatusCode
  $res.ContentType = "application/json; charset=utf-8"
  $res.ContentLength64 = $bytes.Length
  $res.Headers["Access-Control-Allow-Origin"] = "*"
  $res.Headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
  $res.Headers["Access-Control-Allow-Headers"] = "Content-Type"
  $res.OutputStream.Write($bytes, 0, $bytes.Length)
  $res.OutputStream.Close()
}

function SendEmpty {
  param(
    [Parameter(Mandatory)]$Context,
    [int]$StatusCode = 204
  )

  $res = $Context.Response
  $res.StatusCode = $StatusCode
  $res.Headers["Access-Control-Allow-Origin"] = "*"
  $res.Headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
  $res.Headers["Access-Control-Allow-Headers"] = "Content-Type"
  $res.OutputStream.Close()
}

function Main {
  param([string[]]$Argv)

  if ($null -eq $Argv) { $Argv = @() }

  $Port = 8080
  $Bind = "localhost"
  $NoPingLog = $false
  $base = if ($PSScriptRoot -and (Test-Path -LiteralPath $PSScriptRoot)) { $PSScriptRoot } else { (Get-Location).Path }
  $CfgPath = (Join-Path $base "config.json")

  for ($i = 0; $i -lt $Argv.Count; $i++) {
    $a = [string]$Argv[$i]
    switch ($a) {
      "-Port" {
        if ($i + 1 -ge $Argv.Count) { throw "Missing value for -Port" }
        $Port = [int]$Argv[$i + 1]
        $i++
        continue
      }
      "-BindAddress" {
        if ($i + 1 -ge $Argv.Count) { throw "Missing value for -BindAddress" }
        $Bind = [string]$Argv[$i + 1]
        $i++
        continue
      }
      "-ConfigPath" {
        if ($i + 1 -ge $Argv.Count) { throw "Missing value for -ConfigPath" }
        $CfgPath = [string]$Argv[$i + 1]
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

  $hosts = GetHosts -Path $CfgPath
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
    public string status { get; set; }
    public string successedAt { get; set; }
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
        _timer = new Timer(Tick, null, 0, _intervalMs);
    }

    private void Tick(object state)
    {
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
                Task.WaitAll(tasks.ToArray(), 9000);
            }
            catch
            {
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
  $prefix = "http://$Bind`:$Port/"
  $listener.Prefixes.Add($prefix)

  Write-Host "Server: $prefix"
  Write-Host "Config: $CfgPath"
  Write-Host ("Hosts: " + ($hosts -join ", "))

  try {
    $listener.Start()
  } catch {
    Write-Error ("Listen failed {0}: {1}" -f $prefix, $_.Exception.Message)
    throw
  }

  try {
    while ($listener.IsListening) {
      $ctx = $listener.GetContext()
      $req = $ctx.Request

      if ($req.HttpMethod -eq "OPTIONS") {
        SendEmpty -Context $ctx -StatusCode 200
        continue
      }

      if ($req.HttpMethod -ne "GET") {
        SendEmpty -Context $ctx -StatusCode 405
        continue
      }

      $path = $req.Url.AbsolutePath

      if ($path -eq "/pings") {
        $arr = $scheduler.GetAllInConfigOrder()
        SendJson -Context $ctx -BodyObj $arr -StatusCode 200
        continue
      }

      if ($path -eq "/ping") {
        $hostQ = $req.QueryString["host"]
        if ([string]::IsNullOrWhiteSpace($hostQ)) {
          SendEmpty -Context $ctx -StatusCode 400
          continue
        }

        if (-not ($hosts -contains $hostQ)) {
          SendEmpty -Context $ctx -StatusCode 404
          continue
        }

        $rec = $scheduler.GetRecord($hostQ)
        if ($null -eq $rec) {
          SendEmpty -Context $ctx -StatusCode 404
          continue
        }

        SendJson -Context $ctx -BodyObj $rec -StatusCode 200
        continue
      }

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
}

Main -Argv $args
