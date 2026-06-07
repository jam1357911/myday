param([int]$Port = 8081)

$root = (Get-Location).Path
$server = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
$server.Start()

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  Web App Server started!" -ForegroundColor Green
Write-Host "  Open: http://localhost:$Port/daily.html" -ForegroundColor Yellow
Write-Host "  Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host "======================================" -ForegroundColor Cyan

$htmlMime = "text/html; charset=utf-8"
$mimeMap = @{".html"=$htmlMime;".css"="text/css; charset=utf-8";".js"="application/javascript; charset=utf-8";".json"="application/json";".png"="image/png";".jpg"="image/jpeg";".ico"="image/x-icon"}

while ($true) {
    $client = $server.AcceptTcpClient()
    $stream = $client.GetStream()
    $reader = New-Object System.IO.StreamReader($stream)

    try {
        $requestLine = $reader.ReadLine()
        if (-not $requestLine) { $client.Close(); continue }

        $parts = $requestLine.Split(' ')
        $method = $parts[0]
        $path = $parts[1]
        $headers = @{}
        while ($true) {
            $line = $reader.ReadLine()
            if ($line -eq '' -or $line -eq $null) { break }
            $colon = $line.IndexOf(':')
            if ($colon -gt 0) { $headers[$line.Substring(0,$colon).Trim()] = $line.Substring($colon+1).Trim() }
        }

        $body = [System.Text.Encoding]::UTF8.GetBytes("")
        $status = "200 OK"
        $contentType = $htmlMime

        if ($path -match "^/api/proxy\?url=(.+)$") {
            $target = [System.Uri]::UnescapeDataString($matches[1])
            if ($target) {
                $req = [System.Net.HttpWebRequest]::Create($target)
                $req.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                $req.Accept = "*/*"
                $req.Headers.Add("Accept-Encoding", "identity")
                $req.Timeout = 15000
                $req.ReadWriteTimeout = 15000

                $resp = $req.GetResponse()
                try {
                    $contentType = $resp.ContentType
                    $rs = $resp.GetResponseStream()
                    try {
                        $ms = New-Object System.IO.MemoryStream
                        $rs.CopyTo($ms)
                        $body = $ms.ToArray()
                    } finally {
                        try { $rs.Close() } catch {}
                    }
                } finally {
                    try { $resp.Close() } catch {}
                }
                Write-Host "  [OK] $($target.Substring(0, [Math]::Min(55, $target.Length)))..." -ForegroundColor DarkGreen
            } else {
                $status = "400 Bad Request"
                $body = [System.Text.Encoding]::UTF8.GetBytes('{"error":"missing url"}')
            }
        } else {
            $filePath = if ($path -eq "/" -or $path -eq "") { Join-Path $root "daily.html" } else { Join-Path $root $path.TrimStart('/') }
            if (Test-Path $filePath -PathType Leaf) {
                $ext = [System.IO.Path]::GetExtension($filePath)
                $contentType = if ($mimeMap.ContainsKey($ext)) { $mimeMap[$ext] } else { "application/octet-stream" }
                $body = [System.IO.File]::ReadAllBytes($filePath)
            } else {
                $status = "404 Not Found"
                $body = [System.Text.Encoding]::UTF8.GetBytes("Not Found")
            }
        }

        $writer = New-Object System.IO.StreamWriter($stream)
        $writer.WriteLine("HTTP/1.1 $status")
        $writer.WriteLine("Content-Type: $contentType")
        $writer.WriteLine("Content-Length: $($body.Length)")
        $writer.WriteLine("Connection: close")
        $writer.WriteLine("Access-Control-Allow-Origin: *")
        $writer.WriteLine("")
        $writer.Flush()
        if ($body.Length -gt 0) { $stream.Write($body, 0, $body.Length) }
    } catch {
        Write-Host "  [ERR] $($_.Exception.Message)" -ForegroundColor Red
        try {
            $writer = New-Object System.IO.StreamWriter($stream)
            $writer.WriteLine("HTTP/1.1 500 Internal Server Error")
            $writer.WriteLine("Content-Length: 0")
            $writer.WriteLine("Connection: close")
            $writer.WriteLine("")
            $writer.Flush()
        } catch {}
    }

    try { $stream.Close() } catch {}
    try { $client.Close() } catch {}
}
