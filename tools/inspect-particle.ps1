# Parses one .particle.json exactly as the runtime does and reports what it found.
#
# Use when an effect "does not play": it shows whether the file is rejected outright, which
# components are ignored, and - most usefully - the evaluated numbers that decide visibility
# (particle count, lifetime, size). An effect whose own values come out zero looks broken but is
# behaving exactly as authored.
#
#   tools\inspect-particle.ps1 <path to .particle.json>

param([Parameter(Mandatory = $true)][string]$File)

$ErrorActionPreference = "Stop"

$project  = Split-Path -Parent $PSScriptRoot
# The repo (this script's parent tree) and the local-only dev environment (MCreator install) are
# sibling folders under the project root - see docs/DEVELOPMENT.md.
$localRoot = Join-Path (Split-Path -Parent $project) "local"
$mcreator  = Join-Path $localRoot "mcreator"
$out       = Join-Path $env:TEMP "kashi-inspect"

$javac = Join-Path $mcreator "jdk\bin\javac.exe"
$java  = Join-Path $mcreator "jdk\bin\java.exe"
$gson  = Get-ChildItem (Join-Path $mcreator "lib") -Filter "gson-*.jar" | Select-Object -First 1

if (-not (Test-Path $File)) { throw "not found: $File" }

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Path $out -Force | Out-Null

$sources = @()
$sources += Get-ChildItem (Join-Path $project "core\src\main\java") -Recurse -Filter "*.java" | ForEach-Object { $_.FullName }
$sources += (Join-Path $project "core\src\test\java\net\kashi\particles\core\ParticleInspector.java")

& $javac -encoding UTF-8 -proc:none -nowarn -classpath $gson.FullName -d $out $sources
if ($LASTEXITCODE -ne 0) { throw "inspector failed to compile" }

& $java -classpath "$out;$($gson.FullName)" net.kashi.particles.core.ParticleInspector (Resolve-Path $File)
exit $LASTEXITCODE
