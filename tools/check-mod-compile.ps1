# Type-checks the mod-side runtime WITHOUT invoking a real gradle build, for every generator this
# plugin supports.
#
# gradle's neoform step is heavy and, on this network drive with the workspace's 1 GB heap, prone
# to stalling, so this avoids repeating it. Older generators (neoforge-1.21.1, neoforge-1.21.8)
# already have their full compile classpath sitting on disk after one MCreator build - the moddev
# "merged" jar plus build/moddev/clientLegacyClasspath.txt - so those are just read directly.
# Newer ones (neoforge-26.1.2, neoforge-26.2) don't write that file at all; for those the
# classpath is resolved by actually asking Gradle once (see ClasspathMode below and
# kashi-print-classpath.init.gradle), then cached on disk so every check after the first is still
# just javac, no daemon involved.
#
# This does NOT produce a runnable mod - it only checks that the code compiles against the real
# API. Building and running still goes through MCreator.

$ErrorActionPreference = "Stop"

$project   = Split-Path -Parent $PSScriptRoot
# The repo (this script's parent tree) and the local-only dev environment (MCreator installs,
# test workspaces) are sibling folders under the project root - see docs/DEVELOPMENT.md.
$localRoot = Join-Path (Split-Path -Parent $project) "local"

# One entry per local MCreator install this plugin supports - each workspace below points at one
# by Label. Matches build-plugin.ps1's $installs list. Each install bundles its own JDK, and they
# are NOT interchangeable: 2026.2's generators require Java 25, 2026.1's require Java 21 (see
# docs/DEVELOPMENT.md) - javac from the wrong install can't even read the other's class files.
$installs = @{
    "2026.1" = Join-Path $localRoot "mcreator"
    "2026.2" = Join-Path $localRoot "02 - MCreator20262"
}

# One entry per test workspace - same list as sync-core-to-workspace.ps1, plus which install's
# JDK to type-check it with. "Label" is only for the summary line. "ClasspathMode" picks how the
# rest of the classpath (beyond the merged/patched Minecraft jar) is found:
#   "legacy" - read the workspace's own build/moddev/clientLegacyClasspath.txt, which
#              neoforge-1.21.1/neoforge-1.21.8's older moddev Gradle plugin writes to disk.
#   "gradle" - that file does not exist for neoforge-26.1.2/neoforge-26.2 (their newer moddev
#              plugin resolves the classpath without ever writing it anywhere) - resolved instead
#              by actually asking Gradle, once, via kashi-print-classpath.init.gradle. See that
#              file for why it needs --no-configuration-cache and can't just be a normal task.
$workspaces = @(
    [pscustomobject]@{ Name = "kashi_particle_test"; Label = "NeoForge 1.21.1 (MCreator 2026.1)"; Install = "2026.1"; ClasspathMode = "legacy" },
    [pscustomobject]@{ Name = "teste_vinte_oito";    Label = "NeoForge 1.21.8 (MCreator 2026.1)"; Install = "2026.1"; ClasspathMode = "legacy" },
    [pscustomobject]@{ Name = "true_particle_test";  Label = "NeoForge 1.21.1 (MCreator 2026.2)"; Install = "2026.2"; ClasspathMode = "legacy" },
    [pscustomobject]@{ Name = "seis_um";             Label = "NeoForge 26.1.2 (MCreator 2026.2)"; Install = "2026.2"; ClasspathMode = "gradle" },
    [pscustomobject]@{ Name = "seis_dois";           Label = "NeoForge 26.2 (MCreator 2026.2)";   Install = "2026.2"; ClasspathMode = "gradle" }
)

$overallCode = 0

