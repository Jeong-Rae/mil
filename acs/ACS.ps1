$script:AppRoot = $null
$script:InitialInvocationName = $MyInvocation.InvocationName
$script:InitialArguments = @($args)

function Get-CommandPath {
    param([object]$Command)

    if ($null -eq $Command) {
        return $null
    }

    if ($Command.PSObject.Properties.Match("Path").Count -eq 0) {
        return $null
    }

    $path = [string]$Command.Path
    if ([string]::IsNullOrWhiteSpace($path)) {
        return $null
    }

    $path
}

function Resolve-InitialAppRoot {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $PSScriptRoot
    }

    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return (Split-Path -Parent $PSCommandPath)
    }

    $scriptPath = Get-CommandPath -Command $MyInvocation.MyCommand
    if (-not [string]::IsNullOrWhiteSpace($scriptPath)) {
        return (Split-Path -Parent $scriptPath)
    }

    (Get-Location).Path
}

$script:InitialCommandPath = $null
if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    $script:InitialCommandPath = $PSCommandPath
}
else {
    $script:InitialCommandPath = Get-CommandPath -Command $MyInvocation.MyCommand
}

function Set-AppRoot {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $script:AppRoot = (Get-Location).Path
        return $script:AppRoot
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "app root not found: $Path"
    }

    $resolved = Resolve-Path -LiteralPath $Path
    $script:AppRoot = $resolved.Path
    $script:AppRoot
}

$script:AppRoot = Resolve-InitialAppRoot

function Get-AppRoot {
    if ([string]::IsNullOrWhiteSpace($script:AppRoot)) {
        $script:AppRoot = (Get-Location).Path
    }

    return $script:AppRoot
}

function Normalize-Id {
    param([string]$Id)

    if ($null -eq $Id) {
        return ""
    }

    $Id.Trim().ToUpperInvariant()
}

function Load-SoldierList {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "list.json not found: $Path"
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        $items = ConvertFrom-Json -InputObject $raw
    }
    catch {
        throw "failed to load list.json"
    }

    $index = @{}
    foreach ($item in @($items)) {
        $id = Normalize-Id -Id ([string]$item.id)
        if ([string]::IsNullOrWhiteSpace($id)) {
            continue
        }

        $index[$id] = $item
    }

    $index
}

function Convert-Base32ToUInt64 {
    param([string]$Value)

    $map = @{
        '0' = 0;  '1' = 1;  '2' = 2;  '3' = 3;  '4' = 4;  '5' = 5;  '6' = 6;  '7' = 7
        '8' = 8;  '9' = 9;  'A' = 10; 'B' = 11; 'C' = 12; 'D' = 13; 'E' = 14; 'F' = 15
        'G' = 16; 'H' = 17; 'J' = 18; 'K' = 19; 'M' = 20; 'N' = 21; 'P' = 22; 'Q' = 23
        'R' = 24; 'S' = 25; 'T' = 26; 'V' = 27; 'W' = 28; 'X' = 29; 'Y' = 30; 'Z' = 31
        'I' = 1;  'L' = 1;  'O' = 0
    }

    $normalized = [string]$Value
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        throw "encoded id is empty"
    }

    $result = [UInt64]0
    foreach ($char in $normalized.Trim().ToUpperInvariant().ToCharArray()) {
        if (-not $map.ContainsKey([string]$char)) {
            throw "invalid encoded id"
        }

        $result = ($result * [UInt64]32) + [UInt64]$map[[string]$char]
    }

    $result
}

function Unpack-Id {
    param([UInt64]$Packed)

    $base = [UInt64]100000000
    $tail8 = [UInt64]($Packed % $base)
    $tmp = [UInt64](($Packed - $tail8) / $base)
    $mid2 = [int]($tmp % [UInt64]100)
    $letterIndex = [int](($tmp - [UInt64]$mid2) / [UInt64]100)

    if ($letterIndex -lt 0 -or $letterIndex -gt 25) {
        throw "invalid packed id"
    }

    $letter = [char]([int][char]'A' + $letterIndex)
    $tailText = ("{0:D8}" -f $tail8).TrimStart('0')
    if ([string]::IsNullOrWhiteSpace($tailText)) {
        $tailText = "0"
    }

    "{0}{1:D2}-{2}" -f $letter, $mid2, $tailText
}

