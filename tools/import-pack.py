"""Imports a whole Bedrock particle pack into the MCreator test workspace.

Writes, for every .particle.json found: a KASHI Particle element, a procedure that fires it, and an
item that runs the procedure on right click. MCreator stores mod elements as plain JSON under
elements/, so this writes them directly rather than driving the wizard 279 times.

Two things in a real pack make a naive import wrong, and both are handled here:

  * Effect files and texture files collide on their short names - the pack holds eleven different
    m1b.particle.json and six different m1b.png. Names are therefore derived from the full path,
    so akaza/m1b and wind/m1b stay separate effects with separate textures.
  * Some effects draw from the vanilla Bedrock particle atlas, which ships with the game rather
    than with the pack. Those get a placeholder and are listed at the end: they will import and
    play, but with the wrong picture until a real atlas is dropped in.

The "registry_name" written into each element below is cosmetic, not authoritative: MCreator
recomputes its own registryName from the element's name every time it generates code (confirmed
against 280 of 281 already-imported elements matching snake() exactly - only a hand-made element
predating this script keeps the name it was given through the wizard), so whatever is written here
is simply overwritten on the next generation pass. It is set anyway, to the same value MCreator
would compute, so the workspace file at least reads consistently in the meantime.

Usage:
    python tools/import-pack.py                 # everything
    python tools/import-pack.py --limit 20      # the first 20, to try the build out first
    python tools/import-pack.py --filter wind   # only paths containing "wind"
"""

import argparse
import json
import os
import re
import shutil
import struct
import sys
import zlib

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The repo (this script's parent tree) and the local-only dev environment (test packs, test
# workspaces) are sibling folders under the project root - see docs/DEVELOPMENT.md.
LOCAL_ROOT = os.path.join(os.path.dirname(PROJECT), "local")
PACK = os.path.join(LOCAL_ROOT, "ds rp")
PARTICLES = os.path.join(PACK, "particles")

# Which workspace to write into - overridable with --workspace, since there is now one test
# workspace per generator (see docs/DEVELOPMENT.md). Both existing workspaces happen to have their
# folder name equal to their mod id, so one flag covers both; WORKSPACE/MODID/etc. below are
# (re)computed from it in main() once args are parsed, so they stay correct either way.
DEFAULT_WORKSPACE = "kashi_particle_test"

WORKSPACE = os.path.join(LOCAL_ROOT, "workspace", DEFAULT_WORKSPACE)
MODID = DEFAULT_WORKSPACE

ELEMENTS = os.path.join(WORKSPACE, "elements")
TEXTURES = os.path.join(WORKSPACE, "src", "main", "resources", "assets", MODID, "textures", "particle")
WORKSPACE_FILE = os.path.join(WORKSPACE, MODID + ".mcreator")

FORMAT_VERSION = 85

# The Bedrock atlas some effects draw from. It ships with the game rather than with a pack, so it
# is only a placeholder when the pack folder does not happen to carry its own copy - which this
# one now does (copied in from the pack's own dsl_ver2 folder), so this path stops mattering for
# it; it stays here only as a fallback for the day a pack genuinely lacks one.
VANILLA_ATLAS = "textures/particle/particles"
PLACEHOLDER = "missing_bedrock_atlas"

# How the generated procedures aim the effect, overridable with --aim.
#
# HORIZONTAL is the default because of what this pack actually contains: 102 of its effects use an
# emitter_transform_* facing, which is a plane pinned to the *emitter's* axes, and 114 declare
# emitter_local_space with rotation - both say "my frame is the entity's frame". Under NONE those
# planes are pinned to world axes instead and are seen edge-on, which looks exactly like the effect
# not playing. NONE is still the right choice for an AOE centred on the player.
AIM = "HORIZONTAL"
FORWARD = 3


def camel(text):
    """A path turned into a unique CamelCase element name MCreator will accept."""
    parts = re.split(r"[^A-Za-z0-9]+", text)

    return "".join(part[:1].upper() + part[1:] for part in parts if part)


def snake(name):
    step = re.sub(r"(.)([A-Z][a-z]+)", r"\1_\2", name)

    return re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", step).lower()


def png(path, size, rgba):
    """Writes a solid PNG, for the placeholder. Avoids a dependency for one tiny image."""
    raw = b"".join(b"\x00" + bytes(rgba) * size for _ in range(size))

    def chunk(tag, data):
        body = tag + data

        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    with open(path, "wb") as out:
        out.write(b"\x89PNG\r\n\x1a\n")
        out.write(chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)))
        out.write(chunk(b"IDAT", zlib.compress(raw)))
        out.write(chunk(b"IEND", b""))


