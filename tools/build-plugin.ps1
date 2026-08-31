# Builds the KASHI Particles Plus MCreator plugin and installs it into the test MCreator copy.
#
# The plugin zip is: everything under src/ at the zip root, plus the compiled plugin classes.
#
# Compiling against MCreator needs net.mcreator.* on the classpath, and those classes are not in
# lib\*.jar - they live inside mcreator.exe, which is a JAR wrapped by launch4j.
#
# Renaming the exe to .jar does not work: javac's zip reader rejects it with "zip END header not
# found". launch4j wraps the archive with a ~192 KB stub in front, and javac needs a clean jar.
# .NET's ZipArchive, unlike javac, happily reads the archive once the front stub is removed, so
# we strip the stub in memory, then copy every entry through ZipArchive into a fresh jar that
# javac accepts. No external tools, no trailer trouble. Cached; only redone when the exe changes.

$ErrorActionPreference = "Stop"

$project  = Split-Path -Parent $PSScriptRoot
# The repo (this script's parent tree) and the local-only dev environment (MCreator install,
# test workspaces) are sibling folders under the project root - see docs/DEVELOPMENT.md.
$localRoot = Join-Path (Split-Path -Parent $project) "local"
$mcreator  = Join-Path $localRoot "mcreator"
$work     = Join-Path $env:TEMP "kashi-plugin-build"
$apiJar   = Join-Path $work "mcreator-api.jar"
$classes  = Join-Path $work "classes"
$staging  = Join-Path $work "staging"
$output   = Join-Path $mcreator "plugins\kashi_particles_plus.zip"

$javac = Join-Path $mcreator "jdk\bin\javac.exe"
$jar   = Join-Path $mcreator "jdk\bin\jar.exe"
$exe   = Join-Path $mcreator "mcreator.exe"

if (-not (Test-Path $javac)) { throw "JDK not found at $javac" }
if (-not (Test-Path $exe))   { throw "mcreator.exe not found at $exe" }

New-Item -ItemType Directory -Path $work -Force | Out-Null

# Guards a bug that cost two full test cycles to find and un-find: a procedure .ftl resolving a
# "CUSTOM:X" field through generator.map(field$x, "kashiparticle"). generator.map() only knows how
# to resolve CUSTOM: references for MCreator's own BUILT-IN datalists (sounds, projectiles, ...);
# "kashiparticle" is entirely plugin-defined, so it has nothing to look up and hands back something
# close to the raw field - capitals and all, an invalid ResourceLocation that CRASHES THE GAME on
# first use, and once even resolved to a different element than the one actually picked. Our own
# procedures instead reproduce MCreator's own registryName transform themselves in FreeMarker (see
# entity_spawn_kashi_particle_from_target.java.ftl) - a plain lower-case is ALSO wrong here, since
# MCreator's real registryName inserts an underscore at each camelCase boundary.
#
# FreeMarker comments are stripped before matching, so a .ftl is free to explain generator.map()'s
# own name in prose without tripping this.
$badPattern = Get-ChildItem (Join-Path $project "src") -Recurse -Filter "*.ftl" | ForEach-Object {
    $filePath = $_.FullName
    $code = (Get-Content $filePath -Raw) -replace '(?s)<#--.*?-->', ''
    $lineNumber = 0

    foreach ($codeLine in ($code -split "`n")) {
        $lineNumber++

        if ($codeLine -match 'generator\.map\([^)]*"kashiparticle"') {
            [pscustomobject]@{ Path = $filePath; Line = $lineNumber }
        }
    }
}

if ($badPattern) {
    Write-Host "FOUND generator.map() used against the kashiparticle datalist - this crashes the game:"
    $badPattern | ForEach-Object { Write-Host "  $($_.Path):$($_.Line)" }
    throw "resolve the effect id by reproducing MCreator's registryName transform instead - see the comment above this check"
}

$apiStamp = Join-Path $work "mcreator-api.stamp"
$exeStamp = (Get-Item $exe).LastWriteTime.Ticks.ToString()

