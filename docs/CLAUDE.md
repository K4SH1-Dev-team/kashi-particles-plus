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
  Templated into every generated mod almost verbatim; never compiled into the plugin itself. Two
  generators share this one tree; a handful of files that genuinely differ between them live in
  `runtime-1.21.8/` instead of a second copy of the whole thing — see ARCHITECTURE.md — "Two
  generators, one shared runtime".
- `src/` — the actual MCreator plugin payload (`plugin.json`, lang strings, each generator's own
  `neoforge-1.21.1`/`neoforge-1.21.8` templates/definition, procedure block definitions, themes).
- `src-java/` — the plugin's own Java: the mod element type, its wizard GUI, plugin entry point.
  Compiled against `mcreator.exe` (MCreator's classes live inside the exe, not in a `lib/` jar —
  see DEVELOPMENT.md).
- `tools/` — every dev script: build pipeline, batch validation, dev-only import helpers.
  Resolves the local-only dev environment (MCreator install, test workspaces) as
  `../local/mcreator` and `../local/workspace/...` relative to this repo — see
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

## Docs

- [USAGE.md](USAGE.md) — for someone using the plugin to build a mod.
- [DEVELOPMENT.md](DEVELOPMENT.md) — build pipeline, prerequisites, local folder layout.
- [ARCHITECTURE.md](ARCHITECTURE.md) — how it works internally and why.
- [ROADMAP.md](ROADMAP.md) — what's done, what's next.
