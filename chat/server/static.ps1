function Write-StaticResponse {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.HttpListenerContext]$Context
    )

    $routes = @{
        "/" = @("index.html", "text/html; charset=utf-8")
        "/index.html" = @("index.html", "text/html; charset=utf-8")
        "/app.js" = @("app.js", "application/javascript; charset=utf-8")
        "/style.css" = @("style.css", "text/css; charset=utf-8")
    }

    $route = $routes[$Context.Request.Url.AbsolutePath]

    if ($null -eq $route) {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes("Not Found")
        $Context.Response.StatusCode = 404
        $Context.Response.ContentType = "text/plain; charset=utf-8"
    }
    else {
        $filePath = [System.IO.Path]::Combine($StaticRoot, $route[0])
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $Context.Response.StatusCode = 200
        $Context.Response.ContentType = $route[1]
    }

    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.OutputStream.Close()
}
