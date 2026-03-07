$ErrorActionPreference = "Stop"

# Edit these constants directly before running on your LAN.
$Port = 9999
$BindAddress = "localhost"
$ListenerPrefix = "http://${BindAddress}:$Port/"
$RunspaceMax = 16

function Write-PlainTextResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory = $true)]
        [string]$Body
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
    $Response.StatusCode = 200
    $Response.ContentType = "text/plain; charset=utf-8"
    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.OutputStream.Close()
}

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

function Stop-ClientSocket {
    param(
        [Parameter(Mandatory = $true)]
        $Client
    )

    if ($null -eq $Client -or $null -eq $Client.Socket) {
        return
    }

    try {
        if ($Client.Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open -or
            $Client.Socket.State -eq [System.Net.WebSockets.WebSocketState]::CloseReceived) {
            $closeTask = $Client.Socket.CloseAsync(
                [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                "bye",
                [System.Threading.CancellationToken]::None
            )
            $closeTask.GetAwaiter().GetResult()
        }
    }
    catch {
        try {
            $Client.Socket.Abort()
        }
        catch {
        }
    }
    finally {
        $Client.Socket.Dispose()
    }
}

function Remove-SharedClient {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    $client = $null

    if ($State.Clients.ContainsKey($Id)) {
        $client = $State.Clients[$Id]
        $State.Clients.Remove($Id)
    }

    if ($null -eq $client) {
        return
    }

    Stop-ClientSocket -Client $client
}

function Read-WebSocketText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.WebSockets.WebSocket]$Socket
    )

    $buffer = New-Object byte[] 4096
    $segment = [System.ArraySegment[byte]]::new($buffer)
    $stream = [System.IO.MemoryStream]::new()

    try {
        while ($true) {
            $result = $Socket.ReceiveAsync(
                $segment,
                [System.Threading.CancellationToken]::None
            ).GetAwaiter().GetResult()

            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                return $null
            }

            if ($result.MessageType -ne [System.Net.WebSockets.WebSocketMessageType]::Text) {
                continue
            }

            $stream.Write($buffer, 0, $result.Count)

            if ($result.EndOfMessage) {
                break
            }
        }

        return [System.Text.Encoding]::UTF8.GetString($stream.ToArray())
    }
    finally {
        $stream.Dispose()
    }
}

function Broadcast-Json {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InboundJson,
        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    $message = $InboundJson | ConvertFrom-Json
    $message | Add-Member -NotePropertyName sentAt -NotePropertyValue ([DateTime]::UtcNow.ToString("o")) -Force
    $outboundJson = $message | ConvertTo-Json -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($outboundJson)
    $segment = [System.ArraySegment[byte]]::new($bytes)

    foreach ($entry in @($State.Clients.GetEnumerator())) {
        $target = $entry.Value
        $lockTaken = $false

        try {
            [System.Threading.Monitor]::Enter($target.SendLock, [ref]$lockTaken)

            if ($target.Socket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
                throw "socket is not open"
            }

            $target.Socket.SendAsync(
                $segment,
                [System.Net.WebSockets.WebSocketMessageType]::Text,
                $true,
                [System.Threading.CancellationToken]::None
            ).GetAwaiter().GetResult()
        }
        catch {
            Remove-SharedClient -Id $entry.Key -State $State
        }
        finally {
            if ($lockTaken) {
                [System.Threading.Monitor]::Exit($target.SendLock)
            }
        }
    }
}

function Start-ClientReceiveLoop {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ClientId,
        [Parameter(Mandatory = $true)]
        [System.Net.WebSockets.WebSocket]$Socket,
        [Parameter(Mandatory = $true)]
        [hashtable]$SharedState
    )

    try {
        while ($Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open -or
               $Socket.State -eq [System.Net.WebSockets.WebSocketState]::CloseReceived) {
            $text = Read-WebSocketText -Socket $Socket

            if ($null -eq $text) {
                break
            }

            Broadcast-Json -InboundJson $text -State $SharedState
        }
    }
    finally {
        Remove-SharedClient -Id $ClientId -State $SharedState
    }
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
    Write-Host "Listener prefix: $ListenerPrefix"
    Write-Host "Connect from clients with: ws://${BindAddress}:$Port/"
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
                Write-PlainTextResponse -Response $context.Response -Body "Simple LAN Chat WebSocket server."
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
            $socket = $webSocketContext.WebSocket
            $state.Clients[$clientId] = @{
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
            Write-Host "Client connected: $clientId"
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
    if ($BindAddress -eq "SERVER_IP") {
        throw "Set `$BindAddress in server.ps1 to the actual LAN IP before running."
    }

    Start-ChatServer
}

Main
