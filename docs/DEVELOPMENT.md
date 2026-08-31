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
src/        The actual MCreator plugin payload: plugin.json, lang strings, procedure block
            definitions, the neoforge-1.21.1 generator's templates and definition.yaml, themes
            (element icon). Zipped as-is into the plugin.
src-java/   The plugin's own Java: the mod element type, its wizard GUI, the plugin entry point.
            Compiled against mcreator.exe (see above).
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
    ├── mcreator/     <- your MCreator install
    └── workspace/
        └── kashi_particle_test/   <- your dev/test workspace
```

- **`local/mcreator/`** — a local MCreator install (`mcreator.exe` directly inside it). Bring
  your own; every script that needs it (`tools/build-plugin.ps1`,
  `tools/check-mod-compile.ps1`, `tools/inspect-particle.ps1`,
  `tools/validate-particles.ps1`) resolves it as `../local/mcreator` relative to this repo.
- **`local/workspace/kashi_particle_test/`** — a dev/test MCreator workspace using the
  NeoForge 1.21.1 generator, with that exact folder name (`tools/check-mod-compile.ps1` and
  `tools/sync-core-to-workspace.ps1` hardcode it). Open and build it in MCreator at least once
  first, so its Gradle moddev "merged" jar and module cache exist on disk.
- PowerShell and Python 3 with `numpy` (only needed for `optimize-textures.py`, which is offline
  tooling, not part of the shipped runtime).

None of this is a hard requirement of the *layout* — every script computes these paths from its
own location, so a different project-root/sibling-folder arrangement works too as long as you
update the `$localRoot`/`LOCAL_ROOT` line near the top of each script accordingly.

## Build pipeline

Run in this order after changing anything under `core/` or `runtime/`:

1. **`tools/run-core-tests.ps1`** — compiles and runs the dependency-free core test suite
   (MoLang evaluator + parser smoke tests) against the JDK and gson MCreator itself ships, so
   nothing extra to install and the exact gson version the runtime will meet. Fast; run this
   first, always.
2. **`tools/sync-core-to-workspace.ps1`** — copies `core/` and `runtime/` into your dev
   workspace's source tree, so the workspace can compile and run them for manual in-game testing.
3. **`tools/check-mod-compile.ps1`** — type-checks that copy against the real Minecraft +
   NeoForge API (via the workspace's merged jar + Gradle cache), without invoking Gradle.
4. **`tools/make-runtime-templates.ps1`** — turns `runtime/` into the `.java.ftl` templates
   under `src/neoforge-1.21.1/templates/kashiparticle/runtime/` and regenerates
   `kashiparticle.definition.yaml`. The one thing it parameterises is the mod id (a compile-time
   constant in the generated code) — read the comment at the top before changing that logic.
5. **`tools/build-plugin.ps1`** — compiles `src-java/` + `core/` against `mcreator.exe`, zips
   `src/` plus the compiled classes into the plugin, and installs it into your local MCreator's
   `plugins/` folder.

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
