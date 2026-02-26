Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function GetHosts {
  param([Parameter(Mandatory)][string]$Path)

  $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  $cfg = $raw | ConvertFrom-Json
  return @($cfg.hosts | ForEach-Object { [string]$_ })
}

function NewPingRecord {
  param([Parameter(Mandatory)][string]$Dest)

  return [pscustomobject]@{
    dest = $Dest
    rtt = $null
    status = "error"
    successedAt = $null
  }
}

function CopyPingRecord {
  param(
    [Parameter(Mandatory)]$Record
  )

  return [pscustomobject]@{
    dest = [string]$Record.dest
    rtt = $Record.rtt
    status = [string]$Record.status
    successedAt = $Record.successedAt
  }
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

function StartPingWorker {
  param(
    [Parameter(Mandatory)]$Shared,
    [Parameter(Mandatory)][bool]$LogSuccess
  )

  $pingLoop = {
    param($SharedState, [bool]$IncludeSuccessLog)

    Set-StrictMode -Version Latest
    $ErrorActionPreference = "Stop"

    while (-not $SharedState.Stop) {
      $tickStarted = [DateTimeOffset]::UtcNow

      foreach ($dest in $SharedState.Hosts) {
        if ($SharedState.Stop) { break }

        $started = [DateTimeOffset]::UtcNow
        $record = [pscustomobject]@{
          dest = $dest
          rtt = $null
          status = "error"
          successedAt = $null
        }
        $errorDetail = $null
        $ping = $null

        try {
          $ping = New-Object System.Net.NetworkInformation.Ping
          $reply = $ping.Send($dest, 2000)

          if ($null -ne $reply -and $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::Success) {
            $record.status = "success"
            $record.rtt = [int]$reply.RoundtripTime
            $record.successedAt = [DateTimeOffset]::UtcNow.ToString("o")
          } elseif ($null -ne $reply -and $reply.Status -eq [System.Net.NetworkInformation.IPStatus]::TimedOut) {
            $record.status = "timeout"
          } else {
            $record.status = "error"
            $errorDetail = "replyStatus=" + $(if ($null -eq $reply) { "null" } else { $reply.Status.ToString() })
          }
        } catch {
          $record.status = "error"
          $errorDetail = $_.Exception.GetType().FullName + ": " + $_.Exception.Message
        } finally {
          if ($null -ne $ping) { $ping.Dispose() }
        }

        $SharedState.Records[$dest] = $record

        $shouldLog = ($record.status -ne "success") -or $IncludeSuccessLog
        if ($shouldLog) {
          $rttStr = if ($null -eq $record.rtt) { "null" } else { [string]$record.rtt }
          $atStr = if ([string]::IsNullOrWhiteSpace([string]$record.successedAt)) { "null" } else { [string]$record.successedAt }
          $elapsedMs = [long]([DateTimeOffset]::UtcNow - $started).TotalMilliseconds
          $logLine = "{0:o} ping dest={1} status={2} rtt={3}ms successedAt={4} elapsedMs={5} error={6}" -f `
            $started, $dest, $record.status, $rttStr, $atStr, $elapsedMs, $(if ($null -eq $errorDetail) { "null" } else { $errorDetail })
          [Console]::WriteLine($logLine)
        }
      }

      $elapsedTickMs = [int]([DateTimeOffset]::UtcNow - $tickStarted).TotalMilliseconds
      $sleepMs = 1000 - $elapsedTickMs
      if ($sleepMs -lt 0) { $sleepMs = 0 }

      while ($sleepMs -gt 0 -and -not $SharedState.Stop) {
        $chunk = [Math]::Min($sleepMs, 500)
        Start-Sleep -Milliseconds $chunk
        $sleepMs -= $chunk
      }
    }
  }

  $workerRunspace = [RunspaceFactory]::CreateRunspace()
  $workerRunspace.ApartmentState = [System.Threading.ApartmentState]::MTA
  $workerRunspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
  $workerRunspace.Open()

  $workerPowerShell = [PowerShell]::Create()
  $workerPowerShell.Runspace = $workerRunspace
  $null = $workerPowerShell.AddScript($pingLoop.ToString()).AddArgument($Shared).AddArgument($LogSuccess)

  $workerHandle = $workerPowerShell.BeginInvoke()

  return [pscustomobject]@{
    Runspace = $workerRunspace
    PowerShell = $workerPowerShell
    Handle = $workerHandle
  }
}

function StopPingWorker {
  param($Worker, $Shared)

  if ($null -ne $Shared) {
    $Shared.Stop = $true
  }

  if ($null -eq $Worker) { return }

  $completed = $true
  try {
    if ($null -ne $Worker.Handle) {
      $completed = $Worker.Handle.IsCompleted
      if (-not $completed) {
        $completed = $Worker.Handle.AsyncWaitHandle.WaitOne(3000)
      }
    }
  } catch {
    $completed = $false
  }

  try {
    if ($null -ne $Worker.PowerShell) {
      if (-not $completed) {
        try { $Worker.PowerShell.Stop() } catch {}
      }
      if ($null -ne $Worker.Handle) {
        try { $null = $Worker.PowerShell.EndInvoke($Worker.Handle) } catch {}
      }
      $Worker.PowerShell.Dispose()
    }
  } finally {
    if ($null -ne $Worker.Runspace) {
      try { $Worker.Runspace.Close() } catch {}
      $Worker.Runspace.Dispose()
    }
  }
}

function Main {
  # Port 입력, e.g: 8080
  $Port = 8080
  # BindAddress 입력, e.g: localhost
  $Bind = "localhost"
  # 성공 로그 포함 여부 입력, e.g: $false (true=성공+실패, false=실패만)
  $LogSuccess = $true
  # ConfigPath 입력, e.g: (cwd)/config.json
  $CfgPath = (Join-Path (Get-Location).Path "config.json")

  $hosts = GetHosts -Path $CfgPath

  $records = [hashtable]::Synchronized(@{})
  foreach ($dest in $hosts) {
    $records[$dest] = NewPingRecord -Dest $dest
  }

  $shared = [hashtable]::Synchronized(@{
    Hosts = [string[]]$hosts
    Records = $records
    Stop = $false
  })

  $worker = StartPingWorker -Shared $shared -LogSuccess $LogSuccess

  $listener = [System.Net.HttpListener]::new()
  $prefix = "http://$Bind`:$Port/"
  $listener.Prefixes.Add($prefix)

  Write-Host "Server: $prefix"
  Write-Host "Config: $CfgPath"
  Write-Host ("Hosts: " + ($hosts -join ", "))

  try {
    try {
      $listener.Start()
    } catch {
      Write-Error ("Listen failed {0}: {1}" -f $prefix, $_.Exception.Message)
      Write-Error ("Another listener may already be running on {0}:{1}. Stop the old process or change the port." -f $Bind, $Port)
      throw
    }

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
        $arr = @()
        foreach ($dest in $hosts) {
          $rec = $shared.Records[$dest]
          if ($null -eq $rec) {
            $rec = NewPingRecord -Dest $dest
          }
          $arr += (CopyPingRecord -Record $rec)
        }

        SendJson -Context $ctx -BodyObj $arr -StatusCode 200
        continue
      }

      if ($path -eq "/ping") {
        $hostQ = $req.QueryString["host"]
        if (-not ($hosts -contains $hostQ)) {
          SendEmpty -Context $ctx -StatusCode 404
          continue
        }

        $rec = $shared.Records[$hostQ]
        if ($null -eq $rec) {
          SendEmpty -Context $ctx -StatusCode 404
          continue
        }

        SendJson -Context $ctx -BodyObj (CopyPingRecord -Record $rec) -StatusCode 200
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
    if ($null -ne $listener) {
      try { $listener.Stop() } catch {}
      try { $listener.Close() } catch {}
    }

    StopPingWorker -Worker $worker -Shared $shared
  }
}

Main