function Get-BarcodeChecksum {
    param([string]$Raw)

    $sum = 0
    foreach ($char in $Raw.ToCharArray()) {
        $sum += [int][char]$char
    }

    "{0:D2}" -f ($sum % 97)
}

function Get-SerialFromTypeAndId {
    param(
        [string]$TypeCode,
        [string]$Id
    )

    $canonical = "ACS1|{0}|{1}" -f $TypeCode.ToUpperInvariant(), (Normalize-Id -Id $Id)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
    $sha1 = [System.Security.Cryptography.SHA1]::Create()

    try {
        $hash = $sha1.ComputeHash($bytes)
    }
    finally {
        $sha1.Dispose()
    }

    -join ($hash[0..4] | ForEach-Object { $_.ToString("X2") })
}

function Decode-Barcode {
    param([string]$Barcode)

    $value = [string]$Barcode
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "barcode is empty"
    }

    $value = $value.Trim().ToUpperInvariant()
    if ($value.Length -lt 13) {
        throw "barcode is too short"
    }

    if (-not $value.StartsWith("A1")) {
        throw "invalid barcode prefix"
    }

    $typeCode = $value.Substring(2, 1)
    $type = switch ($typeCode) {
        "E" { "entry"; break }
        "X" { "exit"; break }
        default { throw "invalid barcode type" }
    }

    $checksum = $value.Substring($value.Length - 2, 2)
    $raw = $value.Substring(0, $value.Length - 2)
    if ($checksum -ne (Get-BarcodeChecksum -Raw $raw)) {
        throw "invalid barcode checksum"
    }

    $encodedId = $value.Substring(3, $value.Length - 5)
    if ($encodedId.Length -ne 8) {
        throw "invalid encoded id length"
    }

    $packed = Convert-Base32ToUInt64 -Value $encodedId
    $id = Unpack-Id -Packed $packed
    $serial = Get-SerialFromTypeAndId -TypeCode $typeCode -Id $id

    [pscustomobject]@{
        type   = $type
        id     = $id
        serial = $serial
    }
}

function Should-IgnoreSerial {
    param(
        [hashtable]$RecentSerials,
        [string]$Serial,
        [int]$WindowSeconds = 15
    )

    $now = [DateTime]::UtcNow
    $cleanupBefore = $now.AddSeconds(-60)

    foreach ($key in @($RecentSerials.Keys)) {
        if ([DateTime]$RecentSerials[$key] -lt $cleanupBefore) {
            $RecentSerials.Remove($key)
        }
    }

    if ($RecentSerials.ContainsKey($Serial)) {
        $lastSeen = [DateTime]$RecentSerials[$Serial]
        if ($lastSeen -ge $now.AddSeconds(-1 * $WindowSeconds)) {
            return $true
        }
    }

    $RecentSerials[$Serial] = $now
    $false
}

function Get-LogPath {
    $logsDir = Join-Path -Path (Get-AppRoot) -ChildPath "logs"
    if (-not (Test-Path -LiteralPath $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir | Out-Null
    }

    Join-Path -Path $logsDir -ChildPath "access-log.csv"
}

function Write-AccessLog {
    param(
        [string]$Path,
        [object]$Entry
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory | Out-Null
    }

    $csvParams = @{
        LiteralPath        = $Path
        NoTypeInformation  = $true
        Encoding           = "UTF8"
    }

    if (Test-Path -LiteralPath $Path) {
        $csvParams["Append"] = $true
    }

    $Entry | Export-Csv @csvParams
}

function Resolve-SoldierName {
    param(
        [hashtable]$SoldierIndex,
        [string]$Id
    )

    $key = Normalize-Id -Id $Id
    if ($SoldierIndex.ContainsKey($key)) {
        $candidate = [string]$SoldierIndex[$key].name
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return $candidate.Trim()
        }
    }

    "UNKNOWN"
}

