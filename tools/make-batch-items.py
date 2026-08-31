"""Creates a handful of "fire everything" items for fast regression testing.

Clicking through 281 individual items one at a time is not a real workflow for "did the last
change break anything". This instead makes BATCH_COUNT items - each one, on right click, fires a
whole SLICE of every imported KASHI Particle effect at once, laid out in a straight line in front
of the player so each effect is spatially separate and inspectable, instead of firing 281
individual clicks.

The batch items use a different vanilla icon (a nether star) so they stand out from the 281
per-effect items in the creative inventory search, which all share "minecraft:light".

Layout: a straight line, not a grid. A grid's lower rows would sit BELOW eye height and end up
underground on flat terrain (up is measured from the player's eyes, and eye height is only ~1.6
blocks) - a line at a fixed height next to the player has no such failure mode, just walk along it.

Usage:
    python tools/make-batch-items.py
"""

import json
import math
import os
import re

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The repo (this script's parent tree) and the local-only dev environment (test workspaces) are
# sibling folders under the project root - see docs/DEVELOPMENT.md.
LOCAL_ROOT = os.path.join(os.path.dirname(PROJECT), "local")
WORKSPACE = os.path.join(LOCAL_ROOT, "workspace", "kashi_particle_test")
MODID = "kashi_particle_test"

ELEMENTS = os.path.join(WORKSPACE, "elements")
WORKSPACE_FILE = os.path.join(WORKSPACE, MODID + ".mcreator")

FORMAT_VERSION = 85
BATCH_COUNT = 9

# Well clear of "minecraft:light" (what every individual effect item uses), so a batch item reads
# as different before you even check its name.
BATCH_TEXTURE = "minecraft:nether_star"

# Minecraft's particle renderer silently drops any particle whose type does not declare
# "override limiter" once it is too far from the player - confirmed by decompiling
# LevelRenderer.addParticle: it reads ParticleType.getOverrideLimiter() and, when false (which is
# what a plain, non-force-visible type like ours has), culls anything past some radius. A batch of
# 32 at SPACING=6 stretched to +-93 blocks and only ~10 rendered; even SPACING=1.5 (+-24 blocks,
# ~24.6 at the far corners once FORWARD is folded in) still lost 11 of 32, asymmetrically between
# the two ends - so the real radius is both smaller and less generous than the ~30 blocks a first
# read of the numbers suggested, and not perfectly symmetric in practice (world geometry, chunk
# state, or something else breaks the tie). A cull-adjacent second-order effect showed up too:
# a few particles that DO render, but only after they were culled through their bright opening
# frames, so by the time they are first drawn their own colour gradient has already faded them to
# fully transparent - not a separate bug, just this same distance issue with an extra symptom.
#
# FORWARD is pulled in and SPACING cut hard so even the far corners sit close to the player -
# worth more overlap (already unavoidable for the pack's 40-60-block effects at any spacing that
# fits 32 of them in frame) in exchange for actually rendering. A batch item is a fast go/no-go
# smoke test read from /kashiparticle report, not a clean side-by-side visual comparison; use the
# individual per-effect item for that.
SPACING = 0.7
FORWARD = 5


def snake(name):
    step = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)

    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", step).lower()


def write_element(name, kind, definition):
    path = os.path.join(ELEMENTS, name + ".mod.json")

    with open(path, "w", encoding="utf-8") as out:
        json.dump({"_fv": FORMAT_VERSION, "_type": kind, "definition": definition}, out, indent=2)


def item_definition(display, procedure):
    return {
        "renderType": 0,
        "texture": BATCH_TEXTURE,
        "customModelName": "Normal",
        "guiTexture": "",
        "customProperties": {},
        "states": [],
        "animations": [],
        "name": display,
        "rarity": "COMMON",
        "creativeTabs": [{"value": "COMBAT"}],
        "stackSize": 1,
        "enchantability": 0,
        "useDuration": 0,
        "toolType": 1.0,
        "damageCount": 0,
        "recipeRemainder": {"value": ""},
        "destroyAnyBlock": False,
        "immuneToFire": False,
        "isPiglinCurrency": False,
        "repairItems": [],
        "stayInGridWhenCrafting": False,
        "damageOnCrafting": False,
        "enableMeleeDamage": False,
        "damageVsEntity": 4.0,
        "attackSpeed": 1.2,
        "specialInformation": {"fixedValue": []},
        "glowCondition": {"fixedValue": False},
        "openGUIOnRightClick": {"fixedValue": False},
        "inventorySize": 9,
        "inventoryStackSize": 99,
        "onRightClickedInAir": {"name": procedure},
        "enableRanged": False,
        "shootConstantly": False,
        "rangedItemChargesPower": False,
        "projectile": {"value": "Arrow"},
        "projectileDisableAmmoCheck": False,
        "isFood": False,
        "nutritionalValue": 4,
        "saturation": 0.3,
        "eatResultItem": {"value": ""},
        "isMeat": False,
        "isAlwaysEdible": False,
        "animation": "none",
        "isMusicDisc": False,
        "musicDiscMusic": {"value": ""},
        "musicDiscDescription": "",
        "musicDiscLengthInTicks": 100,
        "musicDiscAnalogOutput": 0,
        "providedBannerPatterns": [],
        "attributeModifiers": [],
    }


