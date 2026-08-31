# Type-checks the mod-side runtime WITHOUT gradle.
#
# gradle's neoform step is heavy and, on this network drive with the workspace's 1 GB heap, prone
# to stalling. But the compile classpath already exists on disk: the moddev "merged" jar holds all
# of Minecraft + the NeoForge API, and every other dependency (FML loader, joml, brigadier,
# DataFixerUpper, gson, netty) sits in the gradle module cache. Point javac at all of them and we
# get compile errors in seconds, no daemon involved.
#
# This does NOT produce a runnable mod - it only checks that the code compiles against the real
# 1.21.1 API. Building and running still goes through MCreator.

$ErrorActionPreference = "Stop"

$project   = Split-Path -Parent $PSScriptRoot
# The repo (this script's parent tree) and the local-only dev environment (MCreator install,
# test workspaces) are sibling folders under the project root - see docs/DEVELOPMENT.md.
$localRoot = Join-Path (Split-Path -Parent $project) "local"
$mcreator  = Join-Path $localRoot "mcreator"
$workspace = Join-Path $localRoot "workspace\kashi_particle_test"
$out       = Join-Path $env:TEMP "kashi-modcheck"

$javac = Join-Path $mcreator "jdk\bin\javac.exe"
if (-not (Test-Path $javac)) { throw "JDK not found at $javac" }

# The merged jar is authoritative for Minecraft + NeoForge classes; everything else fills in the
# library dependencies. Sources jars are excluded so they do not shadow the real classes.
$artifacts = Join-Path $workspace "build\moddev\artifacts\neoforge-21.1.190-merged.jar"
if (-not (Test-Path $artifacts)) { throw "merged jar not found - open/build the workspace in MCreator once first" }

$cache = Join-Path $env:USERPROFILE ".mcreator\gradle\caches\modules-2\files-2.1"
$deps = Get-ChildItem $cache -Recurse -Filter "*.jar" -EA SilentlyContinue |
        Where-Object { $_.Name -notmatch "-sources\.jar$" -and $_.Name -notmatch "-javadoc\.jar$" } |
        ForEach-Object { $_.FullName }

$classpath = (@($artifacts) + $deps) -join ";"

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Path $out -Force | Out-Null

$sources = Get-ChildItem (Join-Path $workspace "src\main\java\net\kashi") -Recurse -Filter "*.java" |
           ForEach-Object { $_.FullName }

Write-Host "Type-checking $($sources.Count) files against $($deps.Count + 1) jars..."

# javac writes even its harmless notes ("uses a deprecated API") to stderr, and with
# ErrorActionPreference = Stop PowerShell turns any native stderr line into a terminating error -
# so a successful compile would abort this script before it could report success. Relax the
# preference across the call only, and judge the result by the exit code, which is what javac
# actually uses to signal failure.
$previous = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $javac -encoding UTF-8 -proc:none -nowarn -classpath $classpath -d $out $sources
$code = $LASTEXITCODE
$ErrorActionPreference = $previous

if ($code -eq 0) {
    Write-Host "`nOK - mod-side runtime compiles against the NeoForge 1.21.1 API."
} else {
    Write-Host "`nFAILED - fix the errors above (exit $code)."
}

exit $code
