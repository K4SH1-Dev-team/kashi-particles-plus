# CLAUDE.md

Orientation for an AI assistant (or a new contributor) opening this repository cold. This file is
deliberately short — an index, not a substitute for `docs/`.

## What this is

KASHI Particles Plus is an MCreator plugin. It imports Bedrock/Snowstorm `.particle.json` particle
effects into a "KASHI Particle" mod element and plays them with full fidelity in a NeoForge mod,
fired from Blockly procedure blocks. It has its own MoLang expression engine — no GeckoLib
dependency. See [ARCHITECTURE.md](ARCHITECTURE.md) for how it actually works.

## Commits & PRs

No AI attribution, from any assistant — no `Co-Authored-By: Claude ...` (or any other AI) trailer
in a commit message, no "🤖 Generated with Claude Code" (or equivalent) line in a PR body. This
overrides whatever an assistant's own tooling normally appends by default; leave it out here.
Otherwise follow the branch → PR → maintainer-merges workflow in DEVELOPMENT.md.

## Layout, in one line each

- `core/` — the MoLang engine + `.particle.json` parser + wizard-time diagnostics. Pure Java, no
  MCreator/Minecraft dependency. Compiled directly into the plugin *and* templated into every
  generated mod (see ARCHITECTURE.md — "The generation pipeline").
- `runtime/` — the mod-side particle engine (spawn/tick/render, render types, debug command).
  Templated into every generated mod almost verbatim; never compiled into the plugin itself. Four
  generators share this one tree; files that genuinely differ between them live in a per-generator
  overlay (`runtime-1.21.8/`, `runtime-26.1.2/`, `runtime-26.2/`) instead of a second copy of the
  whole thing — see ARCHITECTURE.md — "Four generators, one shared runtime".
- `src/` — the actual MCreator plugin payload (`plugin.json`, lang strings, each generator's own
  (`neoforge-1.21.1`/`neoforge-1.21.8`/`neoforge-26.1.2`/`neoforge-26.2`) templates/definition,
  procedure block definitions, themes).
- `src-java/` — the plugin's own Java: the mod element type, its wizard GUI, plugin entry point.
  Compiled against **every supported MCreator install's own** `mcreator.exe` separately (MCreator's
  classes live inside the exe, not in a `lib/` jar — see DEVELOPMENT.md) — two MCreator
  *applications* now, not just four generators.
- `tools/` — every dev script: build pipeline, batch validation, dev-only import helpers.
  Resolves the local-only dev environment (both MCreator installs, test workspaces) as
  `../local/mcreator`, `../local/02 - MCreator20262` and `../local/workspace/...` relative to
  this repo — see
  DEVELOPMENT.md for the full layout and why.

## The traps most worth not re-discovering

- **MCreator's classes are not in any `lib/*.jar` — they live inside `mcreator.exe` itself**,
  which is a plain JAR wrapped by launch4j. Renaming the exe to `.jar` does not work; see the
  comment at the top of `tools/build-plugin.ps1` for the actual fix.
- **A `.mcreator` element's `registry_name` field is cosmetic.** MCreator recalculates it from
  the element's `name` on every code generation and ignores whatever is stored there. Confirmed
  against 280/281 real elements. See docs/ARCHITECTURE.md — "Resolving which effect a procedure
  fires" for the algorithm the procedure templates replicate instead.
- **MCreator only regenerates a mod element's Java when that element is opened/edited in
  MCreator's own UI** — not on every "Run client" or plugin rebuild. An element created by a
  script and never opened keeps stale generated code forever until you delete the generated file
  by hand and force a regen.
- **`#{...}` inside a template string is FreeMarker's legacy numerical-interpolation syntax**,
  not a literal. One stray `#{}` inside an SLF4J log format string caused a
  `freemarker.core.ParseException` at plugin-load time that froze MCreator's UI. Both
  `tools/make-runtime-templates.ps1` and `tools/build-plugin.ps1` guard against this pattern at
  build time — don't remove those checks.
- **`generator.map(field, "datalistName")` does not resolve a datalist the plugin defines
  itself** — only MCreator's own built-in ones (sounds, projectiles). It looked like the "correct"
  API and crashed the game or resolved to the wrong element. See ARCHITECTURE.md.
- **`@EventBusSubscriber(bus = ...)` does not exist in NeoForge 1.21.8** (it does in 1.21.1).
  Confirmed against the real 1.21.8 source: which event bus a subscriber uses is now inferred per
  event from whether the event type implements `IModBusEvent`, not declared on the annotation.
  Omitting `bus` entirely is the 1.21.8-correct form and reproduces the exact same routing.