if (-not (Test-Path $apiJar) -or -not (Test-Path $apiStamp) -or (Get-Content $apiStamp) -ne $exeStamp) {
    Write-Host "Extracting the MCreator API from mcreator.exe (one-off, cached)..."

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $bytes = [System.IO.File]::ReadAllBytes($exe)
    $offset = -1

    for ($i = 0; $i -lt $bytes.Length - 4; $i++) {
        if ($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and $bytes[$i+2] -eq 0x03 -and $bytes[$i+3] -eq 0x04) {
            $offset = $i
            break
        }
    }

    if ($offset -lt 0) { throw "no zip archive found inside mcreator.exe" }

    $stripped = Join-Path $work "mcreator-stripped.zip"
    [System.IO.File]::WriteAllBytes($stripped, $bytes[$offset..($bytes.Length - 1)])

    if (Test-Path $apiJar) { Remove-Item $apiJar -Force }

    $count = 0
    $source = [System.IO.Compression.ZipFile]::OpenRead($stripped)
    try {
        $dest = [System.IO.Compression.ZipFile]::Open($apiJar, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($entry in $source.Entries) {
                if ($entry.FullName.EndsWith("/")) { continue }

                $target = $dest.CreateEntry($entry.FullName, [System.IO.Compression.CompressionLevel]::Optimal)
                $inStream = $entry.Open()
                $outStream = $target.Open()

                try { $inStream.CopyTo($outStream) } finally { $outStream.Dispose(); $inStream.Dispose() }

                $count++
            }
        } finally { $dest.Dispose() }
    } finally { $source.Dispose() }

    Remove-Item $stripped -Force
    Set-Content $apiStamp $exeStamp -Encoding utf8

    Write-Host "  repacked $count entries into a clean jar"
}

foreach ($dir in @($classes, $staging)) {
    if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
}

$libs = (Get-ChildItem (Join-Path $mcreator "lib") -Filter "*.jar" | ForEach-Object { $_.FullName }) -join ";"
$classpath = "$apiJar;$libs"

# The wizard validates imported .particle.json with the SAME parser the mod runtime uses, so the
# core sources compile into the plugin too - one source of truth for parsing.
$sources = @()
$sources += Get-ChildItem (Join-Path $project "src-java") -Recurse -Filter "*.java" | ForEach-Object { $_.FullName }
$sources += Get-ChildItem (Join-Path $project "core\src\main\java") -Recurse -Filter "*.java" | ForEach-Object { $_.FullName }

Write-Host "Compiling $($sources.Count) plugin source file(s)..."
# -proc:none: MCreator's own dependencies drag annotation processors onto the classpath that we
# have no use for, and javac warns about them on every build.
& $javac -encoding UTF-8 -proc:none -classpath $classpath -d $classes $sources
if ($LASTEXITCODE -ne 0) { throw "plugin compilation failed" }

Copy-Item (Join-Path $project "src\*") $staging -Recurse -Force
Copy-Item (Join-Path $classes "*") $staging -Recurse -Force

# NOT Compress-Archive: on Windows PowerShell it writes zip entries with backslash separators,
# which violates the ZIP spec. Java's classloader then cannot find the classes and the plugin
# reports "fully loaded: no" with a ClassNotFoundException. We build the zip through .NET and
# force forward slashes on every entry name.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (Test-Path $output) { Remove-Item $output -Force }

$stagingFull = (Resolve-Path $staging).Path
$archive = [System.IO.Compression.ZipFile]::Open($output, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem $stagingFull -Recurse -File | ForEach-Object {
        $entryName = $_.FullName.Substring($stagingFull.Length + 1).Replace("\", "/")

        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive, $_.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal)
    }
} finally { $archive.Dispose() }

Write-Host "`nInstalled: $output"
Write-Host "Entries (must use forward slashes):"
$verify = [System.IO.Compression.ZipFile]::OpenRead($output)
try { $verify.Entries | ForEach-Object { "  " + $_.FullName } } finally { $verify.Dispose() }
