param([Parameter(Mandatory = $true)][string]$ProjectRoot)

$ErrorActionPreference = 'Stop'
$backendEnv = Join-Path $ProjectRoot 'backend\.env'
if (Test-Path -LiteralPath $backendEnv) {
    $customUrl = Get-Content -LiteralPath $backendEnv | Where-Object { $_ -match '^\s*MONGODB_URL\s*=' } | Select-Object -First 1
    if ($customUrl) {
        Write-Host 'Using MONGODB_URL from backend/.env; skipping local MongoDB startup.'
        exit 0
    }
}

function Test-MongoPort {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $attempt = $client.BeginConnect('127.0.0.1', 27017, $null, $null)
        if (-not $attempt.AsyncWaitHandle.WaitOne(500)) { return $false }
        $client.EndConnect($attempt)
        return $true
    } catch { return $false }
    finally { $client.Close() }
}

if (Test-MongoPort) {
    Write-Host 'MongoDB is already listening on 127.0.0.1:27017.'
    exit 0
}

$serverRoot = 'C:\Program Files\MongoDB\Server'
$mongod = Get-ChildItem -LiteralPath $serverRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'bin\mongod.exe' } |
    Where-Object { Test-Path -LiteralPath $_ } |
    Select-Object -First 1
if (-not $mongod) {
    Write-Error 'MongoDB is not installed. Install MongoDB Server or configure MONGODB_URL in backend/.env.'
    exit 1
}

$localRoot = Join-Path $ProjectRoot '.local\mongodb'
$dataPath = Join-Path $localRoot 'data'
$logPath = Join-Path $localRoot 'log\mongod.log'
New-Item -ItemType Directory -Force -Path $dataPath, (Split-Path $logPath) | Out-Null
$mongoArgs = @('--dbpath', $dataPath, '--logpath', $logPath, '--logappend',
    '--bind_ip', '127.0.0.1', '--port', '27017', '--wiredTigerCacheSizeGB', '0.25',
    '--setParameter', 'diagnosticDataCollectionEnabled=false')
Start-Process -FilePath $mongod -ArgumentList $mongoArgs -WindowStyle Hidden
for ($i = 0; $i -lt 30; $i++) {
    if (Test-MongoPort) {
        Write-Host "Local MongoDB started. Data: $dataPath"
        exit 0
    }
    Start-Sleep -Milliseconds 500
}
Write-Error "MongoDB did not start. Check $logPath"
exit 1
