# Type-checks the mod-side runtime WITHOUT gradle, for every generator this plugin supports.
#
# gradle's neoform step is heavy and, on this network drive with the workspace's 1 GB heap, prone
# to stalling. But the compile classpath already exists on disk: the moddev "merged" jar holds all
# of Minecraft + the NeoForge API, and every other dependency (FML loader, joml, brigadier,
# DataFixerUpper, gson, netty) is listed in the workspace's own build/moddev/
# clientLegacyClasspath.txt, which Gradle already resolved. Point javac at all of them and we get
# compile errors in seconds, no daemon involved.
#
# This does NOT produce a runnable mod - it only checks that the code compiles against the real
# API. Building and running still goes through MCreator.

$ErrorActionPreference = "Stop"

$project   = Split-Path -Parent $PSScriptRoot
# The repo (this script's parent tree) and the local-only dev environment (MCreator install,
# test workspaces) are sibling folders under the project root - see docs/DEVELOPMENT.md.
$localRoot = Join-Path (Split-Path -Parent $project) "local"
$mcreator  = Join-Path $localRoot "mcreator"

$javac = Join-Path $mcreator "jdk\bin\javac.exe"
if (-not (Test-Path $javac)) { throw "JDK not found at $javac" }

# One entry per test workspace - same list as sync-core-to-workspace.ps1. "Label" is only for the
# summary line.
$workspaces = @(
    [pscustomobject]@{ Name = "kashi_particle_test"; Label = "NeoForge 1.21.1" },
    [pscustomobject]@{ Name = "teste_vinte_oito";    Label = "NeoForge 1.21.8" }
)

$overallCode = 0

foreach ($ws in $workspaces) {
    $workspace = Join-Path $localRoot "workspace\$($ws.Name)"
    if (-not (Test-Path $workspace)) {
        Write-Host "[$($ws.Name)] workspace not found - skipped"
        continue
    }

    $out = Join-Path $env:TEMP "kashi-modcheck-$($ws.Name)"

    # The merged jar is authoritative for Minecraft + NeoForge classes; everything else fills in
    # the library dependencies. Matched by pattern rather than a hardcoded version, since the
    # exact NeoForge build number is whatever the workspace's generator resolved and moves
    # independently of this script.
    $artifactsDir = Join-Path $workspace "build\moddev\artifacts"
    $merged = Get-ChildItem $artifactsDir -Filter "neoforge-*-merged.jar" -EA SilentlyContinue |
              Select-Object -First 1

    if (-not $merged) {
        throw "[$($ws.Name)] merged jar not found under $artifactsDir - open/build the workspace in MCreator once first"
    }

    # The rest of the classpath (FML loader, joml, brigadier, DataFixerUpper, gson, netty, ...) is
    # read from this workspace's OWN Gradle-resolved classpath, not scanned from the shared
    # ~/.mcreator/gradle module cache directly. Both test workspaces share that cache (see
    # docs/DEVELOPMENT.md), so once a second NeoForge version had been downloaded into it, a blind
    # scan picked up two different versions of some libraries (fastutil, notably) and javac
    # resolved symbols against the wrong one - "cannot find symbol" for methods that do exist, just
    # not in the jar javac happened to pick first. This file is what Gradle itself resolved for
    # this exact workspace, so it cannot have that problem.
    $classpathFile = Join-Path $workspace "build\moddev\clientLegacyClasspath.txt"
    if (-not (Test-Path $classpathFile)) {
        throw "[$($ws.Name)] $classpathFile not found - open/build the workspace in MCreator once first"
    }

    $deps = Get-Content $classpathFile
    $classpath = (@($merged.FullName) + $deps) -join ";"

    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    New-Item -ItemType Directory -Path $out -Force | Out-Null

    $sources = Get-ChildItem (Join-Path $workspace "src\main\java\net\kashi") -Recurse -Filter "*.java" |
               ForEach-Object { $_.FullName }

    Write-Host "[$($ws.Name)] type-checking $($sources.Count) files against $($deps.Count + 1) jars ($($merged.Name))..."

    # An @argfile, not a direct command line: with two workspaces sharing one gradle cache (see
    # docs/DEVELOPMENT.md), that cache now holds both NeoForge versions' dependencies, and
    # $classpath alone is long enough to blow past Windows' CreateProcess argument limit ("O nome
    # do arquivo ou a extensão é muito grande" - a real failure hit while wiring up the second
    # workspace, not theoretical). javac reads an @file exactly like a longer command line without
    # that limit; every value that might contain a space (any path under this Drive) is quoted.
    #
    # javac's @argfile format unescapes backslashes inside quoted strings (it hit exactly this:
    # "workspace\teste..." came out with the \t read as a tab character, and every other backslash
    # silently eaten). Forward slashes sidestep that entirely - javac on Windows accepts them in
    # paths just like backslashes - so every path below is normalised before it's written out.
    $argfile = Join-Path $env:TEMP "kashi-modcheck-$($ws.Name).args"
    $classpathFwd = $classpath.Replace("\", "/")
    $outFwd = $out.Replace("\", "/")
    $sourcePathFwd = (Join-Path $workspace "src\main\java").Replace("\", "/")

    # The merged jar bundles a .java alongside the .class for at least some NeoForge classes (e.g.
    # RegisterEvent). Without an explicit -sourcepath, javac defaults it to the classpath - so it
    # finds those bundled sources, and TYPE-CHECKS them (not just compiles: -implicit:none only
    # suppresses writing their .class output, it does not stop javac reading and reporting errors
    # in them, confirmed by trying it first and getting the identical errors below). Those sources
    # then fail on transitive dependencies (org.jetbrains.annotations, notably) that are not on
    # this hand-assembled classpath and were never needed - a real Gradle build never compiles
    # NeoForge's own classes, only ours, and neither should this. Pointing -sourcepath at just this
    # workspace's own source tree (which is all we ever pass as actual source files) keeps the
    # merged jar as a class-file-only classpath entry, the way it is meant to be used here.
    $argLines = @("-encoding", "UTF-8", "-proc:none", "-nowarn",
            "-classpath", "`"$classpathFwd`"", "-sourcepath", "`"$sourcePathFwd`"", "-d", "`"$outFwd`"")
    $argLines += $sources | ForEach-Object { "`"$($_.Replace('\', '/'))`"" }
    [System.IO.File]::WriteAllLines($argfile, $argLines)

    # javac writes even its harmless notes ("uses a deprecated API") to stderr, and with
    # ErrorActionPreference = Stop PowerShell turns any native stderr line into a terminating
    # error - so a successful compile would abort this script before it could report success.
    # Relax the preference across the call only, and judge the result by the exit code, which is
    # what javac actually uses to signal failure.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $javac "@$argfile"
    $code = $LASTEXITCODE
    $ErrorActionPreference = $previous

    if ($code -eq 0) {
        Write-Host "[$($ws.Name)] OK - mod-side runtime compiles against the $($ws.Label) API.`n"
    } else {
        Write-Host "[$($ws.Name)] FAILED - fix the errors above (exit $code).`n"
        $overallCode = $code
    }
}

exit $overallCode
