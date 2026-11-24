param([ValidateSet('web', 'apk', 'appbundle')][string]$Target = 'web',
      [switch]$IconsOnly)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$project = Join-Path $PSScriptRoot '../flutter_app'
$source = Get-Content (Join-Path $project 'lib/branding.dart') -Raw
$literal = ($source -split 'const _logoBase64 =', 2)[1]
# Extract adjacent Dart string literals in source order.
$encoded = ([regex]::Matches($literal, "'([A-Za-z0-9+/=]+)'") | ForEach-Object { $_.Groups[1].Value }) -join ''
$stream = [IO.MemoryStream]::new([Convert]::FromBase64String($encoded))
$logo = [Drawing.Bitmap]::new($stream)
$symbol = [Drawing.Bitmap]::new(186, 220)
try {
    # The wordmark's hyphen also enters this rectangle to the right of the V.
    for ($x = 0; $x -lt $symbol.Width; $x++) {
        for ($y = 0; $y -lt $symbol.Height; $y++) {
            if ($x -ge 160 -and $y -ge 148) { continue }
            $symbol.SetPixel($x, $y, $logo.GetPixel($x, $y))
        }
    }
    $icons = @{
        'web/favicon.png' = 32
        'web/icons/Icon-192.png' = 192
        'web/icons/Icon-512.png' = 512
        'web/icons/Icon-maskable-192.png' = 192
        'web/icons/Icon-maskable-512.png' = 512
    }
    $densities = @{mdpi=48; hdpi=72; xhdpi=96; xxhdpi=144; xxxhdpi=192}
    foreach ($density in $densities.Keys) {
        $icons["android/app/src/main/res/mipmap-$density/ic_launcher.png"] = $densities[$density]
    }
    foreach ($path in $icons.Keys) {
        $size = $icons[$path]
        $icon = [Drawing.Bitmap]::new($size, $size)
        $graphics = [Drawing.Graphics]::FromImage($icon)
        try {
            $graphics.Clear([Drawing.Color]::White)
            $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $height = if ($path -like '*maskable*') { $size * 0.60 } else { $size * 0.88 }
            $width = $height * $symbol.Width / $symbol.Height
            $rect = [Drawing.RectangleF]::new(($size-$width)/2, ($size-$height)/2, $width, $height)
            $graphics.DrawImage($symbol, $rect)
            $icon.Save((Join-Path $project $path), [Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $graphics.Dispose()
            $icon.Dispose()
        }
    }
} finally {
    $symbol.Dispose()
    $logo.Dispose()
    $stream.Dispose()
}
if (!$IconsOnly) {
    Push-Location $project
    try { flutter build $Target --release; exit $LASTEXITCODE }
    finally { Pop-Location }
}
