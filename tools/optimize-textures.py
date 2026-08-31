"""Losslessly shrinks the PNG textures a KASHI Particle pack ships.

Why this exists: a real Bedrock pack's particle textures are large flipbook sprite sheets (some in
this project's own test pack run 8192x512 - a single 4.2 MB file), and 279 imported effects add up
to real weight in the generated mod's jar. Two independent, purely lossless techniques, applied per
file, cheapest first:

  1. Re-deflate (always attempted, effectively free): decompress the IDAT stream, recompress it at
     zlib level 9, leave every other byte of the file untouched. This never even looks at what the
     bytes mean as pixels - it is the exact same filtered scanline data, just packed tighter - so
     it is lossless by construction and, being pure zlib with no per-pixel Python/numpy work,
     stays fast even on an 8+ megapixel sheet.
  2. Palette reduction (attempted only up to MAX_INDEXING_PIXELS): if an RGB/RGBA image actually
     uses <= 256 distinct colours - very common for a stylised particle sprite sheet - re-encode
     it as indexed colour. This is where the big wins are (32 bits per pixel down to 8, before
     compression even factors in), but reconstructing real pixel values from two of the five PNG
     filter types has an inherently sequential dependency along each row that does not vectorise
     cleanly; measured at ~100s for one 8192x512 sheet, which is too slow to run unconditionally
     against a few hundred textures. The size cap keeps this to the images it can finish quickly;
     re-deflate alone still runs against everything.

Every optimized file is decoded back and compared against the original before it is trusted - byte
-for-byte for the re-deflate path, pixel-for-pixel for palette reduction. A single mismatch
discards the result and falls back to the original untouched: this is a hand-written PNG codec
exercised for the first time against a real, varied pack, so it is required to prove itself
correct on every file it touches rather than being trusted on faith.

This is a standalone maintenance tool, not part of what ships inside the plugin or a generated
mod, so it leans on numpy for the palette-reduction pixel math - the "no dependencies" rule that
keeps the Java runtime and plugin lean does not apply to an offline script like this one.

Usage:
    python tools/optimize-textures.py <folder>              # optimize every .png under folder
    python tools/optimize-textures.py <folder> --dry-run     # report savings, write nothing
    python tools/optimize-textures.py <folder> --no-palette  # re-deflate only, skip the slow path
"""

import argparse
import os
import struct
import sys
import time
import zlib

import numpy as np

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

# Palette reduction needs a full pixel decode, which is only fast up to a few megapixels (see the
# module docstring). Above this, re-deflate alone still applies - always fast, always attempted.
MAX_INDEXING_PIXELS = 2_000_000


def read_chunks(data):
    """Yields (tag: bytes, payload: bytes) for every chunk in a PNG byte string."""
    if data[:8] != PNG_SIGNATURE:
        raise ValueError("not a PNG file")

    i = 8

    while i < len(data):
        length = struct.unpack(">I", data[i:i + 4])[0]
        tag = data[i + 4:i + 8]
        payload = data[i + 8:i + 8 + length]

        yield tag, payload

        i += 8 + length + 4  # length + tag + payload + crc


def write_chunk(tag, payload):
    body = tag + payload

    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))


def parse_ihdr(data):
    for tag, payload in read_chunks(data):
        if tag == b"IHDR":
            width, height, bitdepth, colortype = struct.unpack(">IIBB", payload[:10])

            return width, height, bitdepth, colortype

    raise ValueError("no IHDR chunk")


# ------------------------------------------------------------ fast path: re-deflate

def redeflate(data):
    """Recompresses the IDAT stream at max zlib level, keeping every other chunk byte-identical.
    Returns the optimized bytes, or None if nothing was smaller. Verified by decompressing both
    the old and new IDAT and comparing the raw (still-filtered) bytes - no pixel decode needed,
    since this path never changes what those bytes mean."""
    idat = bytearray()
    other_chunks = []

    for tag, payload in read_chunks(data):
        if tag == b"IDAT":
            idat += payload
        elif tag != b"IEND":
            other_chunks.append((tag, payload))

    raw = zlib.decompress(bytes(idat))
    recompressed = zlib.compress(raw, 9)

    if zlib.decompress(recompressed) != raw:
        return None  # should be unreachable, but never trust silently

    if len(recompressed) >= len(idat):
        return None

    chunks = [write_chunk(tag, payload) for tag, payload in other_chunks]
    chunks.insert(1 if other_chunks and other_chunks[0][0] == b"IHDR" else 0,
                  write_chunk(b"IDAT", recompressed))

    return PNG_SIGNATURE + b"".join(chunks) + write_chunk(b"IEND", b"")


# ------------------------------------------------------- slow path: palette reduction

