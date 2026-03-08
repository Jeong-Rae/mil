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
        [string]$ClientId,
        [Parameter(Mandatory = $true)]
        [string]$InboundJson,
        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    if (-not $State.Clients.ContainsKey($ClientId)) {
        return
    }

    $message = $InboundJson | ConvertFrom-Json
    $message | Add-Member -NotePropertyName name -NotePropertyValue $State.Clients[$ClientId].Name -Force
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

            Broadcast-Json -ClientId $ClientId -InboundJson $text -State $SharedState
        }
    }
    finally {
        Remove-SharedClient -Id $ClientId -State $SharedState
    }
}
