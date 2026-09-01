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
- **`tools/check-mod-compile.ps1` type-checks against the workspace's own `build/moddev/
  clientLegacyClasspath.txt`, not a blind scan of `~/.mcreator/gradle/caches`.** Two test
  workspaces share that cache; a bare scan can pick up two different versions of the same library
  and resolve symbols against the wrong one. Also always pass `-sourcepath` pointed at just the
  workspace's own sources: the merged jar bundles a `.java` next to the `.class` for some NeoForge
  classes, and without an explicit `-sourcepath`, javac defaults it to the classpath, finds those,
  and type-checks them too - `-implicit:none` does **not** stop this (it only suppresses writing
  their `.class` output, not the type-checking itself, confirmed by trying it first).

## Docs

- [USAGE.md](USAGE.md) — for someone using the plugin to build a mod.
- [DEVELOPMENT.md](DEVELOPMENT.md) — build pipeline, prerequisites, local folder layout.
- [ARCHITECTURE.md](ARCHITECTURE.md) — how it works internally and why.
- [ROADMAP.md](ROADMAP.md) — what's done, what's next.
