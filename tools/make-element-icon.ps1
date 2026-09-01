# Generates the 64x64 icon MCreator shows for the "KASHI Particle" element type.
#
# Every registered mod element type MUST ship an icon at
#   themes/<theme>/images/mod_types/<registryname>.png
# or MCreator throws "Image not found: mod_types.<registryname>" and the workspace fails to open.
# The icon is written for every bundled theme so it looks right whichever one is active.
#
# Downscaled from assets/particles-icon.png (the project's own artwork) with high-quality bicubic
# resampling. Re-run this after replacing that source image.

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$project = Split-Path -Parent $PSScriptRoot
$themes  = @("default_dark", "default_light", "legacy_dark", "matrix", "midnight")
$size    = 64

$sourcePath = Join-Path $project "assets\particle-icon.png"
if (-not (Test-Path $sourcePath)) { throw "icon source not found: $sourcePath" }

$source   = [System.Drawing.Image]::FromFile($sourcePath)
$bitmap   = New-Object System.Drawing.Bitmap($size, $size)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$graphics.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$graphics.Clear([System.Drawing.Color]::Transparent)
$graphics.DrawImage($source, 0, 0, $size, $size)
$graphics.Dispose()
$source.Dispose()

foreach ($theme in $themes) {
    $dir = Join-Path $project "src\themes\$theme\images\mod_types"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $bitmap.Save((Join-Path $dir "kashiparticle.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "wrote $theme/images/mod_types/kashiparticle.png"
}

$bitmap.Dispose()