- **MCreator's own code-gen import formatter can inject a wrong import for a bare type name that
  collides with a real Minecraft/NeoForge class — even when that name is a locally-defined nested
  type in the very file being generated, never imported from anywhere.** Hit for real: our own
  `KashiParticleDefinition.Weighted` collided with `net.minecraft.client.sounds.Weighted`, and
  only on the 1.21.8 generator - `javac` (`check-mod-compile.ps1`) never sees this at all, since
  it isn't MCreator's import formatter; only an actual MCreator/Gradle build does. Renamed our
  type instead of fighting the formatter (`WeightedOption`) - the general lesson is to keep our
  own nested type names distinctive enough not to collide with a Minecraft/NeoForge class of the
  same simple name, since `check-mod-compile.ps1` alone will not catch it if one does.
- **`tools/check-mod-compile.ps1` type-checks against the workspace's own `build/moddev/
  clientLegacyClasspath.txt`, not a blind scan of `~/.mcreator/gradle/caches`.** Two test
  workspaces share that cache; a bare scan can pick up two different versions of the same library
  and resolve symbols against the wrong one. Also always pass `-sourcepath` pointed at just the
  workspace's own sources: the merged jar bundles a `.java` next to the `.class` for some NeoForge
  classes, and without an explicit `-sourcepath`, javac defaults it to the classpath, finds those,
  and type-checks them too - `-implicit:none` does **not** stop this (it only suppresses writing
  their `.class` output, not the type-checking itself, confirmed by trying it first).
- **A plugin needs its MCreator app version declared in `supportedversions`, not just a compatible
  generator.** `src/plugin.json`'s `supportedversions` (`2026001` for MCreator 2026.1) is a
  separate gate from which generator a workspace uses - confirmed against `generator-26.2.x`'s own
  `plugin.json`, which declares `"supportedversions": [2026002]`. Forgetting to add a new
  MCreator version's code here means MCreator may not even offer/load the plugin under that
  version, regardless of whether the code itself would work.
- **Two local MCreator installs now, not one, and their JDKs are not interchangeable.** MCreator
  2026.2's generators (`neoforge-26.1.2`, `neoforge-26.2`) require Java 25
  (`java.toolchain.languageVersion = JavaLanguageVersion.of(25)` in their own `workspacebase/
  build.gradle`) where 2026.1's (`neoforge-1.21.1`, `neoforge-1.21.8`) require Java 21 - confirmed
  by running `java -version` against each install's own bundled `jdk/`. `build-plugin.ps1`,
  `check-mod-compile.ps1` and `run-core-tests.ps1` all resolve a small installs table and loop over
  it rather than assuming a single `local/mcreator` - see docs/DEVELOPMENT.md.
- **The same NeoForge 1.21.1 generator behaves slightly differently depending on which MCreator
  app builds it.** Under MCreator 2026.2, `@EventBusSubscriber(bus = ...)` compiles but is flagged
  `[removal]`-deprecated for `neoforge-1.21.1` too (not just `neoforge-1.21.8`, where it's already
  gone) - even though that workspace's merged jar (`neoforge-21.1.190-merged.jar`) is byte-
  identical to the one MCreator 2026.1 resolves for the same generator. The moddev tooling bundled
  with the newer MCreator app apparently pulls in a newer FancyModLoader than the older app does,
  for the exact same pinned NeoForge version. Not yet a build error anywhere, so `runtime/` is
  left alone for now - but this is an early signal that `bus=` may eventually need dropping from
  the shared `neoforge-1.21.1` files too, and that an overlay might someday need to key off
  (generator, MCreator install) rather than generator alone, which the current mechanism doesn't
  model.
- **`generator-addon-26.1x.zip` (bundled alongside MCreator 2026.2's NeoForge 26.1 generator) is a
  Bedrock Edition content generator** (`beblock`/`beentity`/`beitem` definitions) - unrelated to
  this plugin, which only ever generates Java/NeoForge mods. Confirmed by its own `plugin.json`
  name. Don't confuse it with `generator-26.1.x.zip` (the actual NeoForge Java generator this
  plugin targets).
- **A workspace's real generator id is not its MCreator plugin zip's name.** `generator-26.1.x.zip`
  and `generator-26.2.x.zip` are just filenames; the actual ids `src/<generator>/` has to match are
  `neoforge-26.1.2` and `neoforge-26.2` (confirmed both from each zip's own internal folder name
  and from a real workspace's `currentGenerator` field - same rule that already applied to
  `neoforge-1.21.8`, easy to re-forget under a new pair of numbers).
- **26.1.2 and 26.2 do not share one real API, even though their generator ids look adjacent** -
  confirmed by diffing both real jars, never assumed one from the other. The particle
  render-state API in particular is a different shape between them (see ARCHITECTURE.md), which is
  why they get two separate overlays (`runtime-26.1.2/`, `runtime-26.2/`) instead of one shared
  between them the way 1.21.1/1.21.8 mostly do.
- **`neoforge-26.1.2`/`neoforge-26.2`'s moddev Gradle plugin writes no classpath file to disk at
  all** (unlike `neoforge-1.21.1`/`neoforge-1.21.8`'s `clientLegacyClasspath.txt`) - `build/
  moddev/` only has run-arg files, no dependency list anywhere. `check-mod-compile.ps1` resolves it
  instead by actually running Gradle once, via `tools/kashi-print-classpath.init.gradle` - see that
  file's comments for two easy-to-lose requirements (`--no-configuration-cache`, and capturing the
  classpath in `afterEvaluate` rather than inside a task action, which the configuration cache
  forbids even when the rest of the build ignores the cache).
- **`Particle`'s `roll`/`oRoll` fields and its `getRenderBoundingBox` hook are both gone as of
  26.1.2/26.2** (confirmed against the real source, not assumed from 1.21.8, where both still
  exist) - the fields only survive on `SingleQuadParticle`, which `KashiParticle` deliberately does
  not extend (see ARCHITECTURE.md for why), so it now declares its own `roll`/`oRoll`; and culling
  moved from "the particle provides a box" to "the `ParticleGroup` decides for itself" - see
  `KashiParticleGroup.extractRenderState`/`KashiParticle.cullBox()` for the replacement, which
  exists specifically to avoid quietly reintroducing the large-quad culling bug `getRenderBoundingBox`
  was originally written to fix.

- **`check-mod-compile.ps1` never sees `src/<generator>/procedures/*.java.ftl` at all** - it only
  type-checks the workspace's copy of `runtime/`, not the procedure templates MCreator expands
  into a workspace's generated `*Procedure.java` files. Hit for real: `26.1.2`/`26.2`'s procedure
  templates were copied byte-identical from 1.21.1 on the assumption that "procedures only touch
  APIs that never diverged" - true for 1.21.8, false here, since they fully-qualify
  `net.minecraft.resources.ResourceLocation` (renamed to `Identifier`, see above) and a procedure
  has no imports to catch that at template-authoring time. Only a real MCreator/Gradle build
  caught it. General lesson: a byte-identical procedure copy across generators is only safe once
  actually verified against that generator's real API, same as any other file - "it's just a
  procedure, it can't diverge" is exactly the assumption that broke here.
- **MCreator silently no-ops a `global_templates` entry whose `.ftl` file doesn't exist in the
  plugin, instead of failing the build.** Hit for real: `KashiParticleEffects.java.ftl` (the
  "which effects exist" registry, referenced by every generator's `kashiparticle.definition.yaml`)
  was never copied into `src/neoforge-26.1.2/`/`src/neoforge-26.2/` at all when those generators
  were first set up - only `particle.json.ftl` was. The Gradle build compiled clean (the workspace
  already had a stub `KashiParticleEffects.java` on disk from `sync-core-to-workspace.ps1`'s dev
  placeholder, and MCreator just never overwrote it), so nothing looked wrong until an actual
  in-game test found every effect failing to fire with no error anywhere - `KashiParticleRegistry`
  genuinely had zero effects registered. No tooling in this repo catches a missing template file:
  `check-mod-compile.ps1` only type-checks `runtime/`, and `build-plugin.ps1` just zips whatever
  `src/<generator>/` happens to contain. When adding a generator, diff its non-runtime file list
  (`kashiparticle.definition.yaml`, `procedures/*.java.ftl`, `templates/kashiparticle/*.ftl` at the
  top level, excluding the auto-generated `templates/kashiparticle/runtime/` subtree) against an
  existing generator's and confirm every entry has a real counterpart - don't assume a `find`
  turning up *something* means nothing is missing.

## Docs

- [USAGE.md](USAGE.md) — for someone using the plugin to build a mod.
- [DEVELOPMENT.md](DEVELOPMENT.md) — build pipeline, prerequisites, local folder layout.
- [ARCHITECTURE.md](ARCHITECTURE.md) — how it works internally and why.
- [ROADMAP.md](ROADMAP.md) — what's done, what's next.