foreach ($ws in $workspaces) {
    $workspace = Join-Path $localRoot "workspace\$($ws.Name)"
    if (-not (Test-Path $workspace)) {
        Write-Host "[$($ws.Name)] workspace not found - skipped"
        continue
    }

    $mcreator = $installs[$ws.Install]
    if (-not $mcreator) { throw "[$($ws.Name)] unknown install label `"$($ws.Install)`"" }

    $javac = Join-Path $mcreator "jdk\bin\javac.exe"
    if (-not (Test-Path $javac)) { throw "[$($ws.Name)] JDK not found at $javac (install `"$($ws.Install)`")" }

    $out = Join-Path $env:TEMP "kashi-modcheck-$($ws.Name)"

    if ($ws.ClasspathMode -eq "gradle") {
        # neoforge-26.1.2/neoforge-26.2's moddev plugin never writes a classpath file to disk (see
        # kashi-print-classpath.init.gradle) - and unlike the legacy mode below, the resolved
        # compileClasspath it hands back already includes the correct Minecraft+NeoForge jar
        # itself (build/moddev/artifacts/minecraft-patched-<version>.jar - NOT the same file as
        # the similarly-named "-merged.jar", which is bigger and meant for running the game, not
        # compiling against it). No separate merged-jar step needed for this mode.
        $resolvedFile = Join-Path $workspace "build\moddev\kashiResolvedClasspath.txt"

        if (-not (Test-Path $resolvedFile)) {
            Write-Host "[$($ws.Name)] no cached classpath - resolving via gradle (one-off; slower than the other workspaces)..."

            $gradlew = Join-Path $workspace "gradlew.bat"
            if (-not (Test-Path $gradlew)) { throw "[$($ws.Name)] $gradlew not found" }

            $initScript = Join-Path $PSScriptRoot "kashi-print-classpath.init.gradle"
            $previousJavaHome = $env:JAVA_HOME
            $env:JAVA_HOME = $mcreator + "\jdk"

            Push-Location $workspace
            try {
                & $gradlew --init-script $initScript "-DkashiOut=$resolvedFile" help -q --no-configuration-cache
                $gradleCode = $LASTEXITCODE
            } finally {
                Pop-Location
                $env:JAVA_HOME = $previousJavaHome
            }

            if ($gradleCode -ne 0 -or -not (Test-Path $resolvedFile)) {
                throw "[$($ws.Name)] gradle classpath resolution failed (exit $gradleCode) - see output above"
            }
        }

        $deps = Get-Content $resolvedFile
        $classpath = $deps -join ";"
        $jarLabel = "$($deps.Count) jars (gradle-resolved)"
    } else {
        # The merged jar is authoritative for Minecraft + NeoForge classes; everything else fills
        # in the library dependencies. Matched by pattern rather than a hardcoded version, since
        # the exact NeoForge build number is whatever the workspace's generator resolved and moves
        # independently of this script.
        $artifactsDir = Join-Path $workspace "build\moddev\artifacts"
        $merged = Get-ChildItem $artifactsDir -Filter "neoforge-*-merged.jar" -EA SilentlyContinue |
                  Select-Object -First 1

        if (-not $merged) {
            throw "[$($ws.Name)] merged jar not found under $artifactsDir - open/build the workspace in MCreator once first"
        }

        # The rest of the classpath (FML loader, joml, brigadier, DataFixerUpper, gson, netty, ...)
        # is read from this workspace's OWN Gradle-resolved classpath, not scanned from the shared
        # ~/.mcreator/gradle module cache directly. Test workspaces share that cache (see
        # docs/DEVELOPMENT.md), so once a second NeoForge version had been downloaded into it, a
        # blind scan picked up two different versions of some libraries (fastutil, notably) and
        # javac resolved symbols against the wrong one - "cannot find symbol" for methods that do
        # exist, just not in the jar javac happened to pick first. This file is what Gradle itself
        # resolved for this exact workspace, so it cannot have that problem.
        $classpathFile = Join-Path $workspace "build\moddev\clientLegacyClasspath.txt"
        if (-not (Test-Path $classpathFile)) {
            throw "[$($ws.Name)] $classpathFile not found - open/build the workspace in MCreator once first"
        }

        $deps = Get-Content $classpathFile
        $classpath = (@($merged.FullName) + $deps) -join ";"
        $jarLabel = "$($deps.Count + 1) jars ($($merged.Name))"
    }

    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    New-Item -ItemType Directory -Path $out -Force | Out-Null

    $sources = Get-ChildItem (Join-Path $workspace "src\main\java\net\kashi") -Recurse -Filter "*.java" |
               ForEach-Object { $_.FullName }

    Write-Host "[$($ws.Name)] type-checking $($sources.Count) files against $jarLabel..."

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
