# Turns the runtime sources into MCreator templates and regenerates the element definition, for
# every generator this plugin supports.
#
# The mod-side runtime (core parser + MoLang evaluator + particle engine) is plain Java under the
# fixed package net.kashi.particles.*, so it ships to a user's mod almost verbatim: each .java
# becomes a .java.ftl, and the plugin emits them as global_templates whenever the workspace has at
# least one KASHI Particle element.
#
# Two generators, one shared source tree: runtime/ (plus core/) is the single source of truth for
# every file both generators need unchanged. A generator can override individual files via its own
# overlay directory (see $generators below) - as of this writing that is only KashiParticleAPI.java
# and KashiRenderType.java for neoforge-1.21.8, whose real API diverges from neoforge-1.21.1 (see
# docs/ARCHITECTURE.md). Everything else is templated identically for both from the same source.
#
# Only one thing is parameterised in the Java itself - the mod id, which must be a compile-time
# constant because @EventBusSubscriber(modid = ...) needs one.
#
# Run this after changing anything under core/, runtime/, or a generator's overlay directory, then
# rebuild the plugin.

$ErrorActionPreference = "Stop"

$project = Split-Path -Parent $PSScriptRoot

# One entry per supported generator. "Overlay" is a directory laid out just like runtime/ (i.e.
# <Overlay>/src/main/java/net/kashi/particles/runtime/*.java) - any file it contains is used in
# place of the one under runtime/ for that generator only; every other file comes from core/ and
# runtime/ unchanged. $null means no overlay - every file comes from the shared source.
$generators = @(
    [pscustomobject]@{ Name = "neoforge-1.21.1"; Overlay = $null },
    [pscustomobject]@{ Name = "neoforge-1.21.8"; Overlay = "runtime-1.21.8" }
)

# The dev mod id used while testing in the workspace; replaced by the freemarker variable.
$devModId = "kashi_particle_test"

$sourceRoots = @(
    (Join-Path $project "core\src\main\java"),
    (Join-Path $project "runtime\src\main\java")
)

foreach ($root in $sourceRoots) {
    if (-not (Test-Path $root)) { throw "source root not found: $root" }
}

# Authoring-time only: these are compiled into the plugin so the import wizard can use them, but
# they never run inside a user's mod and shipping them would be dead weight in every generated jar.
$notShipped = @("ParticleDiagnostics.java")

