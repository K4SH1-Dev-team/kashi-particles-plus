# Usage

## Importing an effect

1. Export the effect from [Snowstorm](https://snowstorm.app/) as a `.particle.json`. Export its
   texture separately as a PNG.
2. In your MCreator workspace: **Mod element → New mod element → KASHI Particle**.
3. Click **Import .particle.json…** and pick the file. It is validated with the exact parser the
   runtime uses — a malformed file is rejected here, with the offending component named, instead
   of surfacing as a crash when a world loads later.
4. Pick the texture under **Particle texture**.
5. If the import succeeds but the effect has something worth knowing about, a dialog says so:
   - **Unsupported components** — parsed but not implemented; the impact is named per component.
   - **Effects it references** — if this effect's events fire another effect
     (`minecraft:particle_effect` nodes), that effect is not automatically pulled in. Import it as
     its own KASHI Particle element too, under any name — the plugin resolves the reference by the
     Bedrock identifier inside the JSON, not by what you called the element. If you skip this, the
     referenced effect silently does nothing when it would have fired.
   - **Diagnostics** — things likely to make the effect draw nothing at all: zero size or alpha
     throughout its life, a flipbook `max_frame` that runs past what the texture sheet actually
     holds, or an estimated particle count high enough to be worth knowing about before you find
     out in-game.

The element only stores the JSON and the texture — nothing is rewritten. What plays in-game is
byte-for-byte what you imported.

The wizard won't let you save without both a successfully-imported `.particle.json` and a
texture — an incomplete KASHI Particle element can't make it into the workspace.

## Firing an effect

Six procedure blocks, all under the **KASHI Particles** category:

### Spawn KASHI Particle at x / y / z

Fires the effect at a world position. `direction x/y/z` defaults to `(0, 0, 0)`, which keeps the
orientation it was authored with (world axes; "up" stays up) — best for an AOE, a structure
effect, a fixed hazard. A non-zero direction turns the whole effect to face that way, the same
idea as **aim** on the entity block below, just given directly since there's no entity to read a
look direction from.

`scale` / `duration` both default to `0`, meaning no change — whatever was authored in Snowstorm
stays the source of truth. They're **additive**, not multiplicative:

- `scale` is added to every particle's authored half-width/half-height (floored at 0, so a large
  negative value shrinks the effect away rather than flipping it). A positive value grows the
  effect, a negative value shrinks it.
- `duration` is added to the emitter's `active_time` — how long it keeps spawning *new* particles
  — not to any individual particle's own lifetime. A positive value keeps the emitter creating
  particles for longer; existing particles still live out their own authored lifetime either way.

### Spawn KASHI Particle from entity

Fires from the entity's **feet**, offset in the entity's **own** frame:

- `right` / `up` / `forward` — the offset, in blocks, measured relative to the entity (so
  `forward: 3` always means "3 blocks in front of wherever it's looking", not a fixed world
  direction; `up: 0` lands on the ground, not at eye height).
- `aim` — how much of the entity's orientation the effect inherits:
  - **follows full look (up/down too)** — pitch included; an effect fired while looking up travels
    up. What most hit/cast effects want.
  - **turns with entity, stays level** — yaw only, no pitch; the effect never tips over if the
    entity looks up or down. What most on-the-ground trail/aura effects want, and what an effect
    that declares `emitter_local_space.rotation` needs to stay upright.
  - **no aim - world orientation (AOE)** — ignores the entity's facing entirely; the effect plays
    in its authored world orientation, just centred on the entity. What most AOE effects want.

An effect that declares `emitter_local_space` follows the firing entity for its whole lifetime,
not just at spawn — `position` makes it track the entity's movement, `rotation` makes its offset
and velocity turn with the entity (yaw only, for the reason above), `velocity` makes it inherit
the entity's own motion (a trail effect that keeps moving with whoever cast it, instead of
snapping to a stop the instant it's created).

Same `scale` / `duration` additive offsets as the world-position block above, both defaulting to
`0` (no change).

### Spawn KASHI Particle from block

Fires at the centre of a block. Same `direction x/y/z` as the world-position block above — zero
keeps the authored world orientation, non-zero turns the effect to face that way. Same `scale` /
`duration` additive offsets too, both defaulting to `0` (no change).

### Attach KASHI Particle to entity

Keeps the effect following the entity every tick — position **and** rotation both — instead of
spawning once at a fixed position the way the blocks above do. Good for an aura, fire on the feet,
energy in a hand that turns with the arm.

