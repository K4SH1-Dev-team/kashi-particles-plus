# CLAUDE.md

Orientation for an AI assistant (or a new contributor) opening this repository cold. This file is
deliberately short — an index, not a substitute for `docs/`.

## What this is

KASHI Particles Plus is an MCreator plugin. It imports Bedrock/Snowstorm `.particle.json` particle
effects into a "KASHI Particle" mod element and plays them with full fidelity in a NeoForge mod,
fired from Blockly procedure blocks. It has its own MoLang expression engine — no GeckoLib
dependency. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it actually works.

## Layout, in one line each

- `core/` — the MoLang engine + `.particle.json` parser + wizard-time diagnostics. Pure Java, no
  MCreator/Minecraft dependency. Compiled directly into the plugin *and* templated into every
  generated mod (see docs/ARCHITECTURE.md — "The generation pipeline").
- `runtime/` — the mod-side particle engine (spawn/tick/render, render types, debug command).
  Templated into every generated mod almost verbatim; never compiled into the plugin itself.
- `src/` — the actual MCreator plugin payload (`plugin.json`, lang strings, the
  `neoforge-1.21.1` generator's templates/definition, procedure block definitions, themes).
- `src-java/` — the plugin's own Java: the mod element type, its wizard GUI, plugin entry point.
  Compiled against `mcreator.exe` (MCreator's classes live inside the exe, not in a `lib/` jar —
  see docs/DEVELOPMENT.md).
- `tools/` — every dev script: build pipeline, batch validation, dev-only import helpers.
  Resolves the local-only dev environment (MCreator install, test workspaces) as
  `../local/mcreator` and `../local/workspace/...` relative to this repo — see
  docs/DEVELOPMENT.md for the full layout and why.

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
  API and crashed the game or resolved to the wrong element. See docs/ARCHITECTURE.md.

## Docs

- [docs/USAGE.md](docs/USAGE.md) — for someone using the plugin to build a mod.
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) — build pipeline, prerequisites, local folder layout.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how it works internally and why.
- [docs/ROADMAP.md](docs/ROADMAP.md) — what's done, what's next.