function Process-Barcode {
    param(
        [string]$Barcode,
        [string]$Place,
        [hashtable]$SoldierIndex,
        [hashtable]$RecentSerials,
        [string]$LogPath
    )

    if ([string]::IsNullOrWhiteSpace($Barcode)) {
        return
    }

    try {
        $decoded = Decode-Barcode -Barcode $Barcode
    }
    catch {
        [Console]::WriteLine(("decode error: {0}" -f $_.Exception.Message))
        return
    }

    if (Should-IgnoreSerial -RecentSerials $RecentSerials -Serial $decoded.serial) {
        [Console]::WriteLine(("ignored duplicate serial: {0}" -f $decoded.serial))
        return
    }

    $name = Resolve-SoldierName -SoldierIndex $SoldierIndex -Id $decoded.id
    $entry = [pscustomobject][ordered]@{
        time  = [DateTime]::UtcNow.ToString("s")
        type  = $decoded.type
        place = $Place
        id    = $decoded.id
        name  = $name
    }

    try {
        Write-AccessLog -Path $LogPath -Entry $entry
    }
    catch {
        [Console]::WriteLine(("log error: {0}" -f $_.Exception.Message))
        return
    }

    [Console]::WriteLine((
            "[{0}] {1} {2} {3} {4}" -f `
                $entry.time, `
                $entry.type.ToUpperInvariant(), `
                $entry.id, `
                $entry.name, `
                $entry.place
        ))
}

function Start-ACS {
    [CmdletBinding()]
    param(
        [string]$Place = "unknown",
        [string]$AppRoot
    )

    $previousErrorActionPreference = $ErrorActionPreference

    try {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = "Stop"

        if (-not [string]::IsNullOrWhiteSpace($AppRoot)) {
            [void](Set-AppRoot -Path $AppRoot)
        }

        $resolvedPlace = [string]$Place
        if ([string]::IsNullOrWhiteSpace($resolvedPlace)) {
            $resolvedPlace = "unknown"
        }

        $resolvedAppRoot = Get-AppRoot
        $listPath = Join-Path -Path $resolvedAppRoot -ChildPath "list.json"
        $logPath = Get-LogPath

        try {
            $soldierIndex = Load-SoldierList -Path $listPath
        }
        catch {
            [Console]::Error.WriteLine($_.Exception.Message)
            return
        }

        $recentSerials = @{}

        [Console]::WriteLine(("acs started. place={0}" -f $resolvedPlace))
        [Console]::WriteLine(("list={0}" -f $listPath))
        [Console]::WriteLine(("log={0}" -f $logPath))
        [Console]::WriteLine("scan barcode. type exit to quit.")

        while ($true) {
            $line = Read-Host
            if ($null -eq $line) {
                continue
            }

            $inputValue = $line.Trim()
            if ($inputValue.Length -eq 0) {
                continue
            }

            if ($inputValue.ToLowerInvariant() -eq "exit") {
                break
            }

            Process-Barcode `
                -Barcode $inputValue `
                -Place $resolvedPlace `
                -SoldierIndex $soldierIndex `
                -RecentSerials $recentSerials `
                -LogPath $logPath
        }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
}

function Main {
    [CmdletBinding()]
    param(
        [string]$Place = "unknown",
        [string]$AppRoot
    )

    Start-ACS -Place $Place -AppRoot $AppRoot
}

function Invoke-AcsScriptEntryPoint {
    if ([string]::IsNullOrWhiteSpace($script:InitialCommandPath)) {
        return
    }

    if ($script:InitialInvocationName -eq '.') {
        return
    }

    $place = "unknown"
    if ($script:InitialArguments.Count -gt 0) {
        $candidatePlace = [string]$script:InitialArguments[0]
        if (-not [string]::IsNullOrWhiteSpace($candidatePlace)) {
            $place = $candidatePlace
        }
    }

    $appRoot = $null
    if ($script:InitialArguments.Count -gt 1) {
        $candidateAppRoot = [string]$script:InitialArguments[1]
        if (-not [string]::IsNullOrWhiteSpace($candidateAppRoot)) {
            $appRoot = $candidateAppRoot
        }
    }

    Start-ACS -Place $place -AppRoot $appRoot
}

Invoke-AcsScriptEntryPoint
