# Compiles and runs the dependency-free core tests (parser, and later the MoLang evaluator).
#
# Uses the JDK and gson that ship with MCreator, so there is nothing extra to install and the
# core is checked against exactly the gson version it will meet at runtime.
#
# Build output goes to the local temp dir on purpose: the project lives on a Google Drive
# shared drive, and writing thousands of .class files there would churn the sync client.

$ErrorActionPreference = "Stop"

$mcreator = "G:\Drives compartilhados\WESLEY\01 - MCreator20261"
$project  = Split-Path -Parent $PSScriptRoot
$out      = Join-Path $env:TEMP "kashi-particles-build"

$javac = Join-Path $mcreator "jdk\bin\javac.exe"
$java  = Join-Path $mcreator "jdk\bin\java.exe"
$gson  = Get-ChildItem (Join-Path $mcreator "lib") -Filter "gson-*.jar" | Select-Object -First 1

if (-not (Test-Path $javac)) { throw "JDK not found at $javac" }
if (-not $gson)              { throw "gson jar not found in $mcreator\lib" }

if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Path $out -Force | Out-Null

$sources = Get-ChildItem (Join-Path $project "core\src") -Recurse -Filter "*.java" | ForEach-Object { $_.FullName }

Write-Host "Compiling $($sources.Count) files against $($gson.Name)..."
& $javac -encoding UTF-8 -classpath $gson.FullName -d $out $sources
if ($LASTEXITCODE -ne 0) { throw "compilation failed" }

$fixture = Join-Path $project "core\src\test\resources\wind_3_1_p.particle.json"
$classpath = "$out;$($gson.FullName)"
$failed = $false

Write-Host "`n--- MolangEvaluatorTest ---"
& $java -classpath $classpath net.kashi.particles.core.molang.MolangEvaluatorTest
if ($LASTEXITCODE -ne 0) { $failed = $true }

Write-Host "`n--- ParserSmokeTest ---"
& $java -classpath $classpath net.kashi.particles.core.ParserSmokeTest $fixture
if ($LASTEXITCODE -ne 0) { $failed = $true }

if ($failed) { exit 1 }
Write-Host "`nAll core tests passed."
