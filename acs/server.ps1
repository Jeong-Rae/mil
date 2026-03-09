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
        $value = $Payload | ConvertTo-Json -Compress -Depth 8 -AsArray
        if ($null -eq $value) { "[]" } else { $value }
    } else {
        $Payload | ConvertTo-Json -Compress -Depth 8
    }

    Send-TextResponse -Response $Response -Text $json -ContentType "application/json; charset=utf-8" -StatusCode $StatusCode
}

function Send-RejectedResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [int]$StatusCode = 400
    )

    Send-JsonResponse -Response $Response -Payload @{
        status = "rejected"
        message = $Message
    } -StatusCode $StatusCode
}

function Send-InternalServerError {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response
    )

    if ($Response.OutputStream.CanWrite) {
        Send-RejectedResponse -Response $Response -Message "internal server error" -StatusCode 500
    }
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

function Import-AllowedIds {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ListPath
    )

    $items = Get-Content -LiteralPath $ListPath -Raw | ConvertFrom-Json
    $allowedIds = @{}

    foreach ($item in @($items)) {
        $id = Get-StringField -Object $item -Name "id"
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        $allowedIds[$id] = $true
    }

    return $allowedIds
}

function New-AccessLogFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [System.Text.Encoding]$Encoding
    )

    $dir = Split-Path -Parent $LogPath
    if (-not [string]::IsNullOrWhiteSpace($dir) -and -not (Test-Path -LiteralPath $dir)) { [void](New-Item -ItemType Directory -Path $dir) }
    if (-not (Test-Path -LiteralPath $LogPath)) { [System.IO.File]::WriteAllText($LogPath, "time,type,location,id`n", $Encoding) }
}

function New-AccessRecordLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Location,

        [Parameter(Mandatory = $true)]
        [string]$Id
    )

    return ("{0},{1},{2},{3}" -f [DateTime]::UtcNow.ToString("o"), $Type, $Location, $Id)
}

function Add-AccessRecord {
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

    $encoding = [System.Text.UTF8Encoding]::new($false)
    $line = New-AccessRecordLine -Type $Type -Location $Location -Id $Id
    New-AccessLogFile -LogPath $LogPath -Encoding $encoding
    [System.IO.File]::AppendAllText($LogPath, $line + [Environment]::NewLine, $encoding)
}

function Set-CurrentStatus {
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

        foreach ($name in @($State.Current.Keys)) {
            if ($name -eq $Location) {
                continue
            }

            $other = $State.Current[$name]
            if (-not $other.ContainsKey($Id)) {
                continue
            }

            $other.Remove($Id)
        }

        $bucket[$Id] = $true
    } finally {
        [System.Threading.Monitor]::Exit($State.Lock)
    }
}

function Get-CurrentStatus {
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

function Get-AllCurrentStatus {
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

function Import-CurrentStatus {
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
        if (-not (Test-AccessRecordRow -Row $row)) { continue }
        Set-CurrentStatus -State $State -Type ([string]$row.type) -Location ([string]$row.location) -Id ([string]$row.id)
    }
}

function Test-AccessRecordRow {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Row
    )

    return -not (
        [string]::IsNullOrWhiteSpace([string]$Row.type) -or
        [string]::IsNullOrWhiteSpace([string]$Row.location) -or
        [string]::IsNullOrWhiteSpace([string]$Row.id)
    )
}

function Invoke-StaticResourceRoute {
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

function Read-AccessPayload {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerRequest]$Request,

        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response
    )

    try {
        return (Get-RequestBodyText -Request $Request | ConvertFrom-Json)
    } catch {
        Send-RejectedResponse -Response $Response -Message "invalid json"
        return $null
    }
}

function Invoke-StatusRoute {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory = $true)]
        [hashtable]$State,

        [string]$Location
    )

    if ([string]::IsNullOrWhiteSpace($Location)) {
        Send-JsonResponse -Response $Response -Payload (Get-AllCurrentStatus -State $State) -AsArray
        return $true
    }

    Send-JsonResponse -Response $Response -Payload (Get-CurrentStatus -State $State -Location $Location)
    return $true
}

