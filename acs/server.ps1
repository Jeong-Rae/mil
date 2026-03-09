Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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
        $Payload | ConvertTo-Json -Compress -Depth 8 -AsArray
    } else {
        $Payload | ConvertTo-Json -Compress -Depth 8
    }

    Send-TextResponse -Response $Response -Text $json -ContentType "application/json; charset=utf-8" -StatusCode $StatusCode
}

function Get-RequestBodyText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerRequest]$Request
    )

    $encoding = if ($null -ne $Request.ContentEncoding) { $Request.ContentEncoding } else { [System.Text.Encoding]::UTF8 }
    $reader = [System.IO.StreamReader]::new($Request.InputStream, $encoding)

    try {
        return $reader.ReadToEnd()
    } finally {
        $reader.Dispose()
    }
}

function Get-StringField {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Object,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return ""
    }

    return [string]$property.Value
}

function Write-Tuple {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    $dir = Split-Path -Parent $LogPath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) {
        [void](New-Item -ItemType Directory -Path $dir)
    }

    $time = [DateTime]::UtcNow.ToString("o")
    $line = "{0},{1},{2},{3}" -f $time, $Type, $Location, $Id
    $encoding = [System.Text.UTF8Encoding]::new($false)

    if (-not (Test-Path -LiteralPath $LogPath)) {
        [System.IO.File]::WriteAllText($LogPath, "time,type,location,id`n", $encoding)
    }

    [System.IO.File]::AppendAllText($LogPath, $line + [Environment]::NewLine, $encoding)
}

function Update-Current-Status {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,

        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    [System.Threading.Monitor]::Enter($State.Lock)
    try {
        if (-not $State.Current.ContainsKey($Location)) {
            $State.Current[$Location] = @{}
        }

        $bucket = $State.Current[$Location]
        if ($Type -eq "entry") {
            $bucket[$Id] = $true
            return
        }

        if ($bucket.ContainsKey($Id)) {
            $bucket.Remove($Id)
        }
    } finally {
        [System.Threading.Monitor]::Exit($State.Lock)
    }
}

function Get-Current-Status {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,

        [Parameter(Mandatory = $true)]
        [string]$Location
    )

    [System.Threading.Monitor]::Enter($State.Lock)
    try {
        $ids = @()
        if ($State.Current.ContainsKey($Location)) {
            $ids = @($State.Current[$Location].Keys | Sort-Object)
        }

        return [pscustomobject]@{
            location = $Location
            ids = $ids
        }
    } finally {
        [System.Threading.Monitor]::Exit($State.Lock)
    }
}

function Get-All-Current-Status {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State
    )

    [System.Threading.Monitor]::Enter($State.Lock)
    try {
        $items = New-Object System.Collections.ArrayList
        foreach ($location in @($State.Current.Keys | Sort-Object)) {
            $ids = @($State.Current[$location].Keys | Sort-Object)
            [void]$items.Add([pscustomobject]@{
                location = $location
                ids = $ids
            })
        }

        return @($items)
    } finally {
        [System.Threading.Monitor]::Exit($State.Lock)
    }
}

function Restore-Current-Status {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$State,

        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return
    }

    $rows = Import-Csv -LiteralPath $LogPath
    foreach ($row in $rows) {
        if ([string]::IsNullOrWhiteSpace([string]$row.type) -or [string]::IsNullOrWhiteSpace([string]$row.location) -or [string]::IsNullOrWhiteSpace([string]$row.id)) {
            continue
        }

        Update-Current-Status -State $State -Type ([string]$row.type) -Location ([string]$row.location) -Id ([string]$row.id)
    }
}

