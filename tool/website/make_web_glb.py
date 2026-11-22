"""Makes the website's copy of the 3D athlete.

The app's GLB (assets/figure/athlete.glb) stores data for its own renderer
in the vertex colours: baked ambient occlusion in the red channel and a
skin-warmth weight in the green one. A standard glTF viewer multiplies the
base colour by the vertex colour, which would tint the body red and yellow.
This writes a copy whose vertex colours are plain grey occlusion (lifted so
creases darken without going black), which any viewer shows correctly.

The app also treats the material colours as sRGB, while glTF defines
baseColorFactor as linear, so the copy converts them; otherwise a web viewer
shows the skin and clothes washed out.

Usage (from the repository root):

    python3 tool/website/make_web_glb.py assets/figure/athlete.glb website/assets/athlete.glb

Re-run it whenever assets/figure/athlete.glb is rebuilt.
"""

import json
import struct
import sys

# Darkest an occluded vertex gets (1.0 = no occlusion shading at all).
_FLOOR = 0.42


def _chunks(data):
    magic, version, _ = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67 or version != 2:
        raise SystemExit("not a glTF 2.0 binary")
    offset = 12
    chunks = []
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        chunks.append((kind, bytearray(data[offset + 8 : offset + 8 + length])))
        offset += 8 + length
    return chunks


def _linear(channel):
    """sRGB component (0-1) to linear light."""
    if channel <= 0.04045:
        return channel / 12.92
    return ((channel + 0.055) / 1.055) ** 2.4


def _pad(payload, fill):
    return payload + fill * ((4 - len(payload) % 4) % 4)


def convert(src, dst):
    with open(src, "rb") as f:
        chunks = _chunks(f.read())
    doc = json.loads(chunks[0][1].decode("utf-8"))
    binary = chunks[1][1]

    done = set()
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            index = prim["attributes"].get("COLOR_0")
            if index is None or index in done:
                continue
            done.add(index)
            acc = doc["accessors"][index]
            if acc["componentType"] != 5123 or acc["type"] != "VEC4":
                raise SystemExit("expected normalised uint16 VEC4 vertex colours")
            view = doc["bufferViews"][acc["bufferView"]]
            stride = view.get("byteStride", 8)
            base = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
            for i in range(acc["count"]):
                at = base + i * stride
                occlusion = struct.unpack_from("<H", binary, at)[0] / 65535
                grey = round((_FLOOR + (1 - _FLOOR) * occlusion) * 65535)
                struct.pack_into("<HHHH", binary, at, grey, grey, grey, 65535)

    for material in doc.get("materials", []):
        pbr = material.get("pbrMetallicRoughness", {})
        factor = pbr.get("baseColorFactor")
        if factor:
            pbr["baseColorFactor"] = [round(_linear(c), 5) for c in factor[:3]] + [
                factor[3]
            ]

    doc["asset"]["generator"] = (
        doc["asset"].get("generator", "") + " + levelex make_web_glb"
    )
    text = _pad(json.dumps(doc, separators=(",", ":")).encode("utf-8"), b" ")
    binary = _pad(bytes(binary), b"\0")
    total = 12 + 8 + len(text) + 8 + len(binary)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(text), 0x4E4F534A))
        f.write(text)
        f.write(struct.pack("<II", len(binary), 0x004E4942))
        f.write(binary)
    print(f"{dst}: {total} bytes, {len(done)} colour sets converted")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    convert(sys.argv[1], sys.argv[2])
