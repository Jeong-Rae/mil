$ErrorActionPreference = "Stop"

# Edit these constants directly before running on your LAN.
$ListenerPrefix = "http://+:9999/api/"
$StaticPrefix = "http://+:9999/"
$ClientConnectUrl = "ws://{server-ip}:9999/api/"
$StaticRoot = (Get-Location).Path
$RunspaceMax = 16

. "./server/static.ps1"
. "./server/socket.ps1"
. "./server/main.ps1"

Main
