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
4. **`KashiRenderType`** picks the GL blend state from the effect's Bedrock `material`
   (`particles_add` → additive, `particles_blend` → straight alpha, `particles_alpha`/
   `_opaque` → alpha-tested with blending off, for a crisp cutout edge instead of a soft one). How
   it does that is one of the two files that differ per generator - see "Two generators" below.

## The generation pipeline

```
runtime/src/main/java/...        (plain Java, package net.kashi.particles.runtime/core)
        │
        │  tools/make-runtime-templates.ps1
        ▼
src/<generator>/templates/kashiparticle/runtime/...*.java.ftl   (one copy per generator)
        │
        │  declared as global_templates in that generator's kashiparticle.definition.yaml
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

Each generator's `kashiparticle.definition.yaml` is itself generated (by the same script) from
that generator's file list — don't hand-edit it.

### Four generators, one shared runtime

This plugin ships four generators - `neoforge-1.21.1`, `neoforge-1.21.8`, `neoforge-26.1.2` and
`neoforge-26.2` (see [DEVELOPMENT.md](DEVELOPMENT.md) for the test workspaces that back each and
which MCreator install/JDK each one needs). `runtime/` is one source tree, not four - every file
that genuinely behaves the same across generators is written once there.

Files that genuinely diverge live in a per-generator **overlay** directory
(`runtime-1.21.8/`, `runtime-26.1.2/`, `runtime-26.2/`, each mirroring `runtime/`'s own layout under
`src/main/java/net/kashi/particles/runtime/...`) rather than as a second copy of the whole tree.
`make-runtime-templates.ps1` and `sync-core-to-workspace.ps1` both walk `runtime/` (plus `core/`)
as usual, but for a generator with an overlay, any file that also exists there is used in its place
- and any file that exists **only** in the overlay (no shared counterpart at all) is templated too,
as a genuinely new file for that generator alone. The mechanism does not care how many files an
overlay touches: 1.21.8's overlay is a handful of files; 26.1.2/26.2's is close to the entire tree
(below) plus two files with no 1.21.x equivalent at all.

#### 1.21.1 → 1.21.8: a handful of files

- **`KashiParticleAPI.java`** — `ServerLevel.sendParticles` gained an extra `alwaysShow` boolean
  parameter (the old `longDistance` parameter was renamed `overrideLimiter`, same role - still the
  32-vs-512-block broadcast radius).
- **`KashiRenderType.java`** — `ParticleRenderType` is an interface in 1.21.1 (implemented here,
  driving GL blend state imperatively through `RenderSystem`/`GlStateManager`) and a `record` in
  1.21.8 (can no longer be implemented; Minecraft's own particle render types are built
  declaratively instead, from a `RenderPipeline` + `BlendFunction`). The 1.21.8 file follows that
  same declarative pattern - each blend mode maps to the same `RenderType`/`RenderPipeline` shape
  vanilla itself uses for its own particles.
- **`KashiParticlesRuntime.java`, `KashiParticleClient.java`, `KashiDebugCommand.java`** — each
  only differs in its `@EventBusSubscriber` annotation. 1.21.1 selects the event bus explicitly
  (`bus = EventBusSubscriber.Bus.MOD`/`.GAME`); 1.21.8 removed that attribute entirely - which bus
  a subscriber uses is now inferred per event from whether the event type implements
  `IModBusEvent`, so the 1.21.8 files simply omit `bus` and get the same routing automatically.

#### 1.21.x → 26.1.2/26.2: a much bigger jump, confirmed the same way (real API, not assumed)

Minecraft's own version scheme moved from `1.21.x` to a calendar-based `26.x` between these
generators, and the particle system was substantially redesigned along with it - almost every file
in `runtime/` touches something that changed, so the overlay for these two generators is close to a
full copy rather than a handful of files. What actually changed, confirmed against each generator's
real `minecraft-patched-*.jar`/`-sources.jar` (never assumed from the other):

- **`ResourceLocation` was renamed to `net.minecraft.resources.Identifier`** - identical API
  otherwise (`fromNamespaceAndPath`, `tryParse`, `getPath`, `CODEC`, `STREAM_CODEC`, ...), so every
  file that touches an effect or texture id needed only the rename, not a rethink.
- **`@EventBusSubscriber`'s `bus` attribute is gone**, same as 1.21.8 - omit it, same automatic
  routing.
- **`ServerLevel.sendParticles`** needs the same extra boolean 1.21.8 already added
  (`overrideLimiter, alwaysShow`) - this part didn't change again between 1.21.8 and 26.x.
- **`Level.random` became `protected`** (was `public`) - `level.getRandom()` is the accessor
  (`KashiEventRunner.java`).
- **`Camera.getPosition()` was renamed to `Camera.position()`.**
- **The particle rendering pipeline was rebuilt around "extract this frame's data, submit it
  later" instead of "each particle draws itself into a `VertexConsumer`"**, and this is the one
  that actually costs real code, not just a rename:
  - `Particle` no longer declares `render(VertexConsumer, Camera, float)` at all - a particle now
    implements `getGroup()` (the old `getRenderType()`, renamed) and, if it wants to draw something,
    provides its own way to hand data to a per-`ParticleGroup` render state during `extractRenderState`.
    `KashiEmitterParticle` (which never draws) just drops `render()` entirely - there is nothing to
    override any more for a `NO_RENDER` particle.
  - `KashiParticle` does draw, and needed the deepest change: `runtime-26.1.2/`/`runtime-26.2/` add
    two files with **no 1.21.x counterpart**, `KashiParticleGroup.java` and
    `KashiParticleRenderState.java`, registered once (not per-effect) via NeoForge's
    `RegisterParticleGroupsEvent` (see `KashiParticleClient.java`). Vanilla's own equivalent,
    `SingleQuadParticle`/`QuadParticleRenderState`, was deliberately **not** reused as a base class:
    it only stores one `scale` float per particle, so every quad it can draw is square - and a
    KASHI particle's width and height are independently authored (Bedrock's `particle_appearance
    .size.x`/`.y`). `KashiParticleRenderState` reimplements the same batching-by-texture-and-blend
    pattern with two independent half-sizes instead, using vanilla's own `SingleQuadParticle.Layer`
    record as the bucket key (reused as-is - it is public with a public constructor, so nothing
    stops a mod building its own instances without extending `SingleQuadParticle`).
  - **26.1.2 and 26.2 don't even agree with each other here** - confirmed against both real jars,
    not assumed from one to the other, which is why they get separate overlays rather than sharing
    one: 26.1.2's `QuadParticleRenderState` requires implementing `SubmitNodeCollector
    .ParticleGroupRenderer` (a `prepare()`/`render()` split building GPU buffers by hand -
    `KashiParticleRenderState` implements that interface directly, no inheritance needed). 26.2
    simplified this considerably: `QuadParticleRenderState` dropped that interface for a plain
    `buildLayer(Layer, VertexConsumer)` the engine calls directly - much closer to how 1.21.1/1.21.8
    worked - but `OrderedSubmitNodeCollector.submitQuadParticleGroup` is hard-typed to the
    *concrete* `QuadParticleRenderState` class, not an interface, so the 26.2 version of
    `KashiParticleRenderState` has to `extends QuadParticleRenderState` and override every method
    that matters, deliberately never calling into the (still square-only) inherited storage.
  - `RenderPipeline.Builder` also dropped `withBlend`/`withDepthWrite` (used to build 1.21.8's
    additive pipeline) in favour of `withColorTargetState(ColorTargetState)`/
    `withDepthStencilState(DepthStencilState)` - same vanilla `WEATHER_NO_DEPTH_WRITE`-style pattern,
    just nested differently. `SourceFactor`/`DestFactor` merged into one `BlendFactor` enum in 26.2
    (26.1.2 still has the separate pair) - `KashiRenderType.java` differs between the two overlays
    for exactly this one line.
  - `ParticleRenderType` itself changed shape too: from a per-(texture, blend) object wrapping a
    real render type (1.21.1/1.21.8) to a plain named marker with a handful of fixed vanilla
    constants plus whatever a mod registers (26.1.2's constructor takes one `String`; 26.2's takes
    `(String name, String shorthand)`). The engine now creates exactly one `ParticleGroup` per
    distinct `ParticleRenderType` for the whole session, not one per texture - which is why
    `KashiRenderType.GROUP` is a single shared constant every KASHI particle reports, and the
    per-(texture, blend) batching that used to happen implicitly per-`ParticleRenderType` instance
    moved into `KashiParticleGroup`/`KashiParticleRenderState` instead.
  - Frustum culling moved from "the engine asks each particle for a custom bounding box"
    (`Particle.getRenderBoundingBox`, gone entirely) to "each `ParticleGroup` culls its own
    particles however it likes" (vanilla's own group just tests the bare particle position). Losing
    the old custom box would silently reintroduce the exact bug it was written to fix (a quad
    several blocks across getting culled the instant its centre - not its visible edge - left the
    frustum), so `KashiParticleGroup` calls `Frustum.isVisible(AABB)` against a box `KashiParticle`
    still computes the same way, instead of the plain point test vanilla uses.
  - `ParticleProvider.createParticle` gained a trailing `RandomSource` parameter
    (`KashiParticleClient.java` - accepted, not currently used).
  - **26.2 flipped the default depth-buffer convention to reversed-Z; 26.1.2 did not** - confirmed
    against both real sources: `DepthStencilState.DEFAULT` is `(LESS_THAN_OR_EQUAL, true)` on
    26.1.2, `(GREATER_THAN_OR_EQUAL, true)` on 26.2. `ADDITIVE_PIPELINE` explicitly sets its own
    compare op (to disable `writeDepth` without disturbing the test), so it has to track this by
    hand rather than inheriting the right default the way `OPAQUE_PARTICLE`/`TRANSLUCENT_PARTICLE`
    do - a real bug where the 26.2 file was copied from 26.1.2 with the wrong (old) compare op,
    causing every `ADD`-blend effect to render as an unoccluded, oversaturated blob on 26.2 only.
    See CLAUDE.md for the full diagnosis.

Every generator's procedure templates (`src/<generator>/procedures/*.java.ftl`) and the two
non-runtime templates (`particle.json.ftl`, `KashiParticleEffects.java.ftl`) are plain copies, not
generated - but **not quite identical byte-for-byte across all four any more.** They were for
1.21.1/1.21.8 (neither touches anything that diverged between those two), and `26.1.2`/`26.2`
started as byte-identical copies of 1.21.1's on the same assumption - wrongly: all three procedure
templates construct the effect id via `net.minecraft.resources.ResourceLocation.fromNamespaceAndPath(...)`,
fully-qualified (procedures have no imports of their own), and `ResourceLocation` is exactly the
class that got renamed to `Identifier` for 26.1.2/26.2 (see above) - caught by a real Gradle build,
not `check-mod-compile.ps1` (which only type-checks `runtime/`, never the procedure templates
MCreator itself expands). Fixed by updating that one fully-qualified name in the `26.1.2`/`26.2`
copies; they otherwise still match 1.21.1's procedures line for line, so keep updating all four in
step for anything else - just remember the effect-id line is the one place they now differ.

## Resolving which effect a procedure fires

The three procedure templates (`src/<generator>/procedures/*.java.ftl`, identical for every
generator - see above) need to turn "the
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
