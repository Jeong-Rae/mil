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

function Send-JsonResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory = $true)]
        [object]$Payload,

        [switch]$AsArray,

        [int]$StatusCode = 200
    )

    $json = if ($AsArray) {
        $Payload | ConvertTo-Json -Compress -Depth 6 -AsArray
    } else {
        $Payload | ConvertTo-Json -Compress -Depth 6
    }
    Send-TextResponse -Response $Response -Text $json -ContentType "application/json; charset=utf-8" -StatusCode $StatusCode
}

function Get-ClientLabel {
    param(
        [System.Net.IPAddress]$Address
    )

    if ($null -eq $Address) {
        return "unknown"
    }

    $parts = $Address.ToString().Split(".")
    if ($parts.Length -lt 4) {
        return "unknown"
    }

    return "{0}.{1}" -f $parts[2], $parts[3]
}

function Get-RequestBodyText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerRequest]$Request
    )

    $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
    try {
        return $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
    }
}

function Get-LatestMessageId {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$State
    )

    [System.Threading.Monitor]::Enter($State.Lock)
    try {
        if ($State.Messages.Count -eq 0) {
            return 0
        }

        return [int]$State.Messages[$State.Messages.Count - 1].id
    } finally {
        [System.Threading.Monitor]::Exit($State.Lock)
    }
}

function Get-MessagesAfter {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$State,

        [int]$AfterId
    )

    [System.Threading.Monitor]::Enter($State.Lock)
    try {
        return @($State.Messages | Where-Object { $_.id -gt $AfterId })
    } finally {
        [System.Threading.Monitor]::Exit($State.Lock)
    }
}

function Add-ChatMessage {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$State,

        [Parameter(Mandatory = $true)]
        [string]$Sender,

        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    [System.Threading.Monitor]::Enter($State.Lock)
    try {
        $message = [pscustomobject]@{
            id = [int]$State.NextId
            sender = $Sender
            text = $Text
            createdAt = [DateTime]::UtcNow.ToString("o")
        }

        $State.NextId = [int]$State.NextId + 1
        [void]$State.Messages.Add($message)

        while ($State.Messages.Count -gt 200) {
            $State.Messages.RemoveAt(0)
        }

        return $message
    } finally {
        [System.Threading.Monitor]::Exit($State.Lock)
    }
}

function Wait-ForMessagesAfter {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$State,

        [int]$AfterId
    )

    $deadline = [DateTime]::UtcNow.AddSeconds(15)

    while ([DateTime]::UtcNow -lt $deadline) {
        $messages = Get-MessagesAfter -State $State -AfterId $AfterId
        if ($messages.Count -gt 0) {
            return $messages
        }

        Start-Sleep -Milliseconds 250
    }

    return @()
}

function Try-ParseAfterId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawValue
    )

    $parsed = 0
    $ok = [int]::TryParse($RawValue, [ref]$parsed)

    return [pscustomobject]@{
        ok = $ok
        value = $parsed
    }
}

function Cleanup-RequestHandlers {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.AllowEmptyCollection()]
        [System.Collections.ArrayList]$Handlers
    )

    foreach ($entry in @($Handlers.ToArray())) {
        if (-not $entry.Handle.IsCompleted) {
            continue
        }

        try {
            $entry.PowerShell.EndInvoke($entry.Handle) | Out-Null
        } catch {
        }

        try {
            $entry.PowerShell.Dispose()
        } catch {
        }

        [void]$Handlers.Remove($entry)
    }
}

