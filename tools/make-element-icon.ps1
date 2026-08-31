# Generates the 64x64 icon MCreator shows for the "KASHI Particle" element type.
#
# Every registered mod element type MUST ship an icon at
#   themes/<theme>/images/mod_types/<registryname>.png
# or MCreator throws "Image not found: mod_types.<registryname>" and the workspace fails to open.
# The icon is written for every bundled theme so it looks right whichever one is active.

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$project = Split-Path -Parent $PSScriptRoot
$themes  = @("default_dark", "default_light", "legacy_dark", "matrix", "midnight")
$size    = 64

$bitmap   = New-Object System.Drawing.Bitmap($size, $size)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::Transparent)

# Three sweeping arcs, echoing the slash texture these effects are usually built from.
$arcs = @(
    @{ Rect = @(8, 8, 48, 48);   Start = 200; Sweep = 110; Width = 5.5; Alpha = 255 },
    @{ Rect = @(16, 14, 36, 36); Start = 230; Sweep = 95;  Width = 4.0; Alpha = 190 },
    @{ Rect = @(24, 20, 24, 24); Start = 255; Sweep = 80;  Width = 3.0; Alpha = 130 }
)

foreach ($arc in $arcs) {
    $color = [System.Drawing.Color]::FromArgb($arc.Alpha, 64, 224, 168)
    $pen = New-Object System.Drawing.Pen($color, [float]$arc.Width)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round

    $graphics.DrawArc($pen, $arc.Rect[0], $arc.Rect[1], $arc.Rect[2], $arc.Rect[3],
        [float]$arc.Start, [float]$arc.Sweep)
    $pen.Dispose()
}

# Scattered sparks, so the icon still reads as "particles" and not just a swoosh.
$sparks = @(@(46, 16, 6), @(54, 27, 4), @(40, 9, 3), @(52, 40, 3))

foreach ($spark in $sparks) {
    $brush = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(235, 128, 245, 200))
    $graphics.FillEllipse($brush, $spark[0], $spark[1], $spark[2], $spark[2])
    $brush.Dispose()
}

$graphics.Dispose()

foreach ($theme in $themes) {
    $dir = Join-Path $project "src\themes\$theme\images\mod_types"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null

    $bitmap.Save((Join-Path $dir "kashiparticle.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    Write-Host "wrote $theme/images/mod_types/kashiparticle.png"
}

$bitmap.Dispose()
