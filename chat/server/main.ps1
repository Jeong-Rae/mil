function Remove-CompletedWorkers {
    param(
        [System.Collections.ArrayList]$Workers
    )

    if ($null -eq $Workers -or $Workers.Count -eq 0) {
        return
    }

    $completed = @()

    foreach ($worker in $Workers) {
        if (-not $worker.AsyncResult.IsCompleted) {
            continue
        }

        try {
            $worker.PowerShell.EndInvoke($worker.AsyncResult) | Out-Null
        }
        catch {
            Write-Warning "Client worker ended with an error: $($_.Exception.Message)"
        }
        finally {
            $worker.PowerShell.Dispose()
            $completed += $worker
        }
    }

    foreach ($worker in $completed) {
        [void]$Workers.Remove($worker)
    }
}

function Get-ClientName {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerRequest]$Request
    )

    if ($null -eq $Request.RemoteEndPoint) {
        return "unknown"
    }

    $address = $Request.RemoteEndPoint.Address.ToString()
    $parts = $address.Split(".")

    if ($parts.Count -ge 4) {
        return "$($parts[2]).$($parts[3])"
    }

    return $address
}

function Get-WorkerScript {
    $functionNames = @(
        "Stop-ClientSocket",
        "Remove-SharedClient",
        "Read-WebSocketText",
        "Broadcast-Json",
        "Start-ClientReceiveLoop"
    )

    $definitions = foreach ($name in $functionNames) {
        $functionInfo = Get-Item -Path "Function:$name" -ErrorAction Stop
        $functionInfo.ScriptBlock.ToString()
    }

    return (($definitions -join "`n`n") + "`n`nStart-ClientReceiveLoop -ClientId `$args[0] -Socket `$args[1] -SharedState `$args[2]")
}

function Start-ChatServer {
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($StaticPrefix)
    $listener.Prefixes.Add($ListenerPrefix)

    $state = [hashtable]::Synchronized(@{
        Clients = [hashtable]::Synchronized(@{})
    })

    $pool = [runspacefactory]::CreateRunspacePool(1, $RunspaceMax)
    $pool.ApartmentState = "MTA"
    $pool.Open()

    $workers = [System.Collections.ArrayList]::new()
    $workerScript = Get-WorkerScript

    Write-Host "Simple LAN Chat server starting..."
    Write-Host "Static prefix: $StaticPrefix"
    Write-Host "WebSocket prefix: $ListenerPrefix"
    Write-Host "Connect from clients with: $ClientConnectUrl"
    Write-Host "Press Ctrl+C to stop."

    try {
        $listener.Start()

        while ($listener.IsListening) {
            Remove-CompletedWorkers -Workers $workers

            try {
                $context = $listener.GetContext()
            }
            catch [System.Net.HttpListenerException] {
                break
            }
            catch [System.ObjectDisposedException] {
                break
            }

            if (-not $context.Request.IsWebSocketRequest) {
                Write-StaticResponse -Context $context
                continue
            }

            if ($context.Request.Url.AbsolutePath -ne "/api/") {
                $context.Response.StatusCode = 404
                $context.Response.Close()
                continue
            }

            try {
                $webSocketContext = $context.AcceptWebSocketAsync($null).GetAwaiter().GetResult()
            }
            catch {
                $context.Response.StatusCode = 500
                $context.Response.Close()
                continue
            }

            $clientId = [guid]::NewGuid().ToString("N")
            $clientName = Get-ClientName -Request $context.Request
            $socket = $webSocketContext.WebSocket
            $state.Clients[$clientId] = @{
                Name = $clientName
                Socket = $socket
                SendLock = New-Object object
            }

            $workerPowerShell = [powershell]::Create()
            $workerPowerShell.RunspacePool = $pool
            [void]$workerPowerShell.AddScript($workerScript).AddArgument($clientId).AddArgument($socket).AddArgument($state)

            $worker = [pscustomobject]@{
                ClientId = $clientId
                PowerShell = $workerPowerShell
                AsyncResult = $workerPowerShell.BeginInvoke()
            }

            [void]$workers.Add($worker)
            Write-Host "Client connected: $clientName ($clientId)"
        }
    }
    finally {
        foreach ($clientEntry in @($state.Clients.GetEnumerator())) {
            Stop-ClientSocket -Client $clientEntry.Value
        }

        $state.Clients.Clear()
        Remove-CompletedWorkers -Workers $workers

        foreach ($worker in @($workers)) {
            try {
                $worker.PowerShell.Stop()
            }
            catch {
            }
            finally {
                $worker.PowerShell.Dispose()
            }
        }

        if ($listener.IsListening) {
            $listener.Stop()
        }

        $listener.Close()
        $pool.Close()
        $pool.Dispose()
    }
}

function Main {
    Start-ChatServer
}
