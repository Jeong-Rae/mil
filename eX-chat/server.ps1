function Get-ContentType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
        ".html" { return "text/html; charset=utf-8" }
        ".js" { return "application/javascript; charset=utf-8" }
        ".css" { return "text/css; charset=utf-8" }
        default { return "application/octet-stream" }
    }
}

function Send-BytesResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes,

        [Parameter(Mandatory = $true)]
        [string]$ContentType,

        [int]$StatusCode = 200
    )

    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.ContentLength64 = $Bytes.Length
    $Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
    $Response.OutputStream.Close()
}

function Send-TextResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [string]$ContentType = "text/plain; charset=utf-8",

        [int]$StatusCode = 200
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    Send-BytesResponse -Response $Response -Bytes $bytes -ContentType $ContentType -StatusCode $StatusCode
}

function Get-ClientLabel {
    param(
        [System.Net.IPAddress]$Address
    )

    if ($null -eq $Address) {
        return "unknown"
    }

    if ($Address.IsIPv4MappedToIPv6) {
        $Address = $Address.MapToIPv4()
    }

    if ($Address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return "ipv6"
    }

    $parts = $Address.ToString().Split(".")
    if ($parts.Length -lt 4) {
        return $Address.ToString()
    }

    return "{0}.{1}" -f $parts[2], $parts[3]
}

function New-JsonBytes {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Payload
    )

    return [System.Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Compress -Depth 4))
}

function Broadcast-Bytes {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$State,

        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $clients = @($State.Clients.ToArray())

    foreach ($client in $clients) {
        $socket = $client.Socket
        $gate = $client.SendGate

        if ($null -eq $socket -or $socket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
            [void]$State.Clients.Remove($client)
            continue
        }

        try {
            $null = $gate.Wait()
            $segment = [System.ArraySegment[byte]]::new($Bytes, 0, $Bytes.Length)
            $socket.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
        } catch {
            try {
                if ($socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                    $socket.CloseAsync(
                        [System.Net.WebSockets.WebSocketCloseStatus]::InternalServerError,
                        "send failed",
                        [Threading.CancellationToken]::None
                    ).GetAwaiter().GetResult()
                }
            } catch {
            }
            [void]$State.Clients.Remove($client)
        } finally {
            if ($gate.CurrentCount -eq 0) {
                $null = $gate.Release()
            }
        }
    }
}

function Broadcast-Json {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$State,

        [Parameter(Mandatory = $true)]
        [object]$Payload
    )

    $bytes = New-JsonBytes -Payload $Payload
    Broadcast-Bytes -State $State -Bytes $bytes
}

function Start-ClientHandler {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.WebSockets.WebSocket]$Socket,

        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$State,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool
    )

    $handler = {
        param($Socket, $Label, $State)

        function Send-BroadcastFromHandler {
            param([object]$Payload)

            $bytes = [System.Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Compress -Depth 4))
            $clients = @($State.Clients.ToArray())

            foreach ($client in $clients) {
                $clientSocket = $client.Socket
                $gate = $client.SendGate

                if ($null -eq $clientSocket -or $clientSocket.State -ne [System.Net.WebSockets.WebSocketState]::Open) {
                    [void]$State.Clients.Remove($client)
                    continue
                }

                try {
                    $null = $gate.Wait()
                    $segment = [System.ArraySegment[byte]]::new($bytes, 0, $bytes.Length)
                    $clientSocket.SendAsync(
                        $segment,
                        [System.Net.WebSockets.WebSocketMessageType]::Text,
                        $true,
                        [Threading.CancellationToken]::None
                    ).GetAwaiter().GetResult()
                } catch {
                    try {
                        if ($clientSocket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                            $clientSocket.CloseAsync(
                                [System.Net.WebSockets.WebSocketCloseStatus]::InternalServerError,
                                "send failed",
                                [Threading.CancellationToken]::None
                            ).GetAwaiter().GetResult()
                        }
                    } catch {
                    }
                    [void]$State.Clients.Remove($client)
                } finally {
                    if ($gate.CurrentCount -eq 0) {
                        $null = $gate.Release()
                    }
                }
            }
        }

        $buffer = New-Object byte[] 4096
        $builder = New-Object System.Text.StringBuilder

        try {
            while ($Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                $segment = [System.ArraySegment[byte]]::new($buffer, 0, $buffer.Length)
                $result = $Socket.ReceiveAsync($segment, [Threading.CancellationToken]::None).GetAwaiter().GetResult()

                if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                    break
                }

                if ($result.Count -gt 0) {
                    $null = $builder.Append([System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count))
                }

                if (-not $result.EndOfMessage) {
                    continue
                }

                if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Text) {
                    $text = $builder.ToString()
                    $builder.Clear() | Out-Null

                    Send-BroadcastFromHandler -Payload @{
                        type = "chat"
                        sender = $Label
                        text = $text
                    }
                } else {
                    $builder.Clear() | Out-Null
                }
            }
        } catch {
        } finally {
            $client = $null
            foreach ($item in @($State.Clients.ToArray())) {
                if ([object]::ReferenceEquals($item.Socket, $Socket)) {
                    $client = $item
                    break
                }
            }

            if ($null -ne $client) {
                [void]$State.Clients.Remove($client)
            }

            try {
                if ($Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open -or $Socket.State -eq [System.Net.WebSockets.WebSocketState]::CloseReceived) {
                    $Socket.CloseAsync(
                        [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                        "bye",
                        [Threading.CancellationToken]::None
                    ).GetAwaiter().GetResult()
                }
            } catch {
            }

            Send-BroadcastFromHandler -Payload @{
                type = "system"
                text = "$Label left"
            }

            $Socket.Dispose()
        }
    }

    $ps = [powershell]::Create()
    $ps.RunspacePool = $RunspacePool
    $null = $ps.AddScript($handler).AddArgument($Socket).AddArgument($Label).AddArgument($State)
    $handle = $ps.BeginInvoke()

    return [pscustomobject]@{
        PowerShell = $ps
        Handle = $handle
    }
}