def unfilter(raw, width, height, channels):
    """Undoes the PNG per-scanline filter (spec section 9.2), returning a (height, width,
    channels) uint8 array. Filter type can differ row to row. Types 0 (None) and 2 (Up) are fully
    row-vectorised; type 1 (Sub) reduces to a per-channel cumulative sum across the row. Types 3
    (Average) and 4 (Paeth) depend on the just-reconstructed pixel to their own left, which numpy
    cannot express as a single call - reconstructed one pixel-column at a time, with every channel
    of that column across the row still handled as one vectorised op, so this is O(width) numpy
    calls per such row rather than O(width * channels) Python-level ones. This is the expensive
    part callers guard behind MAX_INDEXING_PIXELS.
    """
    stride = width * channels
    filter_types = np.empty(height, dtype=np.uint8)
    filtered = np.empty((height, stride), dtype=np.uint8)

    pos = 0

    for y in range(height):
        filter_types[y] = raw[pos]
        filtered[y] = np.frombuffer(raw, dtype=np.uint8, count=stride, offset=pos + 1)
        pos += 1 + stride

    out = np.zeros((height, stride), dtype=np.int64)
    prev_row = np.zeros(stride, dtype=np.int64)

    for y in range(height):
        row = filtered[y].astype(np.int64)
        ftype = filter_types[y]

        if ftype == 0:
            recon = row
        elif ftype == 2:
            recon = (row + prev_row) & 0xFF
        elif ftype == 1:
            recon = row.reshape(width, channels).copy()
            np.cumsum(recon, axis=0, out=recon)
            recon = (recon & 0xFF).reshape(stride)
        elif ftype == 3:
            recon = np.zeros(stride, dtype=np.int64)
            left = np.zeros(channels, dtype=np.int64)

            for x in range(width):
                s = slice(x * channels, x * channels + channels)
                up = prev_row[s]
                val = (row[s] + (left + up) // 2) & 0xFF
                recon[s] = val
                left = val
        elif ftype == 4:
            recon = np.zeros(stride, dtype=np.int64)
            left = np.zeros(channels, dtype=np.int64)
            up_left = np.zeros(channels, dtype=np.int64)

            for x in range(width):
                s = slice(x * channels, x * channels + channels)
                up = prev_row[s]
                p = left + up - up_left
                pa = np.abs(p - left)
                pb = np.abs(p - up)
                pc = np.abs(p - up_left)

                predictor = np.where(pa <= pb, np.where(pa <= pc, left, up_left),
                                      np.where(pb <= pc, up, up_left))

                val = (row[s] + predictor) & 0xFF
                recon[s] = val
                up_left = up
                left = val
        else:
            raise ValueError("unknown PNG filter type %d" % ftype)

        out[y] = recon
        prev_row = recon

    return out.astype(np.uint8).reshape(height, width, channels)


def decode_rgba(data):
    """Parses a PNG into (width, height, RGBA uint8 array of shape (height, width, 4))."""
    width, height, bitdepth, colortype = parse_ihdr(data)

    if bitdepth != 8:
        raise ValueError("only 8-bit PNGs are handled (found bitdepth=%d)" % bitdepth)

    channels_by_type = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}

    if colortype not in channels_by_type:
        raise ValueError("unsupported PNG colour type %d" % colortype)

    idat = bytearray()
    palette = None
    trns = None

    for tag, payload in read_chunks(data):
        if tag == b"IDAT":
            idat += payload
        elif tag == b"PLTE":
            palette = payload
        elif tag == b"tRNS":
            trns = payload

    channels = channels_by_type[colortype]
    raw = zlib.decompress(bytes(idat))
    pixels = unfilter(raw, width, height, channels)

    rgba = np.empty((height, width, 4), dtype=np.uint8)

    if colortype == 6:
        rgba[:] = pixels
    elif colortype == 2:
        rgba[:, :, :3] = pixels
        rgba[:, :, 3] = 255
    elif colortype == 0:
        rgba[:, :, 0] = rgba[:, :, 1] = rgba[:, :, 2] = pixels[:, :, 0]
        rgba[:, :, 3] = 255
    elif colortype == 4:
        rgba[:, :, 0] = rgba[:, :, 1] = rgba[:, :, 2] = pixels[:, :, 0]
        rgba[:, :, 3] = pixels[:, :, 1]
    elif colortype == 3:
        pal = np.frombuffer(palette, dtype=np.uint8).reshape(-1, 3)
        alpha = np.full(len(pal), 255, dtype=np.uint8)

        if trns:
            trns_arr = np.frombuffer(trns, dtype=np.uint8)
            alpha[:len(trns_arr)] = trns_arr

        index = pixels[:, :, 0]
        rgba[:, :, :3] = pal[index]
        rgba[:, :, 3] = alpha[index]

    return width, height, rgba


