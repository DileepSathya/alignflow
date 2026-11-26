param([string]$Tag = 'vclear-aligners:0.1.0')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location (Join-Path $root 'flutter_app')
try {
    flutter build web --release --no-web-resources-cdn --dart-define=SAME_ORIGIN_API=true
    if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }
} finally {
    Pop-Location
}
docker build --tag $Tag $root
if ($LASTEXITCODE -ne 0) { throw 'Docker image build failed.' }
