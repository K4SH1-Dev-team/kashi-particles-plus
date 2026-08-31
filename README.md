# KASHI Particles Plus

An [MCreator](https://mcreator.net/) plugin that imports Bedrock/Snowstorm `.particle.json` particle
effects into a mod, plays them with full fidelity, and fires them from Blockly procedure blocks —
no GeckoLib, no hand-written Java, no reduced feature set.

Snowstorm is Mojang's own particle authoring tool for Bedrock Edition
([snowstorm.app](https://snowstorm.app/)). This plugin adds a "KASHI Particle" mod element that
takes what you exported from it — the JSON plus its texture — and plays that exact effect in a
Java/NeoForge mod. The procedure blocks only *fire* the effect; every detail of duration, motion,
shape, colour, animation and events comes from the imported file, evaluated by KASHI's own MoLang
engine.

## Status

**v1.0.0** — first production-ready release. Targets **MCreator 2026.1.x** with the
**NeoForge 1.21.1** generator (the only generator this plugin implements today — see
[Roadmap](#roadmap)).

## Features

- Imports a `.particle.json` + its PNG texture through a wizard page on the mod element, validated
  against the same parser the runtime uses, so a broken file is caught at import time with the
  offending component named — not as a crash when the mod loads in-game.
- Full component coverage for the Bedrock particle spec: emitter shapes (point, disc, sphere,
  box, entity AABB, custom), emitter lifetime (once, looping, expression-driven), spawn rate
  (steady, instant, manual), dynamic and parametric particle motion, collision, kill planes,
  curves (linear, catmull_rom, bezier, bezier_chain), local space (follow the entity that fired
  it), events (`particle_effect`, `sound_effect`, `expression`, `sequence`, `randomize`, `log`),
  flipbook animation, and colour gradients/expressions.
- Three procedure blocks: spawn at a world position, spawn from an entity's eyes (with a
  local-frame offset and an aim mode), and spawn from a block. Aim mode controls how much of the
  firing entity's look direction the effect inherits.
- A self-contained MoLang expression compiler and evaluator (`core/`) — no GeckoLib dependency,
  parses once per expression and re-evaluates the compiled form every tick/frame.
- Wizard-time diagnostics: catches effects that would draw nothing (zero size, zero alpha, a
  flipbook that outruns its own sheet), effects that reference other effects that were not
  imported, and effects likely to spawn a very large number of particles.
- A `/kashiparticle_<modid>` debug command (client-only) to fire an effect without wiring a
  procedure, and to report what every fired effect actually did — spawned, drawn, at what size and
  alpha — because "nothing appeared" can mean four different things that all look identical from
  the outside.

## Requirements

- MCreator 2026.1.x, with the **NeoForge 1.21.1** generator.
- Java plugins enabled in MCreator's preferences (MCreator → Preferences → enable Java plugin
  support, if not already on).

## Installation

1. Download `kashi_particles_plus.zip` from [Releases](../../releases).
2. Drop it into your MCreator plugins folder (`.mcreator/plugins/` under your user profile).
3. Restart MCreator.
4. In a NeoForge 1.21.1 workspace, **Mod element → New mod element → KASHI Particle** should now
   be available.

## Usage

1. Export an effect from [Snowstorm](https://snowstorm.app/) as a `.particle.json`, with its
   texture as a separate PNG.
2. Create a new **KASHI Particle** mod element, click **Import .particle.json…**, and pick the
   texture.
3. If the effect references other effects through its events (a hit effect that also plays a
   sound-trail effect, for instance), import those too — an effect that isn't imported simply
   doesn't play when referenced, silently.
4. Use one of the three **KASHI Particles** procedure blocks to fire it:
   - **Spawn KASHI Particle at x/y/z** — world position, authored orientation. Best for area
     effects.
   - **Spawn KASHI Particle from entity** — from the entity's eyes, with a local-frame offset
     (`forward`/`right`/`up`) and an **aim** mode (full look, yaw-only, or none).
   - **Spawn KASHI Particle from block** — at the centre of a block.

See [docs/USAGE.md](docs/USAGE.md) for the full block reference, aim-mode semantics, and
performance guidance for firing many effects at once.

## Building from source

This is not the standard MCreator Gradle plugin workflow — see
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for why and for the full build pipeline
(`tools/*.ps1`/`*.py`), the codebase layout (`core/` vs `runtime/` vs `src/` vs `src-java/`), and
how to point it at your own MCreator installation and dev workspace.

## Roadmap

- Port to MCreator 2026.2 with the NeoForge 1.21.8, 26.1 and 26.2 generators.
- See [PLANO-PARIDADE-SNOWSTORM.md](PLANO-PARIDADE-SNOWSTORM.md) for the (historical) Bedrock
  parity plan this plugin was built against.

## License

[MIT](LICENSE) — see the LICENSE file.
