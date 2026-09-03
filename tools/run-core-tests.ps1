# Compiles and runs the dependency-free core tests (parser, and later the MoLang evaluator).
#
# Uses the JDK and gson that ship with MCreator, so there is nothing extra to install and the
# core is checked against exactly the gson version it will meet at runtime.
#
# Two JDKs now, not one: core/ ships into mods built by every generator this plugin supports, and
# those generators split into two toolchains - Java 21 (neoforge-1.21.1, neoforge-1.21.8) and Java
# 25 (neoforge-26.1.2, neoforge-26.2 - see docs/DEVELOPMENT.md). Compiling and running under only
# one would miss a real incompatibility with the other.
#
# Build output goes to the local temp dir on purpose: the project lives on a Google Drive shared
# drive, and writing thousands of .class files there would churn the sync client.

$ErrorActionPreference = "Stop"

$project   = Split-Path -Parent $PSScriptRoot
# The repo (this script's parent tree) and the local-only dev environment (MCreator installs) are
# sibling folders under the project root - see docs/DEVELOPMENT.md. This project always uses its
# own isolated MCreator copies under local/, never the WESLEY-shared installs - see the
# [[ambiente-de-teste-isolado]] memory for why (this script used to point at the shared one; fixed
# as part of the V3.0.0 port, when a second JDK made the inconsistency worth noticing).
$localRoot = Join-Path (Split-Path -Parent $project) "local"

# One entry per local MCreator install this plugin supports - same list as build-plugin.ps1 and
# check-mod-compile.ps1.
$installs = @(
    [pscustomobject]@{ Label = "2026.1 (JDK 21)"; Root = Join-Path $localRoot "mcreator" },
    [pscustomobject]@{ Label = "2026.2 (JDK 25)"; Root = Join-Path $localRoot "02 - MCreator20262" }
)

$overallFailed = $false

foreach ($install in $installs) {
    $mcreator = $install.Root
    if (-not (Test-Path $mcreator)) {
        Write-Host "[$($install.Label)] install not found at $mcreator - skipped"
        continue
    }

    $out   = Join-Path $env:TEMP "kashi-particles-build-$($install.Label -replace '[^\w.]', '_')"
    $javac = Join-Path $mcreator "jdk\bin\javac.exe"
    $java  = Join-Path $mcreator "jdk\bin\java.exe"
    $gson  = Get-ChildItem (Join-Path $mcreator "lib") -Filter "gson-*.jar" | Select-Object -First 1

    if (-not (Test-Path $javac)) { throw "[$($install.Label)] JDK not found at $javac" }
    if (-not $gson)              { throw "[$($install.Label)] gson jar not found in $mcreator\lib" }

    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    New-Item -ItemType Directory -Path $out -Force | Out-Null

    $sources = Get-ChildItem (Join-Path $project "core\src") -Recurse -Filter "*.java" | ForEach-Object { $_.FullName }

    Write-Host "[$($install.Label)] compiling $($sources.Count) files against $($gson.Name)..."
    & $javac -encoding UTF-8 -classpath $gson.FullName -d $out $sources
    if ($LASTEXITCODE -ne 0) { throw "[$($install.Label)] compilation failed" }

    $fixture = Join-Path $project "core\src\test\resources\wind_3_1_p.particle.json"
    $classpath = "$out;$($gson.FullName)"

    Write-Host "[$($install.Label)] --- MolangEvaluatorTest ---"
    & $java -classpath $classpath net.kashi.particles.core.molang.MolangEvaluatorTest
    if ($LASTEXITCODE -ne 0) { $overallFailed = $true }

    Write-Host "[$($install.Label)] --- ParserSmokeTest ---"
    & $java -classpath $classpath net.kashi.particles.core.ParserSmokeTest $fixture
    if ($LASTEXITCODE -ne 0) { $overallFailed = $true }

    Write-Host "[$($install.Label)] done.`n"
}

if ($overallFailed) { exit 1 }
Write-Host "All core tests passed under every installed JDK."
