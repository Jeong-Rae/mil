param(
    [string]$Root
)

$ErrorActionPreference = "Stop"

$Port = 3000
$Prefix = "http://localhost:$Port/"
$Routes = @{
    "/"          = @("index.html", "text/html; charset=utf-8")
    "/index.html" = @("index.html", "text/html; charset=utf-8")
    "/app.js"    = @("app.js", "application/javascript; charset=utf-8")
    "/style.css" = @("style.css", "text/css; charset=utf-8")
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add($Prefix)

Write-Host "Static client server starting..."
Write-Host "Open: http://localhost:$Port/"
Write-Host "Static root: $Root"
Write-Host "Press Ctrl+C to stop."

try {
    $listener.Start()

    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
        }
        catch [System.Net.HttpListenerException] {
            break
        }
        catch [System.ObjectDisposedException] {
            break
        }

        $path = $context.Request.Url.AbsolutePath
        $route = $Routes[$path]

        if ($null -eq $route) {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes("Not Found")
            $context.Response.StatusCode = 404
            $context.Response.ContentType = "text/plain; charset=utf-8"
        }
        else {
            $bytes = [System.IO.File]::ReadAllBytes((Join-Path $Root $route[0]))
            $context.Response.StatusCode = 200
            $context.Response.ContentType = $route[1]
        }

        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.OutputStream.Close()
    }
}
finally {
    if ($listener.IsListening) {
        $listener.Stop()
    }

    $listener.Close()
}