- `attach` — which point on the entity to anchor to:
  - **root/body**, **head**, **eye** — exact, tracks the entity itself.
  - **hand (right)** / **hand (left)** / **foot (right)** / **foot (left)** — a visually-tuned
    approximation driven by attack/walk animation, not a real bone lookup: a punch tips a
    hand-anchored effect forward, a stride swings a foot-anchored one along with the leg. Falls
    back to root/body for anything that isn't a living, biped-shaped entity (a dropped item, for
    instance).
- `right` / `up` / `forward` and `aim` work exactly like **Spawn KASHI Particle from entity**
  above, just measured from the chosen point instead of always the feet (`up: 0` lands right on
  that point). `aim` keeps applying for as long as the effect follows the entity, not just at the
  moment it spawns:
  - **follows full look (up/down too)** — the offset turns with the full look direction, pitch
    included, so an offset on a head/eye anchor swings up and down as the entity looks up and
    down, not just side to side.
  - **turns with entity, stays level** — the offset turns with the entity's yaw only. Looking up or
    down never moves the effect, which is what a body/root anchor with an `up` offset (energy held
    at the hip, an aura around the chest) needs; with *full look*, that offset would swing in an
    arc around the feet whenever the entity pitched.
  - **no aim - world orientation (AOE)** — the offset keeps its world axes and only the anchor
    point moves with the entity.
- Same `scale` / `duration` additive offsets as every spawn block above, both defaulting to `0`.

Like every KASHI spawn, this is still fire-and-forget: an attached looping effect ends on its own
after at most 30 seconds of following, even though it kept tracking the entity right up until
then. Use **Stop** or **Despawn** below to end one earlier.

### Stop / Despawn KASHI Particle

Ends a running effect that **Spawn KASHI Particle from entity** or **Attach KASHI Particle to
entity** started for a specific entity. The `entity` input comes pre-filled with
`entity_from_deps`, same as those two blocks, since targeting that entity's own instance is the
intended use — a world or block spawn has no owning entity, so it isn't reachable by either block.

- **Stop KASHI Particle** — ends the emitter (no more new particles), but lets everything it
  already spawned fade out on its own, the same as if the effect had simply run its course.
- **Despawn KASHI Particle** — a full, instant cutoff: ends the emitter **and** immediately
  removes every particle it already spawned, so the effect disappears completely the moment this
  runs instead of fading out.

Neither reaches an effect fired as another effect's own chained event (its Bedrock file spawning a
second effect on impact, for example) — only an effect a Spawn-from-entity/Attach block started
directly can be stopped or despawned.

## Performance: firing many effects at once

Each KASHI effect fires as its own emitter, always created regardless of distance from the
player (so an effect fired far away still plays — it just isn't drawn until the player is close
enough to see it, same as any particle). That has no real cost. On a multiplayer server the spawn
is broadcast to every player within 512 blocks, so an effect that's genuinely in view stays
visible even fired from far away.

What does cost something is firing a lot of *heavy* effects in the very same tick — a crowd of
entities all playing a hit effect simultaneously, or an AOE that fires from every target at once.
Two independent things can go wrong under that kind of load:

- The client can fall behind enough that some particles finish their entire (tick-driven) life
  before a single frame ever gets to draw them — they technically spawned and technically expired,
  but were never visibly drawn. This is normal Minecraft behaviour under load, not specific to
  this plugin, and it mainly affects short-lived, fast effects.
- More particles are simply more to draw, same as any other particle-heavy mod content.

If a scene genuinely needs many effects at once, spread the calls out (a short delay between
targets, or cap how many fire per tick) rather than firing all of them in one procedure pass.

## The debug command

Client-only, `/kashiparticle_<your mod's id>` (the id is folded into the command name so two
mods built from this plugin never collide with each other):

- `/kashiparticle_<modid>` — lists every effect this mod registered, and any that failed to load
  (with the reason).
- `/kashiparticle_<modid> <effect>` — fires that effect a few blocks in front of you, aimed along
  your full look direction. Useful for eyeballing an effect without wiring a procedure to it.
- `/kashiparticle_<modid> report` — for every effect fired so far this session, what actually
  happened: never spawned, spawned but never drawn, drawn at zero size, drawn fully transparent,
  or fine (with the size/alpha it reached). Only lists the ones worth looking at.
- `/kashiparticle_<modid> reportall` — same, but lists every fired effect, including the ones that
  behaved.
- `/kashiparticle_<modid> reset` — clears the counters `report` reads from.

"Nothing appeared" can mean four different things that all look identical from outside the game —
`report` turns it into a number for each one.