def encode_indexed(width, height, rgba):
    """Re-encodes an (height, width, 4) RGBA array as an indexed-colour PNG, or returns None if
    it uses more than 256 distinct colours. Alpha is part of the colour key: two pixels that only
    differ in transparency are two different palette entries, not the same one."""
    flat = rgba.reshape(-1, 4)
    colours, indices = np.unique(flat, axis=0, return_inverse=True)

    if len(colours) > 256:
        return None

    idx_image = indices.reshape(height, width).astype(np.uint8)
    filtered = np.concatenate(
        [np.zeros((height, 1), dtype=np.uint8), idx_image], axis=1)  # filter-type byte 0 per row
    idat = zlib.compress(filtered.tobytes(), 9)

    plte = colours[:, :3].tobytes()
    chunks = [write_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0)),
              write_chunk(b"PLTE", plte)]

    if np.any(colours[:, 3] != 255):
        chunks.append(write_chunk(b"tRNS", colours[:, 3].tobytes()))

    chunks.append(write_chunk(b"IDAT", idat))
    chunks.append(write_chunk(b"IEND", b""))

    return PNG_SIGNATURE + b"".join(chunks)


def palette_reduce(data):
    """Returns indexed-colour bytes if the image fits a 256-colour palette and is small enough to
    decode in reasonable time, verified pixel-for-pixel; otherwise None."""
    width, height, _, _ = parse_ihdr(data)

    if width * height > MAX_INDEXING_PIXELS:
        return None

    width, height, rgba = decode_rgba(data)
    candidate = encode_indexed(width, height, rgba)

    if candidate is None:
        return None

    check_width, check_height, check_rgba = decode_rgba(candidate)

    if check_width != width or check_height != height or not np.array_equal(check_rgba, rgba):
        return None  # the codec disagreed with itself - discard rather than risk it

    return candidate


# ---------------------------------------------------------------------- driver

def optimize(data, allow_palette=True):
    """Returns (optimized_bytes, method) for one PNG's raw bytes, or (None, reason)."""
    try:
        parse_ihdr(data)
    except Exception as unreadable:
        return None, "not touched (%s)" % unreadable

    candidates = []

    try:
        fast = redeflate(data)

        if fast is not None:
            candidates.append(("re-deflated", fast))
    except Exception as broke:
        return None, "re-deflate failed (%s)" % broke

    if allow_palette:
        try:
            indexed = palette_reduce(data)

            if indexed is not None:
                candidates.append(("indexed palette", indexed))
        except Exception:
            pass  # the fast path alone is still a valid result; do not let this sink it

    if not candidates:
        return None, "already as small as this tool can make it"

    label, best = min(candidates, key=lambda pair: len(pair[1]))

    return best, label


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", help="folder to scan recursively for .png files")
    parser.add_argument("--dry-run", action="store_true", help="report only, write nothing")
    parser.add_argument("--no-palette", action="store_true",
                        help="re-deflate only; skip the slower palette-reduction pass entirely")
    args = parser.parse_args()

    if not os.path.isdir(args.folder):
        sys.exit("not a folder: " + args.folder)

    total_before = 0
    total_after = 0
    touched = 0
    skipped = []
    started = time.time()

    for root, _, names in os.walk(args.folder):
        for name in sorted(names):
            if not name.lower().endswith(".png"):
                continue

            path = os.path.join(root, name)
            original = open(path, "rb").read()

            try:
                result, label = optimize(original, allow_palette=not args.no_palette)
            except Exception as broken:
                skipped.append((path, "error: %s" % broken))
                continue

            if result is None:
                skipped.append((path, label))
                continue

            total_before += len(original)
            total_after += len(result)
            touched += 1

            saved_pct = 100 * (1 - len(result) / len(original))
            print("%-60s %9d -> %9d bytes  (-%.0f%%, %s)" %
                  (os.path.relpath(path, args.folder), len(original), len(result), saved_pct, label))

            if not args.dry_run:
                open(path, "wb").write(result)

    print()
    print("optimized  : %d file(s) in %.1fs" % (touched, time.time() - started))

    if touched:
        print("total       : %d -> %d bytes (-%.1f%%)" %
              (total_before, total_after, 100 * (1 - total_after / total_before) if total_before else 0))

    if skipped:
        print("not changed: %d file(s)" % len(skipped))

        for path, reason in skipped[:10]:
            print("   %s - %s" % (os.path.relpath(path, args.folder), reason))

        if len(skipped) > 10:
            print("   ... and %d more" % (len(skipped) - 10))

    if args.dry_run:
        print("\n(dry run - nothing was written)")


if __name__ == "__main__":
    main()