foreach ($gen in $generators) {
    $generator = Join-Path $project "src\$($gen.Name)"
    $outDir    = Join-Path $generator "templates\kashiparticle\runtime"

    if (-not (Test-Path $generator)) {
        throw "generator folder not found: $generator (create src\$($gen.Name)\ first)"
    }

    $overlayRoot = $null
    if ($gen.Overlay) {
        $overlayRoot = Join-Path $project "$($gen.Overlay)\src\main\java"
        if (-not (Test-Path $overlayRoot)) { throw "overlay root not found: $overlayRoot" }
    }

    if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null

    $emitted = @()

    foreach ($root in $sourceRoots) {
        foreach ($file in Get-ChildItem $root -Recurse -Filter "*.java") {
            if ($notShipped -contains $file.Name) { continue }

            $relative = $file.FullName.Substring($root.Length + 1)   # net\kashi\particles\...\X.java
            $target   = Join-Path $outDir ($relative -replace "\.java$", ".java.ftl")

            New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force | Out-Null

            # An overlay file with the same relative path wins over the shared one - this is the
            # only place a generator's output can differ from another's.
            $sourceFile = $file.FullName
            if ($overlayRoot) {
                $overlayFile = Join-Path $overlayRoot $relative
                if (Test-Path $overlayFile) { $sourceFile = $overlayFile }
            }

            $code = Get-Content $sourceFile -Raw -Encoding UTF8

            # Freemarker would eat any of these as its own syntax rather than passing them through
            # as literal Java text: ${...} interpolation, <#...> directives, and #{...} -
            # FreeMarker's legacy numerical-interpolation shorthand, which is easy to hit by
            # accident in an SLF4J log line like "call #{}" (the "#" plus a brace pair is exactly
            # that syntax). This one cost a real MCreator freeze to find: it only breaks at
            # code-generation time, not at javac time, so check-mod-compile.ps1 cannot catch it -
            # only regenerating actually does.
            if ($code -match '\$\{' -or $code -match '<#' -or $code -match '#\{') {
                throw "$($file.Name) ($($gen.Name)) contains freemarker syntax and cannot be templated as-is"
            }

            $before = $code
            $code = $code.Replace("`"$devModId`"", '"${modid}"')

            # String.Replace() is a silent no-op if $devModId is not found in this file - which is
            # exactly what happens if the dev workspace's own mod id ever changes without updating
            # $devModId here. The one file that MUST contain it is KashiParticlesRuntime.java,
            # whose MODID constant every generated mod's particle type, event bus subscription and
            # packet registration all key off. Ship that unreplaced and every mod built from this
            # plugin would silently register itself under "kashi_particle_test" - invisible in
            # THIS workspace (its own mod id happens to already be that string) and broken in
            # every other one.
            if ($file.Name -eq "KashiParticlesRuntime.java" -and $code -eq $before) {
                throw "expected `"$devModId`" in $($file.Name) ($($gen.Name)) to be replaced " +
                    "with the modid placeholder, but nothing changed - update `$devModId in " +
                    "this script to match the dev workspace's actual mod id"
            }

            # WriteAllText, not Set-Content: PowerShell 5.1 writes UTF-8 WITH a BOM, which would
            # end up at the top of every generated .java and make javac fail on "illegal character".
            [System.IO.File]::WriteAllText($target, $code)

            $emitted += [pscustomobject]@{
                Template = ("kashiparticle/runtime/" + ($relative -replace "\\", "/" -replace "\.java$", ".java.ftl"))
                Name     = ("@SRCROOT/" + ($relative -replace "\\", "/"))
            }
        }
    }

    Write-Host "[$($gen.Name)] templated $($emitted.Count) runtime source files"

    # --- regenerate this generator's element definition so templates and definition never drift apart ---

    $lines = @()
    $lines += "# GENERATED by tools\make-runtime-templates.ps1 - do not edit by hand."
    $lines += "#"
    $lines += "# Declares the ""KASHI Particle"" element for the $($gen.Name) generator. Per element we"
    $lines += "# emit the imported .particle.json as a mod resource; the texture is handled by MCreator"
    $lines += "# itself (imported as a PARTICLE texture). The global templates carry the shared runtime that"
    $lines += "# reads and plays those files, generated once whenever any KASHI Particle element exists."
    $lines += "templates:"
    $lines += "  - template: kashiparticle/particle.json.ftl"
    $lines += "    writer: file"
    $lines += "    name: ""@MODASSETSROOT/kashi_particles/@registryname.particle.json"""
    $lines += ""
    $lines += "global_templates:"
    $lines += "  - template: kashiparticle/KashiParticleEffects.java.ftl"
    $lines += "    name: ""@SRCROOT/net/kashi/particles/runtime/KashiParticleEffects.java"""

    foreach ($entry in $emitted) {
        $lines += "  - template: $($entry.Template)"
        $lines += "    name: ""$($entry.Name)"""
    }

    # No localizationkeys: a KASHI Particle has no in-game display name to translate, and mapping
    # one to a field the element does not have makes MCreator log
    # "Failed to parse values for key ... NoSuchFieldException: name" on every regeneration.

    [System.IO.File]::WriteAllLines((Join-Path $generator "kashiparticle.definition.yaml"), $lines)

    Write-Host "[$($gen.Name)] regenerated kashiparticle.definition.yaml ($($emitted.Count + 1) global templates)"
}