function Start-EXChat {
    param(
        [int]$Port = 8888,
        [string]$BindAddress = "+",
        [string]$AppRoot = $PSScriptRoot
    )

    if ([string]::IsNullOrWhiteSpace($AppRoot)) {
        $AppRoot = (Get-Location).Path
    }

    $prefix = "http://{0}:{1}/" -f $BindAddress, $Port
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($prefix)

    $state = [hashtable]::Synchronized(@{
        Clients = [System.Collections.ArrayList]::Synchronized((New-Object System.Collections.ArrayList))
    })

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, 16)
    $runspacePool.Open()
    $handlers = New-Object System.Collections.ArrayList

    try {
        $listener.Start()
        Write-Host ("eX-chat listening on {0}" -f $prefix)

        while ($listener.IsListening) {
            $context = $listener.GetContext()
            $path = $context.Request.Url.AbsolutePath

            if ($path -eq "/ws") {
                if (-not $context.Request.IsWebSocketRequest) {
                    Send-TextResponse -Response $context.Response -Text "WebSocket required" -StatusCode 400
                    continue
                }

                try {
                    $wsContext = $context.AcceptWebSocketAsync($null).GetAwaiter().GetResult()
                    $socket = $wsContext.WebSocket
                    $label = Get-ClientLabel -Address $context.Request.RemoteEndPoint.Address

                    $client = [hashtable]::Synchronized(@{
                        Socket = $socket
                        Label = $label
                        SendGate = [System.Threading.SemaphoreSlim]::new(1, 1)
                    })
                    [void]$state.Clients.Add($client)

                    Broadcast-Json -State $state -Payload @{
                        type = "system"
                        text = "$label joined"
                    }

                    [void]$handlers.Add((Start-ClientHandler -Socket $socket -Label $label -State $state -RunspacePool $runspacePool))
                } catch {
                    if ($context.Response.OutputStream.CanWrite) {
                        Send-TextResponse -Response $context.Response -Text "WebSocket accept failed" -StatusCode 500
                    }
                }

                continue
            }

            $relativePath = switch ($path) {
                "/" { "index.html" }
                "/index.html" { "index.html" }
                "/script.js" { "script.js" }
                "/style.css" { "style.css" }
                default { $null }
            }

            if ($null -eq $relativePath) {
                Send-TextResponse -Response $context.Response -Text "Not Found" -StatusCode 404
                continue
            }

            $filePath = Join-Path $AppRoot $relativePath
            if (-not (Test-Path -LiteralPath $filePath)) {
                Send-TextResponse -Response $context.Response -Text "Missing file" -StatusCode 500
                continue
            }

            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            $contentType = Get-ContentType -Path $filePath
            Send-BytesResponse -Response $context.Response -Bytes $bytes -ContentType $contentType
        }
    } finally {
        foreach ($handler in @($handlers)) {
            try {
                $handler.PowerShell.Stop()
            } catch {
            }

            try {
                $handler.PowerShell.Dispose()
            } catch {
            }
        }

        foreach ($client in @($state.Clients.ToArray())) {
            try {
                if ($client.Socket.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
                    $client.Socket.CloseAsync(
                        [System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,
                        "shutdown",
                        [Threading.CancellationToken]::None
                    ).GetAwaiter().GetResult()
                }
            } catch {
            }

            try {
                $client.Socket.Dispose()
            } catch {
            }
        }

        if ($listener.IsListening) {
            $listener.Stop()
        }

        $listener.Close()
        $runspacePool.Close()
        $runspacePool.Dispose()
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    Start-EXChat
}