function Handle-Request {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$State,

        [Parameter(Mandatory = $true)]
        [string]$AppRoot
    )

    $request = $Context.Request
    $response = $Context.Response
    $path = $request.Url.AbsolutePath
    $method = $request.HttpMethod.ToUpperInvariant()

    try {
        if ($method -eq "GET" -and ($path -eq "/" -or $path -eq "/index.html" -or $path -eq "/script.js" -or $path -eq "/style.css")) {
            $relativePath = switch ($path) {
                "/" { "index.html" }
                default { $path.TrimStart("/") }
            }

            $filePath = Join-Path $AppRoot $relativePath
            if (-not (Test-Path -LiteralPath $filePath)) {
                Send-TextResponse -Response $response -Text "Missing file" -StatusCode 500
                return
            }

            $bytes = [System.IO.File]::ReadAllBytes($filePath)
            Send-BytesResponse -Response $response -Bytes $bytes -ContentType (Get-ContentType -Path $filePath)
            return
        }

        if ($method -eq "GET" -and $path -eq "/messages/latest") {
            Send-JsonResponse -Response $response -Payload @{ latestId = (Get-LatestMessageId -State $State) }
            return
        }

        if ($method -eq "GET" -and $path -eq "/messages") {
            $rawAfter = $request.QueryString["after"]
            if ([string]::IsNullOrWhiteSpace($rawAfter)) {
                Send-TextResponse -Response $response -Text "after is required" -StatusCode 400
                return
            }

            $parsed = Try-ParseAfterId -RawValue $rawAfter
            if (-not $parsed.ok) {
                Send-TextResponse -Response $response -Text "after must be integer" -StatusCode 400
                return
            }

            $messages = Wait-ForMessagesAfter -State $State -AfterId $parsed.value
            Send-JsonResponse -Response $response -Payload $messages -AsArray
            return
        }

        if ($method -eq "POST" -and $path -eq "/messages") {
            $raw = Get-RequestBodyText -Request $request
            $payload = $null

            try {
                $payload = $raw | ConvertFrom-Json
            } catch {
                Send-TextResponse -Response $response -Text "invalid json" -StatusCode 400
                return
            }

            $text = [string]$payload.text
            if ([string]::IsNullOrWhiteSpace($text)) {
                Send-TextResponse -Response $response -Text "text is required" -StatusCode 400
                return
            }

            $message = Add-ChatMessage -State $State -Sender (Get-ClientLabel -Address $request.RemoteEndPoint.Address) -Text $text.Trim()
            Send-JsonResponse -Response $response -Payload $message -StatusCode 201
            return
        }

        Send-TextResponse -Response $response -Text "Not Found" -StatusCode 404
    } catch {
        if ($response.OutputStream.CanWrite) {
            Send-TextResponse -Response $response -Text "Internal Server Error" -StatusCode 500
        }
    }
}

function Start-ChatServer {
    $appRoot = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($appRoot)) {
        $appRoot = (Get-Location).Path
    }

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://+:8888/")

    $state = [hashtable]::Synchronized(@{
        Messages = New-Object System.Collections.ArrayList
        NextId = 1
        Lock = [System.Object]::new()
    })

    $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    foreach ($name in @(
        "Get-ContentType",
        "Send-BytesResponse",
        "Send-TextResponse",
        "Send-JsonResponse",
        "Get-ClientLabel",
        "Get-RequestBodyText",
        "Get-LatestMessageId",
        "Get-MessagesAfter",
        "Add-ChatMessage",
        "Wait-ForMessagesAfter",
        "Try-ParseAfterId",
        "Handle-Request"
    )) {
        $iss.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry $name, (Get-Item ("function:" + $name)).ScriptBlock.ToString()))
    }

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, 24, $iss, $Host)
    $runspacePool.Open()
    $handlers = New-Object System.Collections.ArrayList

    try {
        $listener.Start()
        Write-Host "chat listening on http://+:8888/"

        while ($listener.IsListening) {
            
            Cleanup-RequestHandlers -Handlers $handlers

            $context = $listener.GetContext()
            $ps = [powershell]::Create()
            $ps.RunspacePool = $runspacePool
            $null = $ps.AddCommand("Handle-Request").AddArgument($context).AddArgument($state).AddArgument($appRoot)
            $handle = $ps.BeginInvoke()

            [void]$handlers.Add([pscustomobject]@{
                PowerShell = $ps
                Handle = $handle
            })
        }
    } finally {
        foreach ($entry in @($handlers.ToArray())) {
            try {
                $entry.PowerShell.Stop()
            } catch {
            }

            try {
                $entry.PowerShell.Dispose()
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
    Start-ChatServer
}
