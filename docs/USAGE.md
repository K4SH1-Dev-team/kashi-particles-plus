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

Three procedure blocks, all under the **KASHI Particles** category:

### Spawn KASHI Particle at x / y / z

Fires the effect at a world position. `direction x/y/z` defaults to `(0, 0, 0)`, which keeps the
orientation it was authored with (world axes; "up" stays up) — best for an AOE, a structure
effect, a fixed hazard. A non-zero direction turns the whole effect to face that way, the same
idea as **aim** on the entity block below, just given directly since there's no entity to read a
look direction from.

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

### Spawn KASHI Particle from block

Fires at the centre of a block. Same `direction x/y/z` as the world-position block above — zero
keeps the authored world orientation, non-zero turns the effect to face that way.

## Performance: firing many effects at once

Each KASHI effect fires as its own emitter, always created regardless of distance from the
player (so an effect fired far away still plays — it just isn't drawn until the player is close
enough to see it, same as any particle). That has no real cost.

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