def item_definition(display, procedure):
    return {
        "renderType": 0,
        "texture": "minecraft:light",
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


def procedure_xml(effect):
    return (
        '<xml xmlns="https://developers.google.com/blockly/xml">'
        '<block type="event_trigger" deletable="false" x="40" y="40">'
        '<field name="trigger">no_ext_trigger</field><next>'
        '<block type="entity_spawn_kashi_particle_from_target">'
        '<field name="effect">CUSTOM:' + effect + "</field>"
        '<field name="aim">' + AIM + "</field>"
        '<value name="entity"><block type="entity_from_deps"></block></value>'
        '<value name="right"><block type="math_number"><field name="NUM">0</field></block></value>'
        '<value name="up"><block type="math_number"><field name="NUM">0</field></block></value>'
        '<value name="forward"><block type="math_number"><field name="NUM">'
        + str(FORWARD)
        + "</field></block></value>"
        "</block></next></block></xml>"
    )


def write_element(name, kind, definition):
    path = os.path.join(ELEMENTS, name + ".mod.json")

    with open(path, "w", encoding="utf-8") as out:
        json.dump({"_fv": FORMAT_VERSION, "_type": kind, "definition": definition}, out, indent=2)


def main():
    global AIM, WORKSPACE, MODID, ELEMENTS, TEXTURES, WORKSPACE_FILE

    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=0, help="import only the first N effects")
    parser.add_argument("--filter", default="", help="only paths containing this text")
    parser.add_argument("--no-items", action="store_true",
                        help="effects only - no procedures and no items")
    parser.add_argument("--aim", choices=["HORIZONTAL", "FULL", "NONE"], default=AIM,
                        help="how the generated procedures aim the effect (default %s)" % AIM)
    parser.add_argument("--workspace", default=DEFAULT_WORKSPACE,
                        help="local/workspace/<name> to import into (default %s); its mod id is "
                             "assumed to equal <name>, true of every workspace this project has "
                             "used so far" % DEFAULT_WORKSPACE)
    args = parser.parse_args()

    AIM = args.aim

    WORKSPACE = os.path.join(LOCAL_ROOT, "workspace", args.workspace)
    MODID = args.workspace
    ELEMENTS = os.path.join(WORKSPACE, "elements")
    TEXTURES = os.path.join(WORKSPACE, "src", "main", "resources", "assets", MODID, "textures", "particle")
    WORKSPACE_FILE = os.path.join(WORKSPACE, MODID + ".mcreator")

    if not os.path.isdir(ELEMENTS):
        sys.exit("workspace not found: " + WORKSPACE)

    files = []

    for root, _, names in os.walk(PARTICLES):
        for name in sorted(names):
            if name.endswith(".json"):
                files.append(os.path.join(root, name))

    files.sort()

    if args.filter:
        files = [f for f in files if args.filter.lower() in f.lower()]

    if args.limit:
        files = files[: args.limit]

    os.makedirs(TEXTURES, exist_ok=True)

    elements = []
    language = {}
    rejected = []
    placeholders = []
    copied = set()

    for path in files:
        relative = os.path.relpath(path, PARTICLES)
        source = open(path, encoding="utf-8").read()

        try:
            effect = json.loads(source)["particle_effect"]
            texture = effect["description"]["basic_render_parameters"]["texture"]
        except Exception as broken:
            rejected.append((relative, str(broken)))
            continue

        name = camel(relative.replace(".particle.json", "").replace(".json", ""))

        # The texture name carries its folder too: six different m1b.png would otherwise collapse
        # into one and five effects would silently draw the wrong picture.
        #
        # The vanilla atlas only gets the placeholder when the pack genuinely does not carry its
        # own copy of it - checked by file existence, not by name, so dropping a real
        # textures/particle/particles.png into the pack fixes every effect that names it without
        # touching this script again.
        if texture == VANILLA_ATLAS and not os.path.exists(os.path.join(PACK, texture + ".png")):
            texture_name = PLACEHOLDER
            placeholders.append(relative)
        else:
            texture_name = snake(camel(texture.replace("textures/particle/", "")))

        if texture_name not in copied:
            copied.add(texture_name)
            target = os.path.join(TEXTURES, texture_name + ".png")

            if texture_name == PLACEHOLDER:
                # 128 is the vanilla Bedrock atlas size, so UVs at least land inside the image.
                png(target, 128, (255, 0, 255, 160))
            else:
                origin = os.path.join(PACK, texture + ".png")

                if os.path.exists(origin):
                    shutil.copyfile(origin, target)
                else:
                    rejected.append((relative, "texture not found: " + texture))
                    continue

        write_element(name, "kashiparticle", {"particleJson": source, "texture": texture_name})
        elements.append((name, "kashiparticle"))

        if args.no_items:
            continue

        procedure = name + "Fire"
        item = name + "Item"

        write_element(procedure, "procedure",
                      {"procedurexml": procedure_xml(name), "skipDependencyNullCheck": False})
        write_element(item, "item", item_definition(name, procedure))

        elements.append((procedure, "procedure"))
        elements.append((item, "item"))
        language["item." + MODID + "." + snake(item)] = name

    # --- fold the new elements into the workspace file, keeping whatever was already there ---

    workspace = json.load(open(WORKSPACE_FILE, encoding="utf-8"))
    existing = {entry["name"] for entry in workspace["mod_elements"]}

    for name, kind in elements:
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

    # ------------------------------------------------------------------ report

    effects = sum(1 for _, kind in elements if kind == "kashiparticle")

    print("effects imported : %d" % effects)
    print("elements written : %d" % len(elements))
    print("textures copied  : %d" % len(copied))

    if placeholders:
        print()
        print("%d effect(s) draw from the vanilla Bedrock atlas, which is not in this pack."
              % len(placeholders))
        print("They import and play, but with a placeholder picture. Drop the real")
        print("particles.png in as %s.png to fix all of them at once:" % PLACEHOLDER)

        for name in placeholders[:8]:
            print("   " + name)

        if len(placeholders) > 8:
            print("   ... and %d more" % (len(placeholders) - 8))

    if rejected:
        print()
        print("%d file(s) skipped:" % len(rejected))

        for name, reason in rejected:
            print("   %s - %s" % (name, reason))


if __name__ == "__main__":
    main()
