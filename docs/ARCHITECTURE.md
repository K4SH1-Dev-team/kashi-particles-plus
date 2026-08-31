# Architecture

How this works internally, and why it's built the way it is. For "how to build it", see
[DEVELOPMENT.md](DEVELOPMENT.md). For "how to use it", see [USAGE.md](USAGE.md).

## Why a self-contained MoLang engine instead of GeckoLib

Bedrock particle effects are driven by MoLang, Bedrock's expression language (`variable.size =
math.random(0,360);`). GeckoLib is the usual way an MCreator plugin gets MoLang-like scripting on
the Java side, but it doesn't expose a general MoLang parser/evaluator as a reusable API — and,
separately, at the time this plugin targeted MCreator's NeoForge 1.21.1 generator, no GeckoLib
build compatible with that generator combination existed. So `core/.../molang/` is a from-scratch
MoLang compiler and evaluator: a small hand-written parser (`MolangCompiler`) that turns an
expression string into a compiled `MolangValue` once, and a `MolangContext` holding the variable
slots (`variable.*`, `v.*` aliases, `query.*`) it evaluates against. No GeckoLib dependency
anywhere in this plugin.

## Particle lifecycle

One imported effect becomes, at generation time, one `KashiCompiledEffect` — the parsed
`KashiParticleDefinition` (from `core/`) plus a `MolangCompiler` primed with every expression in
it pre-compiled. Firing it:

1. **`KashiParticleAPI.spawnKashiParticle`/`spawnFromEntity`** (called from a procedure block or
   `KashiDebugCommand`) looks the effect up in `KashiParticleRegistry` and creates one
   **`KashiEmitterParticle`** — an invisible, tick-driven particle that IS the emitter. It never
   renders (`KashiRenderType` is never invoked for it); its only job is to run
   `emitter_initialization`, obey the emitter's shape/rate/lifetime, and spawn the particles
   users actually see.
2. Each tick, the emitter evaluates its rate (`emitter_rate_steady`/`_instant`/`_manual`) and
   shape (`emitter_shape_point`/`_disc`/`_sphere`/`_box`/`_custom`/`_entity_aabb`) to decide how
   many **`KashiParticle`**s to spawn this tick and where, then hands each one straight to
   Minecraft's own `ParticleEngine.add(Particle)` — not through the type-gated
   `Level.addParticle(...)` path, which matters (see below).
3. Each `KashiParticle` runs its own per-tick update (`applyDynamicMotion`/
   `applyParametricMotion`, curves, collision) and, separately, a per-*frame* `render()` — the
   distinction matters because ticks run at a fixed 20/s but frames don't, so anything that must
   look smooth (position, colour interpolation) is computed in `render()`, not just on tick.
4. **`KashiRenderType`** picks the GL blend function from the effect's Bedrock `material`
   (`particles_add` → additive, `particles_blend` → straight alpha, `particles_alpha`/
   `_opaque` → alpha-tested with blending off, for a crisp cutout edge instead of a soft one).

## The generation pipeline

```
runtime/src/main/java/...        (plain Java, package net.kashi.particles.runtime/core)
        │
        │  tools/make-runtime-templates.ps1
        ▼
src/neoforge-1.21.1/templates/kashiparticle/runtime/...*.java.ftl
        │
        │  declared as global_templates in kashiparticle.definition.yaml
        │  (regenerated whenever a workspace has ≥1 KASHI Particle element)
        ▼
<user's mod>/src/main/java/net/kashi/particles/runtime/...   (real .java, compiled with their mod)
```

`runtime/` and `core/` are both templated this way — every file becomes a `.java.ftl` almost
verbatim (the templating script does exactly one substitution: the dev workspace's mod id, needed
because it's a compile-time constant in the generated code — see the comment at the top of
`make-runtime-templates.ps1`). `core/` is templated too, but it also does double duty: the
**plugin itself** compiles `core/` straight from source (via `tools/build-plugin.ps1`, against
`mcreator.exe`) so the import wizard can parse and run diagnostics on a `.particle.json` *before*
any mod code exists to run it. So a `.particle.json` is parsed by the exact same `core/` code
twice — once by the wizard at import time (compiled Java), once by the generated mod at
registration time (templated Java) — which is why a parse error is always caught at import,
never as a surprise mod crash.

`src/neoforge-1.21.1/kashiparticle.definition.yaml` is itself generated (by the same script) from
that file list — don't hand-edit it.

## Resolving which effect a procedure fires

The three procedure templates (`src/neoforge-1.21.1/procedures/*.java.ftl`) need to turn "the
`CUSTOM:` reference to a KASHI Particle mod element" into the exact `ResourceLocation` path
MCreator will register that element's effect under. This was the single most expensive thing to
get right in this project, so it's worth writing down clearly:

- **`generator.map(field, "datalistName")`** — MCreator's normal tool for this — only actually
  resolves `CUSTOM:` references for MCreator's own *built-in* datalists (sounds, projectiles).
  For a datalist this plugin defines itself, it returns something close to the raw field,
  unresolved (capitalisation and all). Using it here either crashed with a `ResourceLocationException`
  or silently resolved to the *wrong* element.
- **Writing our own `registry_name`** into the `.mcreator` element file and matching it with a
  plain `?lower_case` in the template — looked right, but **MCreator recalculates `registryName`
  itself from the element's `name` on every code generation, ignoring whatever is stored in that
  field.** Confirmed by comparing against every real element in a 281-element test pack: 280
  matched the recalculated value, only one legacy hand-created element didn't.
- **What actually works:** the templates reproduce MCreator's own name→registryName algorithm
  directly in FreeMarker —
  `?replace("(.)([A-Z][a-z]+)", "$1_$2", "r")?replace("([a-z0-9])([A-Z])", "$1_$2", "r")?lower_case`
  (insert `_` at capital-letter transitions, then lowercase). Verified against all 281 real
  elements before ever testing in-game: exact match.

If you ever touch these three templates, re-verify against a real batch of elements with
multi-word names — a fix that only gets tested against one-word element names will look correct
and silently break for everything else (that's exactly how this bug went unnoticed for months).

## `overrideLimiter = true`

`KashiParticleType`'s constructor passes `true` for `overrideLimiter`. Vanilla's
`LevelRenderer.addParticle` reads this flag to decide whether to distance-cull a particle
*before it's even created*, but only for particles spawned through the type-gated
`Level.addParticle(ParticleOptions, ...)` path. This plugin's own particles never go through that
path — they're added directly via `ParticleEngine.add(Particle)` (see Particle lifecycle above),
so the flag has zero effect on them. What it *does* gate is the invisible `KashiEmitterParticle`
itself: with the default `false`, an effect fired more than roughly 15-30 blocks from the player
(distance-to-cull depends on angle) never got its emitter created at all — no error, no particles,
indistinguishable from a broken effect. Setting it `true` costs nothing (the emitter never
renders) and means an effect deliberately fired off-screen still plays once the player gets close
enough to see it, instead of silently never starting.

## Thread-safety

Every piece of shared mutable state in `runtime/` is a `ConcurrentHashMap`
(`KashiParticleRegistry`'s effect/alias/failure maps, `KashiRenderType`'s per-(texture,blend)
cache, `KashiDiagnostics`'s per-effect counters). None of it is keyed by particle instance or
grows per-particle — only by distinct effect identifier or (texture, blend) pair, both small,
bounded sets — so none of this is a performance concern at scale.
