# Development

## Why this isn't the standard MCreator plugin Gradle workflow

The [official plugin template](https://github.com/MCreator/DemoJavaPlugin) builds against a
Gradle project pointed at MCreator's own source tree (`mcreator_path` in `gradle.properties`).
This repo doesn't use that, for one concrete reason: **`net.mcreator.*` is not shipped as
`.jar`s under a `lib/` folder — it lives inside `mcreator.exe` itself**, which is a plain JAR
wrapped by [launch4j](https://launch4j.sourceforge.net/). `tools/build-plugin.ps1` compiles
directly against that exe as a classpath entry (`javac` reads it as a zip; renaming it to `.jar`
first does *not* work — see the comment at the top of that script for why).

Gradle is also actively avoided for the mod-side dev loop: this project lives on a Google Drive
shared drive, and a NeoForge/NeoGradle `neoform` decompile step under a constrained heap on a
network drive is slow and prone to stalling. `tools/check-mod-compile.ps1` gets the same
"does this compile against the real Minecraft + NeoForge API" answer in seconds by pointing
`javac` straight at the workspace's already-built moddev "merged" jar plus its Gradle module
cache — no daemon, no decompile.

## Layout

```
core/       Pure-Java parser + MoLang compiler/evaluator. No MCreator or Minecraft dependency.
            Used by BOTH the wizard (import-time validation/diagnostics) and, via a straight
            source copy, the generated mod's runtime. This is the one source of truth for parsing.
runtime/    The mod-side runtime: particle engine, render types, the debug command, event
            runner. Plain Java under the fixed package net.kashi.particles.*, written once and
            templated almost verbatim into every generated mod (see make-runtime-templates.ps1).
            Shared by every generator; a few files that genuinely differ between them (real
            NeoForge API differences, not guessed - see docs/ARCHITECTURE.md) live in a per-
            generator overlay directory (runtime-1.21.8/, and more as later generators need one)
            instead of a second copy of the whole tree.
src/        The actual MCreator plugin payload: plugin.json, lang strings, procedure block
            definitions, each generator's own (neoforge-1.21.1/, neoforge-1.21.8/, ...) templates
            and definition.yaml, themes (element icon). Zipped as-is into the plugin.
src-java/   The plugin's own Java: the mod element type, its wizard GUI, the plugin entry point.
            Compiled against EVERY supported MCreator install's own mcreator.exe (see above) -
            the source is identical either way, but each is compiled and zipped separately so a
            real net.mcreator.* API difference between MCreator versions shows up as a build
            error instead of shipping a zip that only happens to work against one of them.
tools/      Every dev script below.
```

## Prerequisites

This repo (`github/`) is one of two sibling folders under a project root — the other,
conventionally named `local/`, holds everything the scripts below need that isn't tracked in
version control:

```
<project root>/
├── github/     <- this repo
└── local/
    ├── mcreator/                 <- your MCreator 2026.1 install (JDK 21)
    ├── 02 - MCreator20262/       <- your MCreator 2026.2 install (JDK 25)
    └── workspace/
        ├── kashi_particle_test/   <- dev/test workspace, NeoForge 1.21.1, MCreator 2026.1
        ├── teste_vinte_oito/      <- dev/test workspace, NeoForge 1.21.8, MCreator 2026.1
        ├── true_particle_test/    <- dev/test workspace, NeoForge 1.21.1, MCreator 2026.2
        ├── seis_um/               <- dev/test workspace, NeoForge 26.1.2, MCreator 2026.2
        └── seis_dois/             <- dev/test workspace, NeoForge 26.2, MCreator 2026.2
```

- **Two local MCreator installs, each fully isolated** (`mcreator.exe` directly inside it, own
  `jdk/`, own `plugins/`) — never the WESLEY-shared installs one drive level up, so this project's
  plugin dev never interferes with (or is broken by) other MCreator projects on the same machine.
  Bring your own; every script that needs one (`tools/build-plugin.ps1`,
  `tools/check-mod-compile.ps1`, `tools/run-core-tests.ps1`) resolves both as `../local/mcreator`
  and `../local/02 - MCreator20262` relative to this repo, and loops over both. The two installs
  are **not interchangeable**: 2026.1 bundles JDK 21 and offers `generator-1.21.1`/
  `generator-1.21.8`; 2026.2 bundles JDK 25 (a real requirement of its generators' own
  `build.gradle`, not a MCreator preference) and offers `generator-1.21.1` again plus the newer
  `generator-26.1.x` (real generator id `neoforge-26.1.2`) and `generator-26.2.x` (real generator
  id `neoforge-26.2`) - see docs/ARCHITECTURE.md for what's confirmed to differ API-wise.
- **One dev/test MCreator workspace per (generator, MCreator install) pair this plugin supports**
  — `tools/check-mod-compile.ps1` and `tools/sync-core-to-workspace.ps1` both hardcode the exact
  workspace list, each tagged with which install to type-check it against. Open and build each in
  its MCreator at least once first, so its Gradle moddev "merged" jar and resolved classpath exist
  on disk. If you only work on one generator day-to-day, the other workspaces can be left as-is -
  both scripts skip a workspace folder that doesn't exist.
  - `neoforge-1.21.1`/`neoforge-1.21.8` write their classpath to `build/moddev/
    clientLegacyClasspath.txt` after one MCreator build - `check-mod-compile.ps1` just reads it
    (`ClasspathMode = "legacy"`).
  - `neoforge-26.1.2`/`neoforge-26.2`'s newer moddev Gradle plugin does not write that file at all
    (`ClasspathMode = "gradle"`) - `check-mod-compile.ps1` resolves it instead by actually running
    Gradle once (`gradlew --init-script tools/kashi-print-classpath.init.gradle ... help`, with
    `JAVA_HOME` pointed at that workspace's own install), caching the result at `build/moddev/
    kashiResolvedClasspath.txt` so every check after the first is still pure `javac`. See that
    `.gradle` file's own comments for two non-obvious things it needs
    (`--no-configuration-cache`, and why the classpath has to be captured in `afterEvaluate` rather
    than inside a task action).
- PowerShell and Python 3 with `numpy` (only needed for `optimize-textures.py`, which is offline
  tooling, not part of the shipped runtime).

None of this is a hard requirement of the *layout* — every script computes these paths from its
own location, so a different project-root/sibling-folder arrangement works too as long as you
update the `$localRoot`/`LOCAL_ROOT` line near the top of each script accordingly.

## Build pipeline

Run in this order after changing anything under `core/` or `runtime/`:

1. **`tools/run-core-tests.ps1`** — compiles and runs the dependency-free core test suite
   (MoLang evaluator + parser smoke tests) against the JDK and gson each supported MCreator
   install ships (both JDK 21 and JDK 25, see Prerequisites above), so nothing extra to install
   and the exact gson version the runtime will meet under either toolchain. Fast; run this first,
   always.
2. **`tools/sync-core-to-workspace.ps1`** — copies `core/` and `runtime/` into each dev
   workspace's source tree (applying that workspace's generator overlay, if it has one), so each
   workspace can compile and run them for manual in-game testing.
3. **`tools/check-mod-compile.ps1`** — type-checks each workspace's copy against that generator's
   real Minecraft + NeoForge API (via the workspace's own merged jar + resolved classpath),
   without invoking Gradle.
4. **`tools/make-runtime-templates.ps1`** — turns `runtime/` (plus each generator's overlay) into
   the `.java.ftl` templates under `src/<generator>/templates/kashiparticle/runtime/` and
   regenerates that generator's `kashiparticle.definition.yaml`, once per generator. The one thing
   it parameterises in the Java itself is the mod id (a compile-time constant in the generated
   code) — read the comment at the top before changing that logic.
5. **`tools/build-plugin.ps1`** — compiles `src-java/` + `core/` against each supported MCreator
   install's own `mcreator.exe`, zips `src/` plus that install's compiled classes into the plugin,
   and installs it into that install's `plugins/` folder. Repeats per install (see Prerequisites
   above), not just once.

Other tools, used as needed rather than every change:

- **`tools/validate-particles.ps1 <folder>`** — batch-checks a folder of `.particle.json` files
  against the parser before importing them; lists what won't load and why.
- **`tools/inspect-particle.ps1 <file>`** — parses one file exactly as the runtime does and
  prints the evaluated numbers that decide visibility (particle count, lifetime, size) — for the
  "this effect doesn't play but nothing looks wrong" case.
- **`tools/make-element-icon.ps1`** — regenerates the 64×64 element-type icon shipped under
  `src/themes/*/images/mod_types/`. MCreator refuses to open a workspace with a mod element type
  missing its icon, so re-run this if you rename the element type.
- **`tools/import-pack.py`** / **`tools/make-batch-items.py`** — bulk dev/test helpers that
  write mod elements, procedures and items directly into a workspace's `elements/` folder from a
  whole local pack of `.particle.json` files, for regression-testing many effects at once instead
  of clicking through the wizard by hand. Not part of the shipped plugin; point them at your own
  local pack folder.
- **`tools/optimize-textures.py <folder>`** — losslessly shrinks a pack's PNGs before import
  (re-deflate + palette indexing where it fits, both verified byte/pixel-identical before
  writing). Offline tooling only.

## Testing in-game

After the pipeline above, open (or switch to) your dev workspace in MCreator, regenerate code,
and run the client. MCreator only regenerates a mod element's Java when that element is opened or
edited in MCreator's UI — not on every "Run client" — so if you changed shared runtime code and
nothing seems to have updated, that's almost always the fix.

A change to a file that's shared between generators (the common case) only needs testing in one
workspace. A change to a generator-specific overlay file, or anything render-related, is worth
testing in **both** `kashi_particle_test` and `teste_vinte_oito` — they exercise genuinely
different Minecraft/NeoForge code paths, not just the same code on a different version number.