function Invoke-AccessRoute {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerRequest]$Request,

        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerResponse]$Response,

        [Parameter(Mandatory = $true)]
        [hashtable]$State,

        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$AllowedIds
    )

    $payload = Read-AccessPayload -Request $Request -Response $Response
    if ($null -eq $payload) { return $true }

    $type = Get-StringField -Object $payload -Name "type"
    $location = Get-StringField -Object $payload -Name "location"
    $id = Get-StringField -Object $payload -Name "id"

    if ([string]::IsNullOrWhiteSpace($type) -or [string]::IsNullOrWhiteSpace($location) -or [string]::IsNullOrWhiteSpace($id)) {
        Send-RejectedResponse -Response $Response -Message "type, id, location are required"
        return $true
    }

    if ($type -ne "entry" -and $type -ne "exit") {
        Send-RejectedResponse -Response $Response -Message "type must be entry or exit"
        return $true
    }

    if (-not $AllowedIds.ContainsKey($id)) {
        Send-RejectedResponse -Response $Response -Message "id is not allowed"
        return $true
    }

    try {
        Add-AccessRecord -LogPath $LogPath -Type $type -Location $location -Id $id
        Set-CurrentStatus -State $State -Type $type -Location $location -Id $id
    } catch {
        Send-RejectedResponse -Response $Response -Message "failed to write access record" -StatusCode 500
        return $true
    }

    Send-JsonResponse -Response $Response -Payload @{ status = "logged" }
    return $true
}

function Invoke-ApiRoute {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory = $true)]
        [hashtable]$State,

        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$AllowedIds
    )

    $request = $Context.Request
    $response = $Context.Response
    $path = $request.Url.AbsolutePath
    $method = $request.HttpMethod.ToUpperInvariant()

    if ($method -eq "GET" -and $path -eq "/status") { return (Invoke-StatusRoute -Response $response -State $State -Location ([string]$request.QueryString["location"])) }
    if ($method -eq "POST" -and $path -eq "/access") { return (Invoke-AccessRoute -Request $request -Response $response -State $State -LogPath $LogPath -AllowedIds $AllowedIds) }

    return $false
}

function Invoke-Request {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory = $true)]
        [string]$AppRoot,

        [Parameter(Mandatory = $true)]
        [hashtable]$State,

        [Parameter(Mandatory = $true)]
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [hashtable]$AllowedIds
    )

    if (Invoke-StaticResourceRoute -Context $Context -AppRoot $AppRoot) { return }
    if (Invoke-ApiRoute -Context $Context -State $State -LogPath $LogPath -AllowedIds $AllowedIds) { return }
    Send-TextResponse -Response $Context.Response -Text "Not Found" -StatusCode 404
}

function Start-AcsServer {
    $appRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) { (Get-Location).Path } else { $PSScriptRoot }
    $logPath = Join-Path $appRoot "logs/access-log.csv"
    $listPath = Join-Path $appRoot "list.json"
    $allowedIds = Import-AllowedIds -ListPath $listPath

    $state = @{
        Current = @{}
        Lock = [System.Object]::new()
    }

    Import-CurrentStatus -State $state -LogPath $logPath

    $listener = [System.Net.HttpListener]::new()
    $prefix = "http://+:8888/"
    $listener.Prefixes.Add($prefix)

    Write-Host ("ACS listening on {0}" -f $prefix)
    Write-Host ("App root: {0}" -f $appRoot)
    Write-Host ("Log path: {0}" -f $logPath)
    Write-Host ("List path: {0}" -f $listPath)

    try {
        $listener.Start()

        while ($listener.IsListening) {
            $context = $listener.GetContext()

            try {
                Invoke-Request -Context $context -AppRoot $appRoot -State $state -LogPath $logPath -AllowedIds $allowedIds
            } catch {
                Send-InternalServerError -Response $context.Response
            }
        }
    } finally {
        if ($listener.IsListening) {
            $listener.Stop()
        }

        $listener.Close()
    }
}

Start-AcsServer