function Route-Static-Resource {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$AppRoot
    )

    $request = $Context.Request
    $response = $Context.Response
    $path = $request.Url.AbsolutePath
    $method = $request.HttpMethod.ToUpperInvariant()

    if ($method -ne "GET") {
        return $false
    }

    $relativePath = switch ($path) {
        "/" { "index.html" }
        "/index.html" { "index.html" }
        "/board.html" { "board.html" }
        "/script.js" { "script.js" }
        "/style.css" { "style.css" }
        default { $null }
    }

    if ($null -eq $relativePath) {
        return $false
    }

    $filePath = Join-Path $AppRoot $relativePath
    if (-not (Test-Path -LiteralPath $filePath)) {
        Send-TextResponse -Response $response -Text "Missing file" -StatusCode 500
        return $true
    }

    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    Send-BytesResponse -Response $response -Bytes $bytes -ContentType (Get-ContentType -Path $filePath)
    return $true
}

function Route-API {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory = $true)]
        [hashtable]$State,

        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    $request = $Context.Request
    $response = $Context.Response
    $path = $request.Url.AbsolutePath
    $method = $request.HttpMethod.ToUpperInvariant()

    if ($method -eq "GET" -and $path -eq "/status") {
        $location = [string]$request.QueryString["location"]
        if ([string]::IsNullOrWhiteSpace($location)) {
            Send-JsonResponse -Response $response -Payload (Get-All-Current-Status -State $State) -AsArray
            return $true
        }

        Send-JsonResponse -Response $response -Payload (Get-Current-Status -State $State -Location $location)
        return $true
    }

    if ($method -eq "POST" -and $path -eq "/access") {
        $raw = Get-RequestBodyText -Request $request
        $payload = $null

        try {
            $payload = $raw | ConvertFrom-Json
        } catch {
            Send-JsonResponse -Response $response -Payload @{
                status = "rejected"
                message = "invalid json"
            } -StatusCode 400
            return $true
        }

        $type = Get-StringField -Object $payload -Name "type"
        $location = Get-StringField -Object $payload -Name "location"
        $id = Get-StringField -Object $payload -Name "id"

        if ([string]::IsNullOrWhiteSpace($type) -or [string]::IsNullOrWhiteSpace($location) -or [string]::IsNullOrWhiteSpace($id)) {
            Send-JsonResponse -Response $response -Payload @{
                status = "rejected"
                message = "type, id, location are required"
            } -StatusCode 400
            return $true
        }

        if ($type -ne "entry" -and $type -ne "exit") {
            Send-JsonResponse -Response $response -Payload @{
                status = "rejected"
                message = "type must be entry or exit"
            } -StatusCode 400
            return $true
        }

        try {
            Write-Tuple -LogPath $LogPath -Type $type -Location $location -Id $id
            Update-Current-Status -State $State -Type $type -Location $location -Id $id
        } catch {
            Send-JsonResponse -Response $response -Payload @{
                status = "rejected"
                message = "failed to write access record"
            } -StatusCode 500
            return $true
        }

        Send-JsonResponse -Response $response -Payload @{
            status = "logged"
        }
        return $true
    }

    return $false
}

function Main {
    $appRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { (Get-Location).Path } else { $PSScriptRoot }
    $logPath = Join-Path $appRoot "logs/access-log.csv"

    $state = @{
        Current = @{}
        Lock = [System.Object]::new()
    }

    Restore-Current-Status -State $state -LogPath $logPath

    $listener = [System.Net.HttpListener]::new()
    $prefix = "http://+:8888/"
    $listener.Prefixes.Add($prefix)

    Write-Host ("ACS listening on {0}" -f $prefix)
    Write-Host ("App root: {0}" -f $appRoot)
    Write-Host ("Log path: {0}" -f $logPath)

    try {
        $listener.Start()

        while ($listener.IsListening) {
            $context = $listener.GetContext()
            $response = $context.Response

            try {
                if (Route-Static-Resource -Context $context -AppRoot $appRoot) {
                    continue
                }

                if (Route-API -Context $context -State $state -LogPath $logPath) {
                    continue
                }

                Send-TextResponse -Response $response -Text "Not Found" -StatusCode 404
            } catch {
                if ($response.OutputStream.CanWrite) {
                    Send-JsonResponse -Response $response -Payload @{
                        status = "rejected"
                        message = "internal server error"
                    } -StatusCode 500
                }
            }
        }
    } finally {
        if ($listener.IsListening) {
            $listener.Stop()
        }

        $listener.Close()
    }
}

Main