def num(x):
    # Blockly's math_number field wants plain decimal text, not Python's repr / scientific form.
    return ("%g" % x)


def spawn_block(effect_name, right, next_xml=""):
    next_part = ("<next>" + next_xml + "</next>") if next_xml else ""

    return (
        '<block type="entity_spawn_kashi_particle_from_target">'
        '<field name="effect">CUSTOM:' + effect_name + "</field>"
        '<field name="aim">HORIZONTAL</field>'
        '<value name="entity"><block type="entity_from_deps"></block></value>'
        '<value name="right"><block type="math_number"><field name="NUM">' + num(right)
        + "</field></block></value>"
        '<value name="up"><block type="math_number"><field name="NUM">0</field></block></value>'
        '<value name="forward"><block type="math_number"><field name="NUM">' + str(FORWARD)
        + "</field></block></value>"
        + next_part
        + "</block>"
    )


def procedure_xml(effect_names):
    # Centred on 0 so the line runs half to the player's left, half to the right, rather than
    # trailing off entirely to one side.
    offsets = [(i - (len(effect_names) - 1) / 2) * SPACING for i in range(len(effect_names))]

    chain = ""

    for effect, right in reversed(list(zip(effect_names, offsets))):
        chain = spawn_block(effect, right, chain)

    return (
        '<xml xmlns="https://developers.google.com/blockly/xml">'
        '<block type="event_trigger" deletable="false" x="40" y="40">'
        '<field name="trigger">no_ext_trigger</field>'
        "<next>" + chain + "</next>"
        "</block></xml>"
    )


def main():
    workspace = json.load(open(WORKSPACE_FILE, encoding="utf-8"))
    effect_names = [e["name"] for e in workspace["mod_elements"] if e["type"] == "kashiparticle"]
    effect_names.sort()

    total = len(effect_names)
    base, extra = divmod(total, BATCH_COUNT)

    batches = []
    start = 0

    for i in range(BATCH_COUNT):
        size = base + (1 if i < extra else 0)
        batches.append(effect_names[start:start + size])
        start += size

    existing = {entry["name"] for entry in workspace["mod_elements"]}
    new_elements = []
    language = {}

    for i, batch in enumerate(batches, start=1):
        element = "TestBatch%d" % i
        procedure = element + "Fire"
        item = element + "Item"
        display = "Test Batch %d (%d effects)" % (i, len(batch))

        write_element(procedure, "procedure",
                      {"procedurexml": procedure_xml(batch), "skipDependencyNullCheck": False})
        write_element(item, "item", item_definition(display, procedure))

        new_elements.append((procedure, "procedure"))
        new_elements.append((item, "item"))
        language["item." + MODID + "." + snake(item)] = display

    for name, kind in new_elements:
        if name in existing:
            continue

        workspace["mod_elements"].append({
            "name": name,
            "type": kind,
            "compiles": True,
            "locked_code": False,
            "registry_name": snake(name),
            "metadata": {"files": []},
        })

    workspace.setdefault("language_map", {}).setdefault("en_us", {}).update(language)

    with open(WORKSPACE_FILE, "w", encoding="utf-8") as out:
        json.dump(workspace, out, indent=2)

    print("effects available : %d" % total)
    print("batch items        : %d" % BATCH_COUNT)
    print()

    for i, batch in enumerate(batches, start=1):
        print("  Test Batch %d: %d effects (%s .. %s)" % (i, len(batch), batch[0], batch[-1]))


if __name__ == "__main__":
    main()
