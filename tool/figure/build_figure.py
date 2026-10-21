"""Builds the Levelex athlete: a rigged, skinned human body with named
muscle-group materials and one animation per MY PT clip, exported as
assets/figure/athlete.glb.

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b -P tool/figure/build_figure.py -- \
      --poses tool/figure/poses.json --out assets/figure/athlete.glb [--previews DIR]

The body is sculpted from overlapping muscle volumes (ellipsoids and
capsules placed on the rest-pose skeleton exported from the Dart rig), fused
with a voxel remesh, smoothed and decimated, then weighted to an armature
whose bones follow the same joints. Every clip's keyframes come from
poses.json, so the body moves exactly like the verified capsule mannequin.
Coordinates: the rig is Y-up facing +Z; Blender is Z-up, and the glTF
exporter (Y-up) maps Blender (x, y, z) -> (x, z, -y), so we build with
blender = (rigX, -rigZ, rigY).
"""
import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

# ----------------------------------------------------------------------------
# Arguments
# ----------------------------------------------------------------------------
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument("--poses", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--previews", default=None)
ap.add_argument("--voxel", type=float, default=0.013)
ap.add_argument("--tris", type=int, default=14000)
ap.add_argument("--base-tris", type=int, default=36000)
ap.add_argument("--fps", type=int, default=30)
ap.add_argument("--base", default=None, help="Blender file with a human base mesh (CC0 Human Base Meshes bundle)")
ap.add_argument("--base-object", default="GEO-body_male_realistic")
ap.add_argument("--no-ao", action="store_true")
args = ap.parse_args(argv)

with open(args.poses) as f:
    POSES = json.load(f)
REST = {k: Vector(v) for k, v in POSES["rest"].items()}
HEAD_R = POSES["headRadius"]


def B(v):
    """Rig (Y-up, +Z front) -> Blender (Z-up, -Y front)."""
    return Vector((v[0], -v[2], v[1]))


# ----------------------------------------------------------------------------
# Scene reset
# ----------------------------------------------------------------------------
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.fps = args.fps
scene.unit_settings.system = "METRIC"

R = REST
Z = Vector((0, 0, 1))  # rig forward (toward the camera)


def lerp(a, b, t):
    return a + (b - a) * t


HOOKS = {}

GROUP_COLORS = {
    "skin": (0.78, 0.66, 0.58, 1.0),
    "sclera": (0.93, 0.93, 0.92, 1.0),
    "iris": (0.22, 0.14, 0.09, 1.0),
    "hair": (0.16, 0.12, 0.09, 1.0),
    "shirt": (0.26, 0.31, 0.40, 1.0),
    "shorts": (0.11, 0.12, 0.15, 1.0),
    # muscles under the clothes: "<garment>.<muscle>" so the app can light
    # the muscle through the cloth
    "shirt.chest": (0.26, 0.31, 0.40, 1.0),
    "shirt.back": (0.26, 0.31, 0.40, 1.0),
    "shirt.core": (0.26, 0.31, 0.40, 1.0),
    "shirt.shoulders": (0.26, 0.31, 0.40, 1.0),
    "shorts.glutes": (0.11, 0.12, 0.15, 1.0),
    "shorts.quads": (0.11, 0.12, 0.15, 1.0),
    "shorts.hamstrings": (0.11, 0.12, 0.15, 1.0),
    "chest": (0.80, 0.62, 0.55, 1.0),
    "back": (0.80, 0.62, 0.55, 1.0),
    "shoulders": (0.80, 0.62, 0.55, 1.0),
    "biceps": (0.80, 0.62, 0.55, 1.0),
    "triceps": (0.80, 0.62, 0.55, 1.0),
    "core": (0.80, 0.62, 0.55, 1.0),
    "glutes": (0.80, 0.62, 0.55, 1.0),
    "quads": (0.80, 0.62, 0.55, 1.0),
    "hamstrings": (0.80, 0.62, 0.55, 1.0),
    "calves": (0.80, 0.62, 0.55, 1.0),
}


def add_materials(body):
    mats = {}
    for name, col in GROUP_COLORS.items():
        m = bpy.data.materials.new(name)
        if hasattr(m, "use_nodes") and not m.use_nodes:
            m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF") if m.node_tree else None
        if bsdf:
            bsdf.inputs["Base Color"].default_value = col
            bsdf.inputs["Roughness"].default_value = 0.55
        mats[name] = m
        body.data.materials.append(m)
    return {name: i for i, name in enumerate(GROUP_COLORS)}


def build_procedural():
    """The original sculpt: skin modifier over a stick skeleton."""
    global R
    # ----------------------------------------------------------------------------
    # Body: skin modifier over an anatomical stick skeleton
    # ----------------------------------------------------------------------------
    # Each skeleton vertex: (name, rig position, (radius_x, radius_depth)).
    # The Skin modifier wraps the edges in a smooth, unified quad surface with
    # elliptical cross-sections; Subdivision rounds it; muscle volumes then push
    # the surface outward where a muscle sits, and the same volumes decide the
    # material (muscle group) of every face.




    SK = []  # (name, Vector, (rx, rd))
    SE = []  # (nameA, nameB)


    def sv(name, pos, rx, rd=None):
        SK.append((name, Vector(pos), (rx, rd if rd is not None else rx)))


    def se(a, b):
        SE.append((a, b))


    pelvis, chest, neck, head = R["pelvis"], R["chest"], R["neck"], R["head"]
    # Trunk
    sv("crotch", pelvis + Vector((0, -0.07, 0.0)), 0.085, 0.075)
    sv("pelvis", pelvis + Vector((0, 0.0, -0.005)), 0.148, 0.1)
    sv("waist", lerp(pelvis, chest, 0.33) - 0.01 * Z, 0.117, 0.086)
    sv("ribs", lerp(pelvis, chest, 0.64) - 0.015 * Z, 0.158, 0.108)
    sv("chest", lerp(pelvis, chest, 0.88) - 0.01 * Z, 0.178, 0.11)
    sv("clav", chest + Vector((0, 0.03, -0.005)), 0.142, 0.088)
    sv("neck0", neck - Vector((0, 0.03, 0.005)), 0.066, 0.066)
    sv("neck1", lerp(neck, head, 0.3) - 0.005 * Z, 0.062, 0.064)
    sv("head", head + Vector((0, 0.0, 0.008)), 0.116, 0.126)
    sv("crown", head + Vector((0, 0.08, -0.012)), 0.092, 0.095)
    sv("chin", head + Vector((0, -0.1, 0.04)), 0.056, 0.052)
    for a, b in (("crotch", "pelvis"), ("pelvis", "waist"), ("waist", "ribs"), ("ribs", "chest"), ("chest", "clav"), ("clav", "neck0"), ("neck0", "neck1"), ("neck1", "head"), ("head", "crown"), ("head", "chin")):
        se(a, b)
    # Arms
    for side in ("L", "R"):
        s_ = 1 if side == "L" else -1
        sh, el, wr, ha = R["shoulder" + side], R["elbow" + side], R["wrist" + side], R["hand" + side]
        sv("shoulder" + side, sh + Vector((s_ * 0.012, 0.012, 0)), 0.072, 0.072)
        sv("uarm" + side, lerp(sh, el, 0.45), 0.056, 0.053)
        sv("elbow" + side, el, 0.042, 0.042)
        sv("farm" + side, lerp(el, wr, 0.3), 0.046, 0.043)
        sv("wrist" + side, wr, 0.032, 0.026)
        sv("hand" + side, ha, 0.046, 0.02)
        sv("fingers" + side, ha + (ha - wr).normalized() * 0.045, 0.038, 0.014)
        se("clav", "shoulder" + side)
        se("shoulder" + side, "uarm" + side)
        se("uarm" + side, "elbow" + side)
        se("elbow" + side, "farm" + side)
        se("farm" + side, "wrist" + side)
        se("wrist" + side, "hand" + side)
        se("hand" + side, "fingers" + side)
    # Legs
    for side in ("L", "R"):
        hp, kn, an, to = R["hip" + side], R["knee" + side], R["ankle" + side], R["toe" + side]
        sv("hip" + side, hp + Vector((0, -0.02, 0)), 0.088, 0.09)
        sv("thigh" + side, lerp(hp, kn, 0.45), 0.078, 0.082)
        sv("knee" + side, kn, 0.056, 0.06)
        sv("calf" + side, lerp(kn, an, 0.32), 0.056, 0.062)
        sv("shin" + side, lerp(kn, an, 0.72), 0.04, 0.045)
        sv("ankle" + side, an + Vector((0, 0.03, 0)), 0.036, 0.04)
        sv("heel" + side, an + Vector((0, 0.0, -0.035)), 0.035, 0.03)
        sv("toe" + side, to + Vector((0, 0.022, 0.0)), 0.042, 0.02)
        se("pelvis", "hip" + side)
        se("hip" + side, "thigh" + side)
        se("thigh" + side, "knee" + side)
        se("knee" + side, "calf" + side)
        se("calf" + side, "shin" + side)
        se("shin" + side, "ankle" + side)
        se("ankle" + side, "heel" + side)
        se("ankle" + side, "toe" + side)

    names = [v[0] for v in SK]
    index = {n: i for i, n in enumerate(names)}
    me = bpy.data.meshes.new("AthleteSkeleton")
    me.from_pydata([tuple(B(v[1])) for v in SK], [(index[a], index[b]) for a, b in SE], [])
    me.update()
    body = bpy.data.objects.new("Athlete", me)
    bpy.context.collection.objects.link(body)
    bpy.context.view_layer.objects.active = body
    body.select_set(True)
    skin_mod = body.modifiers.new("Skin", "SKIN")
    skin_mod.use_smooth_shade = True
    skin_mod.branch_smoothing = 0.6
    for i, v in enumerate(SK):
        rx, rd = v[2]
        sk = me.skin_vertices[0].data[i]
        sk.radius = (rx, rd)
        sk.use_root = v[0] == "pelvis"
        sk.use_loose = False
    sub = body.modifiers.new("Subdivision", "SUBSURF")
    sub.levels = 3
    sub.render_levels = 3
    bpy.ops.object.modifier_apply(modifier=skin_mod.name)
    bpy.ops.object.modifier_apply(modifier=sub.name)
    sm = body.modifiers.new("Smooth", "SMOOTH")
    sm.factor = 0.5
    sm.iterations = 4
    bpy.ops.object.modifier_apply(modifier=sm.name)
    print(f"[figure] skin body: {len(body.data.vertices)} verts, {len(body.data.polygons)} faces")

    # ----------------------------------------------------------------------------
    # Muscle volumes: displacement + material
    # ----------------------------------------------------------------------------
    # (group, centre, radii, amplitude in metres)
    MUSCLES = []


    def mus(group, centre, radii, amp):
        MUSCLES.append((group, B(Vector(centre)), Vector((radii[0], radii[2], radii[1])), amp))


    sh_l, sh_r = R["shoulderL"], R["shoulderR"]
    mus("back", chest + Vector((0, 0.02, -0.06)), (0.16, 0.07, 0.07), 0.006)  # traps
    for s_ in (1, -1):
        mus("back", Vector((s_ * 0.1, chest.y - 0.2, chest.z - 0.075)), (0.085, 0.15, 0.06), 0.012)  # lats
        mus("chest", Vector((s_ * 0.078, chest.y - 0.085, chest.z + 0.095)), (0.085, 0.062, 0.045), 0.02)  # pecs
        mus("core", Vector((s_ * 0.095, pelvis.y + 0.2, pelvis.z + 0.075)), (0.045, 0.13, 0.035), 0.004)  # obliques
        mus("glutes", Vector((s_ * 0.08, pelvis.y - 0.03, pelvis.z - 0.085)), (0.085, 0.09, 0.075), 0.011)
    for k in range(4):  # abdominal blocks
        y = pelvis.y + 0.1 + k * 0.075
        for s_ in (1, -1):
            mus("core", Vector((s_ * 0.035, y, pelvis.z + 0.085)), (0.038, 0.034, 0.03), 0.009)
    for side, sh, el, wr in (("L", sh_l, R["elbowL"], R["wristL"]), ("R", sh_r, R["elbowR"], R["wristR"])):
        out = Vector((1 if side == "L" else -1, 0, 0))
        mus("shoulders", sh + out * 0.032 + Vector((0, 0.018, 0)), (0.078, 0.072, 0.078), 0.015)
        mus("biceps", lerp(sh, el, 0.52) + Z * 0.028, (0.05, 0.1, 0.045), 0.016)
        mus("triceps", lerp(sh, el, 0.5) - Z * 0.03, (0.05, 0.105, 0.045), 0.01)
    for side, hp, kn, an in (("L", R["hipL"], R["kneeL"], R["ankleL"]), ("R", R["hipR"], R["kneeR"], R["ankleR"])):
        mus("quads", lerp(hp, kn, 0.5) + Z * 0.04, (0.08, 0.21, 0.055), 0.016)
        mus("hamstrings", lerp(hp, kn, 0.52) - Z * 0.04, (0.072, 0.2, 0.05), 0.01)
        mus("calves", lerp(kn, an, 0.36) - Z * 0.035, (0.058, 0.13, 0.05), 0.015)


    def norm_dist(p, c, r):
        d = p - c
        return math.sqrt((d.x / r.x) ** 2 + (d.y / r.y) ** 2 + (d.z / r.z) ** 2)


    mesh = body.data
    mesh.calc_normals_split() if hasattr(mesh, "calc_normals_split") else None
    vnormals = [v.normal.copy() for v in mesh.vertices]
    for v, n in zip(mesh.vertices, vnormals):
        push = 0.0
        for group, c, r, amp in MUSCLES:
            d = norm_dist(v.co, c, r)
            if d < 1.25:
                # smooth bump: 1 inside the core, fading to 0 at 1.25
                w = 1.0 if d < 0.7 else max(0.0, 1.0 - (d - 0.7) / 0.55)
                push = max(push, amp * (w * w * (3 - 2 * w)))
        if push > 0:
            v.co = v.co + n * push
    mesh.update()

    # Simplify to the budget and smooth-shade.
    tri_count = sum(len(p.vertices) - 2 for p in mesh.polygons)
    dm = body.modifiers.new("Decimate", "DECIMATE")
    dm.ratio = min(1.0, args.tris / max(tri_count, 1))
    dm.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=dm.name)
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.shade_smooth()
    print(f"[figure] body: {len(body.data.vertices)} verts, {len(body.data.polygons)} faces (from {tri_count} tris)")

    GROUP_COLORS = {
        "skin": (0.78, 0.66, 0.58, 1.0),
        "chest": (0.80, 0.62, 0.55, 1.0),
        "back": (0.80, 0.62, 0.55, 1.0),
        "shoulders": (0.80, 0.62, 0.55, 1.0),
        "biceps": (0.80, 0.62, 0.55, 1.0),
        "triceps": (0.80, 0.62, 0.55, 1.0),
        "core": (0.80, 0.62, 0.55, 1.0),
        "glutes": (0.80, 0.62, 0.55, 1.0),
        "quads": (0.80, 0.62, 0.55, 1.0),
        "hamstrings": (0.80, 0.62, 0.55, 1.0),
        "calves": (0.80, 0.62, 0.55, 1.0),
    }
    mats = {}
    for name, col in GROUP_COLORS.items():
        m = bpy.data.materials.new(name)
        if hasattr(m, "use_nodes") and not m.use_nodes:
            m.use_nodes = True
        bsdf = m.node_tree.nodes.get("Principled BSDF") if m.node_tree else None
        if bsdf:
            bsdf.inputs["Base Color"].default_value = col
            bsdf.inputs["Roughness"].default_value = 0.55
        mats[name] = m
        body.data.materials.append(m)
    mat_index = {name: i for i, name in enumerate(GROUP_COLORS)}
    mw = body.matrix_world
    for poly in body.data.polygons:
        centre = mw @ poly.center
        best, best_s = "skin", 1.3
        for group, c, r, amp in MUSCLES:
            sc = norm_dist(centre, c, r)
            if sc < best_s:
                best, best_s = group, sc
        poly.material_index = mat_index[best]

    return body, REST


# ----------------------------------------------------------------------------
# Body from a real human base mesh (Blender Studio "Human Base Meshes", CC0)
# ----------------------------------------------------------------------------
# Face sets of GEO-body_male_realistic v1.4.1 (sculpt face sets, FACE/INT).
BASE_SETS = {
    "head": 17, "torso": 1, "abdomen": 19, "pelvis": 18,
    "upperArmR": 20, "upperArmL": 21, "forearmR": 11, "forearmL": 12,
    "handR": 10, "handL": 9, "thighR": 23, "thighL": 24,
    "shinR": 16, "shinL": 15, "footR": 13, "footL": 14,
}


def build_from_base(path, name):
    """Appends the base mesh, fits the rig joints to its face sets, scales it
    to the rig's hip height, joins the eyes, simplifies and assigns muscle
    materials. Returns (body, joints in rig coordinates)."""
    with bpy.data.libraries.load(path, link=False) as (src, dst):
        wanted = [name, name + ".eye.L", name + ".eye.R"]
        dst.objects = [n for n in wanted if n in src.objects]
    objs = [o for o in dst.objects if o is not None]
    for o in objs:
        bpy.context.scene.collection.objects.link(o)
    body = next(o for o in objs if o.name == name)
    eyes = [o for o in objs if o is not body]
    # The bundle lays its bodies out in a row: put this one on the origin
    # (the eyes are parented to it and follow).
    body.matrix_world = Matrix.Identity(4)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    for m in list(body.modifiers):
        if m.type == "MULTIRES":
            m.levels = 1
            m.sculpt_levels = 1
            m.render_levels = 1
            bpy.ops.object.modifier_apply(modifier=m.name)
        else:
            body.modifiers.remove(m)
    me = body.data
    fs = me.attributes.get(".sculpt_face_set")
    if fs is None:
        raise RuntimeError("base mesh has no face sets")
    face_set = [fs.data[i].value for i in range(len(me.polygons))]
    print(f"[figure] base mesh: {len(me.vertices)} verts, {len(me.polygons)} faces, {len(set(face_set))} face sets")
    # vertex -> face sets it touches
    vsets = [set() for _ in me.vertices]
    for poly, sid in zip(me.polygons, face_set):
        for v in poly.vertices:
            vsets[v].add(sid)

    def boundary(a, b):
        pts = [me.vertices[i].co for i, ss in enumerate(vsets) if a in ss and b in ss]
        if not pts:
            raise RuntimeError(f"no boundary between face sets {a} and {b}")
        return sum(pts, Vector()) / len(pts)

    def centroid(sid):
        pts = [me.vertices[i].co for i, ss in enumerate(vsets) if sid in ss]
        return sum(pts, Vector()) / len(pts)

    S = BASE_SETS
    J = {}
    for side in ("L", "R"):
        J["shoulder" + side] = boundary(S["torso"], S["upperArm" + side])
        J["elbow" + side] = boundary(S["upperArm" + side], S["forearm" + side])
        J["wrist" + side] = boundary(S["forearm" + side], S["hand" + side])
        J["hip" + side] = boundary(S["pelvis"], S["thigh" + side])
        J["knee" + side] = boundary(S["thigh" + side], S["shin" + side])
        J["ankle" + side] = boundary(S["shin" + side], S["foot" + side])
        sx = 1 if side == "L" else -1
        wrist = J["wrist" + side]
        tips = [v.co for v in me.vertices if v.co.x * sx > 0.3 and v.co.z < wrist.z + 0.02 and v.co.z > 0.5]
        tip = min(tips, key=lambda c: c.z) if tips else wrist + Vector((0, 0, -0.15))
        J["hand" + side] = wrist + (tip - wrist) * 0.45
        toes = [v.co for v in me.vertices if v.co.x * sx > 0.08 and v.co.z < 0.06]
        J["toe" + side] = min(toes, key=lambda c: c.y) if toes else J["ankle" + side] + Vector((0, -0.2, -0.03))
    # Relax the hands: the base mesh splays the fingers; close the spread
    # and curl them slightly toward the palm so they read as a relaxed hand
    # rather than jazz hands in every pose.
    for side in ("L", "R"):
        sid = S["hand" + side]
        idx = [i for i, ss in enumerate(vsets) if sid in ss]
        pts = [me.vertices[i].co.copy() for i in idx]
        wrist = J["wrist" + side]
        tip_z = min(pt.z for pt in pts)
        cx = sum(pt.x for pt in pts) / len(pts)
        cy = sum(pt.y for pt in pts) / len(pts)
        knuckle_z = wrist.z - 0.42 * (wrist.z - tip_z)
        span = max(knuckle_z - tip_z, 1e-6)
        tip_i = min(idx, key=lambda i: me.vertices[i].co.z)
        tip = me.vertices[tip_i].co.copy()
        # pick the curl direction that moves the fingertips toward the body
        best_sign, best_dx = 1, None
        for sign in (1, -1):
            ang = sign * math.radians(40)
            dx, dz = tip.x - cx, tip.z - knuckle_z
            nx = cx + dx * math.cos(ang) - dz * math.sin(ang)
            if best_dx is None or abs(nx) < best_dx:
                best_dx, best_sign = abs(nx), sign
        for i in idx:
            v = me.vertices[i]
            if v.co.z >= knuckle_z:
                continue
            t = min(1.0, (knuckle_z - v.co.z) / span)
            y = cy + (v.co.y - cy) * (1 - 0.55 * t)
            ang = best_sign * math.radians(40) * t
            dx, dz = v.co.x - cx, v.co.z - knuckle_z
            x = cx + dx * math.cos(ang) - dz * math.sin(ang)
            z = knuckle_z + dx * math.sin(ang) + dz * math.cos(ang)
            v.co = Vector((x, y, z))
    print("[figure] hands relaxed")
    J["pelvis"] = (J["hipL"] + J["hipR"]) / 2
    J["chest"] = (J["shoulderL"] + J["shoulderR"]) / 2 + Vector((0, 0, 0.02))
    # Standing straight: the pelvis is upright and faces -Y in Blender,
    # which is +Z in rig coordinates after `rig()` below.
    pelvis_axes = {"pelvisUp": Vector((0, 1, 0)), "pelvisFwd": Vector((0, 0, 1))}
    J["neck"] = boundary(S["torso"], S["head"])
    # The rig's head bone points straight up from the neck; put the head
    # joint directly above the neck (not at the skull centroid, which sits
    # forward of it) so the face looks ahead instead of tilting back.
    head_top = max(me.vertices[i].co.z for i, ss in enumerate(vsets) if S["head"] in ss)
    J["head"] = Vector((J["neck"].x, J["neck"].y, head_top - 0.09))
    # Blender (x, y, z) -> rig (x, z, -y), scaled so the hips sit at the
    # rig's hip height (feet then meet the floor in standing poses).
    scale = REST["pelvis"].y / J["pelvis"].z
    print(f"[figure] base scale {scale:.3f}; hip z {J['pelvis'].z:.3f}")

    def rig(v):
        return Vector((v.x * scale, v.z * scale, -v.y * scale))

    joints = {k: rig(v) for k, v in J.items()}
    joints.update(pelvis_axes)
    # keep the face-set ids in a plain attribute (the join drops the sculpt
    # one), mark eyes, join them in, then scale the object
    fset = me.attributes.new("fset", "INT", "FACE")
    for i in range(len(me.polygons)):
        fset.data[i].value = face_set[i]
    is_eye = me.attributes.new("is_eye", "INT", "FACE")
    for eye in eyes:
        fa = eye.data.attributes.new("fset", "INT", "FACE")
        for i in range(len(eye.data.polygons)):
            fa.data[i].value = -1
        a = eye.data.attributes.new("is_eye", "INT", "FACE")
        for i in range(len(eye.data.polygons)):
            a.data[i].value = 1
    bpy.ops.object.select_all(action="DESELECT")
    for eye in eyes:
        eye.select_set(True)
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    if eyes:
        bpy.ops.object.join()
    body.scale = (scale, scale, scale)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    me = body.data
    # Simplify first, so the clothing and hair lines below are cut into the
    # mesh the app draws (cutting before the decimation leaves a sawtooth
    # wherever a collapse crosses the line).
    tri_count = sum(len(p.vertices) - 2 for p in me.polygons)
    dm = body.modifiers.new("Decimate", "DECIMATE")
    dm.ratio = min(1.0, args.base_tris / max(tri_count, 1))
    dm.use_collapse_triangulate = True
    dm.use_symmetry = True
    dm.symmetry_axis = "X"
    bpy.ops.object.modifier_apply(modifier=dm.name)
    me = body.data
    fs = me.attributes.get("fset")
    eye_attr = me.attributes.get("is_eye")
    if fs is None:
        raise RuntimeError("face-set attribute lost in decimation")
    mat_index = add_materials(body)
    inv = {v: k for k, v in S.items()}
    P = {k: B(v) for k, v in joints.items()}  # scaled Blender coordinates
    head_set = S["head"]

    # Eyes: the front cap of each eyeball is the iris.
    eye_front = {}
    eye_z = None
    if eye_attr is not None:
        for i, poly in enumerate(me.polygons):
            if eye_attr.data[i].value != 1:
                continue
            side = "L" if poly.center.x > 0 else "R"
            c = poly.center
            if side not in eye_front or c.y < eye_front[side]:
                eye_front[side] = c.y
            eye_z = c.z if eye_z is None else (eye_z + c.z) / 2
    head_top = max(
        me.vertices[j].co.z
        for i, poly in enumerate(me.polygons)
        if fs.data[i].value == head_set
        for j in poly.vertices
    )
    ear_z = eye_z if eye_z is not None else head_top - 0.12

    def hairline_y(z):
        # The hairline runs diagonally from the sideburn (just above ear
        # level, at the temple) up to the front corner of the crown.
        lo, hi = ear_z + 0.012, head_top - 0.045
        t = min(1.0, max(0.0, (z - lo) / max(1e-6, hi - lo)))
        return -0.03 + (-0.1 - -0.03) * t

    # Smooth scalar fields; each boundary is the zero line of one of them
    # (positive = hair / cloth). The mesh is split along those lines so the
    # neckline, sleeves and hems are clean curves instead of face-set
    # zigzags.
    chest, neck = P["chest"], P["neck"]
    neck_axis = (neck - chest).normalized()

    def f_collar(p):
        d = p - chest
        radial = (d - neck_axis * d.dot(neck_axis)).length
        front = max(0.0, min(1.0, (chest.y - p.y) / 0.06))  # -Y is front
        return radial - (0.07 + 0.03 * front)

    def f_sleeve(p, side):
        s0, e0 = P["shoulder" + side], P["elbow" + side]
        return 0.13 - (p - s0).dot((e0 - s0).normalized())

    # T-shirt hem a little above the hip joints, so the trunks show.
    hem_z = (P["hipL"].z + P["hipR"].z) / 2 + 0.03

    def f_hem(p):
        return p.z - hem_z

    def f_shorts(p, side):
        h0, k0 = P["hip" + side], P["knee" + side]
        return 0.27 - (p - h0).dot((k0 - h0).normalized())

    def f_hair(p):
        return max(
            p.z - (head_top - 0.045),
            min(p.z - (ear_z + 0.012), p.y - hairline_y(p.z)),
        )

    def field(kind, p, region, eye):
        if eye:
            return -1.0
        if kind == "collar":
            return f_collar(p) if region == "torso" else 1.0
        if kind == "sleeve":
            if region and region.startswith("upperArm"):
                return f_sleeve(p, region[-1])
            return 1.0
        if kind == "hem":
            if region in ("abdomen", "pelvis", "thighL", "thighR"):
                return f_hem(p)
            return 1.0
        if kind == "shorts":
            if region and region.startswith("thigh"):
                return f_shorts(p, region[-1])
            return 1.0
        return f_hair(p) if region == "head" else -1.0

    # The cuts and the per-face materials wait until the body is weighted:
    # bone-heat weighting wants the untouched decimated mesh, and the new
    # boundary vertices then inherit interpolated weights and occlusion.
    def finish_materials():
        nonlocal me
        me = body.data
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(me)
        fl = bm.faces.layers.int.get("fset")
        el = bm.faces.layers.int.get("is_eye")

        def vert_region(v):
            for f in v.link_faces:
                if el is not None and f[el] == 1:
                    return None, True
                return inv.get(f[fl]), False
            return None, False

        added = 0
        for kind in ("collar", "sleeve", "hem", "shorts", "hair"):
            vals = {}
            for v in bm.verts:
                region, eye = vert_region(v)
                vals[v] = field(kind, v.co, region, eye)
            new = []
            for e in list(bm.edges):
                a, b = e.verts
                fa, fb = vals[a], vals[b]
                if fa * fb < 0:
                    frac = min(0.98, max(0.02, fa / (fa - fb)))
                    _, nv = bmesh.utils.edge_split(e, a, frac)
                    new.append(nv)
            if new:
                bmesh.ops.connect_verts(bm, verts=new)
                added += len(new)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.to_mesh(me)
        bm.free()
        me.update()
        fs = me.attributes.get("fset")
        eye_attr = me.attributes.get("is_eye")
        print(f"[figure] cut {added} boundary vertices")

        # material per face from face set, facing and the fields above
        sh = (P["shoulderL"].z + P["shoulderR"].z) / 2
        for i, poly in enumerate(me.polygons):
            group = "skin"
            c = poly.center
            n = poly.normal
            front = n.y < -0.25
            back = n.y > 0.25
            region = inv.get(fs.data[i].value)
            if eye_attr is not None and eye_attr.data[i].value == 1:
                side = "L" if c.x > 0 else "R"
                group = "iris" if c.y - eye_front.get(side, c.y) < 0.0021 else "sclera"
            elif region == "head":
                group = "hair" if f_hair(c) > 0 else "skin"
            elif region == "torso":
                if f_collar(c) <= 0:
                    group = "skin"
                elif front and c.z > sh - 0.26 * scale and abs(c.x) < 0.19 * scale:
                    group = "shirt.chest"
                elif back:
                    group = "shirt.back"
                else:
                    group = "shirt"
            elif region in ("abdomen", "pelvis"):
                if f_hem(c) > 0:
                    group = "shirt.back" if back else ("shirt.core" if front or region == "abdomen" else "shirt")
                else:
                    group = "shorts.glutes" if back else "shorts"
            elif region and region.startswith("upperArm"):
                if f_sleeve(c, region[-1]) > 0:
                    group = "shirt.shoulders"
                else:
                    group = "triceps" if back else "biceps"
            elif region and region.startswith("thigh"):
                side = region[-1]
                if f_hem(c) > 0:
                    group = "shirt"
                elif f_shorts(c, side) > 0:
                    group = "shorts.hamstrings" if back else "shorts.quads"
                else:
                    group = "hamstrings" if back else "quads"
            elif region and region.startswith("shin"):
                knee_z = P["knee" + region[-1]].z
                group = "calves" if (back and c.z > knee_z - 0.28 * scale) else "skin"
            poly.material_index = mat_index[group]
        bpy.ops.object.select_all(action="DESELECT")
        body.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.shade_smooth()
        from collections import Counter
        usage = Counter(p.material_index for p in body.data.polygons)
        names = list(GROUP_COLORS)
        print("[figure] materials:", {names[k]: v for k, v in sorted(usage.items())})
        print(f"[figure] base body: {len(body.data.vertices)} verts, {len(body.data.polygons)} faces (from {tri_count} tris)")

    HOOKS["finish"] = finish_materials
    return body, joints


def bake_ao(body):
    """Bakes ambient occlusion into a vertex colour layer (COLOR_0)."""
    me = body.data
    col = me.color_attributes.new("AO", "FLOAT_COLOR", "POINT")
    me.color_attributes.active_color = col
    try:
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = 48
        if scene.world is None:
            scene.world = bpy.data.worlds.new("World")
        scene.world.light_settings.distance = 0.35
        bpy.ops.object.select_all(action="DESELECT")
        body.select_set(True)
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
        print("[figure] AO baked with Cycles")
        return
    except Exception as e:  # noqa: BLE001
        print(f"[figure] Cycles AO bake failed ({e}); ray-casting instead")
    from mathutils.bvhtree import BVHTree
    bvh = BVHTree.FromObject(body, bpy.context.evaluated_depsgraph_get())
    import random
    rnd = random.Random(7)
    dirs = []
    while len(dirs) < 24:
        d = Vector((rnd.uniform(-1, 1), rnd.uniform(-1, 1), rnd.uniform(-1, 1)))
        if 0.1 < d.length <= 1:
            dirs.append(d.normalized())
    for i, v in enumerate(me.vertices):
        n = v.normal
        hits = 0
        total = 0
        for d in dirs:
            if d.dot(n) <= 0.05:
                continue
            total += 1
            loc, _, _, dist = bvh.ray_cast(v.co + n * 0.004, d, 0.35)
            if loc is not None:
                hits += 1 - (dist / 0.35) * 0.5
        ao = 1.0 - (hits / total if total else 0)
        col.data[i].color = (ao, ao, ao, 1.0)
    print("[figure] AO ray-cast")


if args.base:
    body, R = build_from_base(args.base, args.base_object)
    REST = R
else:
    body, R = build_procedural()
if not args.no_ao:
    bake_ao(body)


def bake_warmth(body, joints):
    """Writes a skin-warmth weight into the green channel of the vertex
    colour: face, hands, knees and elbows run a little redder."""
    me = body.data
    col = me.color_attributes.get("AO")
    if col is None:
        return
    anchors = []
    for name, radius, strength in (
        ("head", 0.16, 0.9),
        ("handL", 0.11, 0.8),
        ("handR", 0.11, 0.8),
        ("kneeL", 0.09, 0.6),
        ("kneeR", 0.09, 0.6),
        ("elbowL", 0.07, 0.5),
        ("elbowR", 0.07, 0.5),
        ("toeL", 0.08, 0.5),
        ("toeR", 0.08, 0.5),
    ):
        if name in joints:
            anchors.append((B(joints[name]), radius, strength))
    for i, v in enumerate(me.vertices):
        w = 0.0
        for c, r, k in anchors:
            d = (v.co - c).length / r
            w = max(w, k * math.exp(-d * d))
        ao = col.data[i].color[0]
        col.data[i].color = (ao, w, 0.0, 1.0)
    print("[figure] warmth baked")


if not args.no_ao:
    bake_warmth(body, R)


def drop_enclosed(body):
    """Deletes faces no light reaches (the mouth bag, the eye sockets'
    insides, the backs of the eyeballs): never visible, but a painter's
    algorithm can still let them bleed through the face."""
    me = body.data
    col = me.color_attributes.get("AO")
    if col is None:
        return
    ao = [c.color[0] for c in col.data]
    doomed = [p.index for p in me.polygons if all(ao[v] < 0.03 for v in p.vertices)]
    if not doomed:
        return
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in doomed], context="FACES")
    bm.to_mesh(me)
    bm.free()
    me.update()
    print(f"[figure] dropped {len(doomed)} enclosed faces -> {len(me.polygons)} faces")


if not args.no_ao:
    drop_enclosed(body)

# ----------------------------------------------------------------------------
# Armature
# ----------------------------------------------------------------------------
BONES = [
    # name, head joint, tail joint (or offset), parent, side
    ("pelvis", "pelvis", None, None),
    ("spineLower", "pelvis", "spineMid", "pelvis"),
    ("spineUpper", "spineMid", "chest", "spineLower"),
    ("neck", "chest", "neck", "spineUpper"),
    ("head", "neck", "head", "neck"),
    ("shoulderL", "chest", "shoulderL", "spineUpper"),
    ("upperArmL", "shoulderL", "elbowL", "shoulderL"),
    ("forearmL", "elbowL", "wristL", "upperArmL"),
    ("handL", "wristL", "handL", "forearmL"),
    ("shoulderR", "chest", "shoulderR", "spineUpper"),
    ("upperArmR", "shoulderR", "elbowR", "shoulderR"),
    ("forearmR", "elbowR", "wristR", "upperArmR"),
    ("handR", "wristR", "handR", "forearmR"),
    ("hipL", "pelvis", "hipL", "pelvis"),
    ("thighL", "hipL", "kneeL", "hipL"),
    ("shinL", "kneeL", "ankleL", "thighL"),
    ("footL", "ankleL", "toeL", "shinL"),
    ("hipR", "pelvis", "hipR", "pelvis"),
    ("thighR", "hipR", "kneeR", "hipR"),
    ("shinR", "kneeR", "ankleR", "thighR"),
    ("footR", "ankleR", "toeR", "shinR"),
]


def frame_dirs(J):
    """Torso axes from a joint dict (rig coordinates)."""
    up = (J["chest"] - J["pelvis"]).normalized()
    right = (J["shoulderR"] - J["shoulderL"]).normalized()
    fwd = up.cross(right).normalized()
    return up, right, fwd


def bone_frame(name, J):
    """Desired world matrix (Blender space) of a bone for joints J.

    Y axis along the bone, Z axis towards the segment's "front" hint, X the
    flexion axis. The same function builds the rest pose, so skinning only
    sees the relative motion.
    """
    up, right, fwd = frame_dirs(J)
    p_right = (J["hipR"] - J["hipL"]).normalized()
    if "pelvisUp" in J:
        # The rig's own pelvis orientation: lets the spine curve between
        # the hips and the chest instead of hinging at one joint.
        p_up = Vector(J["pelvisUp"]).normalized()
        p_fwd = Vector(J["pelvisFwd"]).normalized()
    else:
        p_up = (J["chest"] - J["pelvis"]).normalized()
        p_fwd = p_up.cross(p_right).normalized()
    spec = {b[0]: b for b in BONES}[name]
    head_j, tail_j = spec[1], spec[2]
    a = J[head_j]
    if tail_j is None:
        b = a + p_up * 0.1
    else:
        b = J[tail_j]
    y = (b - a)
    if y.length < 1e-6:
        y = up.copy()
    y.normalize()

    def axis_from_hint(hint):
        x = y.cross(hint)
        if x.length < 1e-4:
            x = y.cross(p_right if abs(y.dot(p_right)) < 0.9 else p_fwd)
        x.normalize()
        z = x.cross(y).normalized()
        return x, z

    if name in ("pelvis", "hipL", "hipR"):
        x, z = axis_from_hint(p_fwd)
    elif name in ("spineLower", "spineUpper", "neck", "head", "shoulderL", "shoulderR"):
        x, z = axis_from_hint(fwd if name != "spineLower" else (fwd + p_fwd).normalized())
    elif name.startswith("upperArm") or name.startswith("thigh"):
        side = name[-1]
        child = {"upperArm": ("elbow", "wrist"), "thigh": ("knee", "ankle")}[name[:-1]]
        d2 = (J[child[1] + side] - J[child[0] + side]).normalized()
        flex = y.cross(d2)  # flexion axis when bent
        if name.startswith("upperArm"):
            ref = right if side == "R" else -right
        else:
            ref = p_right if side == "R" else -p_right
        if flex.length < 0.08:
            hint = fwd if name.startswith("upperArm") else p_fwd
            x, z = axis_from_hint(hint)
        else:
            x = flex.normalized()
        # The flexion axis always points to the same side of the body, so
        # straight and bent frames never flip the roll (no candy-wrapper
        # twist on the forearm and hand).
        if x.dot(ref) < 0:
            x = -x
        z = x.cross(y).normalized()
    elif name.startswith("forearm") or name.startswith("shin") or name.startswith("hand") or name.startswith("foot"):
        side = name[-1]
        parent = {"forearm": "upperArm", "shin": "thigh", "hand": "forearm", "foot": "shin"}[name[:-1]] + side
        px, _, _, _ = BONE_FRAMES_CACHE[parent]
        x = px.copy()
        z = x.cross(y)
        if z.length < 1e-4:
            x, z = axis_from_hint(fwd)
        else:
            z.normalize()
            x = y.cross(z).normalized()
    else:
        x, z = axis_from_hint(fwd)
    # rig -> blender vectors
    xb, yb, zb, ab = B(x), B(y), B(z), B(a)
    m = Matrix((
        (xb.x, yb.x, zb.x, ab.x),
        (xb.y, yb.y, zb.y, ab.y),
        (xb.z, yb.z, zb.z, ab.z),
        (0, 0, 0, 1),
    ))
    BONE_FRAMES_CACHE[name] = (x, y, z, m)
    return m, (b - a).length if tail_j else 0.1


BONE_FRAMES_CACHE = {}


def with_spine_mid(J):
    """Adds the synthetic mid-spine joint: the lower spine leaves the pelvis
    half way between the pelvis's own up axis and the chest direction, so a
    crunch or a cat-cow bends through the back rather than at the hips."""
    J = dict(J)
    pelvis, chest = J["pelvis"], J["chest"]
    spine = chest - pelvis
    length = spine.length
    spine_dir = spine.normalized()
    if "pelvisUp" in J:
        p_up = Vector(J["pelvisUp"]).normalized()
    else:
        p_up = spine_dir
    lower = (p_up + spine_dir)
    lower = lower.normalized() if lower.length > 1e-6 else spine_dir
    J["spineMid"] = pelvis + lower * (length * 0.5)
    return J


def all_bone_frames(J):
    J = with_spine_mid(J)
    BONE_FRAMES_CACHE.clear()
    out = {}
    for spec in BONES:
        out[spec[0]] = bone_frame(spec[0], J)
    return out


rest_frames = all_bone_frames(REST)

bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
arm = bpy.context.active_object
arm.name = "Skeleton"
arm.data.name = "Skeleton"
ebones = arm.data.edit_bones
for eb in list(ebones):
    ebones.remove(eb)
for spec in BONES:
    name, _, _, parent = spec
    m, length = rest_frames[name]
    eb = ebones.new(name)
    headp = m.to_translation()
    yaxis = Vector((m[0][1], m[1][1], m[2][1]))
    zaxis = Vector((m[0][2], m[1][2], m[2][2]))
    eb.head = headp
    eb.tail = headp + yaxis * max(length, 0.05)
    eb.align_roll(zaxis)
    if parent:
        eb.parent = ebones[parent]
        eb.use_connect = False
bpy.ops.object.mode_set(mode="OBJECT")

# Parent with automatic weights.
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
eye_attr = body.data.attributes.get("is_eye")
if eye_attr is not None:
    head_group = body.vertex_groups.get("head") or body.vertex_groups.new(name="head")
    eye_verts = set()
    for i, poly in enumerate(body.data.polygons):
        if eye_attr.data[i].value == 1:
            eye_verts.update(poly.vertices)
    for vg in body.vertex_groups:
        if vg.name != "head":
            vg.remove(list(eye_verts))
    head_group.add(list(eye_verts), 1.0, "REPLACE")
    print(f"[figure] {len(eye_verts)} eye vertices pinned to the head")
if "finish" in HOOKS:
    HOOKS["finish"]()

# ----------------------------------------------------------------------------
# Animations: one NLA track per clip, keyframes at whole seconds
# ----------------------------------------------------------------------------
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="POSE")
pbones = arm.pose.bones
rest_local = {spec[0]: arm.data.bones[spec[0]].matrix_local.copy() for spec in BONES}
parent_of = {spec[0]: spec[3] for spec in BONES}

if arm.animation_data is None:
    arm.animation_data_create()
# New keys interpolate linearly (the Dart player does the same).
bpy.context.preferences.edit.keyframe_new_interpolation_type = "LINEAR"


def apply_frame(J, frame):
    frames = all_bone_frames(J)
    world = {}
    for spec in BONES:
        name = spec[0]
        desired = frames[name][0]
        parent = parent_of[name]
        if parent is None:
            basis = rest_local[name].inverted() @ desired
        else:
            rel_rest = rest_local[parent].inverted() @ rest_local[name]
            basis = rel_rest.inverted() @ world[parent].inverted() @ desired
        world[name] = desired
        pb = pbones[name]
        pb.matrix_basis = basis
        if parent is not None:
            # Rotations only: the body's own segment lengths decide where
            # each joint sits, so proportions never have to match the rig.
            pb.location = (0.0, 0.0, 0.0)
        pb.keyframe_insert("rotation_quaternion", frame=frame)
        if parent is None:
            pb.keyframe_insert("location", frame=frame)


clip_count = 0
for clip_id, clip in POSES["clips"].items():
    action = bpy.data.actions.new(clip_id)
    arm.animation_data.action = action
    for i, frame_joints in enumerate(clip["frames"]):
        J = {k: Vector(v) for k, v in frame_joints.items()}
        apply_frame(J, i * args.fps)
    # linear interpolation between keys (layered actions in Blender 4.4+)
    def _fcurves(act):
        if hasattr(act, "fcurves"):
            return list(act.fcurves)
        out = []
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    out.extend(cb.fcurves)
        return out
    for fc in _fcurves(action):
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    track = arm.animation_data.nla_tracks.new()
    track.name = clip_id
    strip = track.strips.new(clip_id, int(action.frame_range[0]), action)
    strip.name = clip_id
    arm.animation_data.action = None
    clip_count += 1
bpy.ops.object.mode_set(mode="OBJECT")
print(f"[figure] {clip_count} clips keyed")

# ----------------------------------------------------------------------------
# Export
# ----------------------------------------------------------------------------
os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
arm.select_set(True)
def _export(mode):
    bpy.ops.export_scene.gltf(
        filepath=args.out,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=False,
        export_normals=True,
        export_tangents=False,
        export_materials="EXPORT",
        export_image_format="NONE",
        export_vertex_color="ACTIVE",
        export_all_vertex_colors=False,
        export_active_vertex_color_when_no_material=True,
        export_skins=True,
        export_all_influences=False,
        export_animations=True,
        export_animation_mode=mode,
        export_nla_strips=True,
        export_force_sampling=False,
        export_optimize_animation_size=False,
        export_morph=False,
        export_def_bones=False,
        export_rest_position_armature=True,
    )


try:
    _export("ACTIONS")
except Exception as e:  # noqa: BLE001
    print(f"[figure] ACTIONS export failed ({e}); using NLA_TRACKS")
    _export("NLA_TRACKS")
print(f"[figure] exported {args.out} ({os.path.getsize(args.out)} bytes)")

# ----------------------------------------------------------------------------
# Previews (Workbench renders of a few clips)
# ----------------------------------------------------------------------------
if args.previews:
    os.makedirs(args.previews, exist_ok=True)
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_object_outline = False
    scene.render.resolution_x = 420
    scene.render.resolution_y = 560
    scene.render.film_transparent = False
    cam_data = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cam_data)
    bpy.context.collection.objects.link(cam)
    scene.camera = cam
    # 3/4 view from the front-left, slightly above
    cam.location = (-2.4, -3.2, 1.6)
    cam.rotation_euler = (math.radians(75), 0, math.radians(-37))
    cam_data.lens = 45
    def render(name):
        scene.render.filepath = os.path.join(args.previews, name)
        bpy.ops.render.render(write_still=True)

    for track in arm.animation_data.nla_tracks:
        track.mute = True
    scene.frame_set(0)
    cam.location = (0, -4.2, 1.0)
    cam.rotation_euler = (math.radians(88), 0, 0)
    render("rest_front.png")
    for track in arm.animation_data.nla_tracks:
        track.mute = track.name != "stand"
    scene.frame_set(0)
    cam.location = (0, -4.2, 1.0)
    cam.rotation_euler = (math.radians(88), 0, 0)
    render("stand_front.png")
    cam.location = (0, 4.2, 1.0)
    cam.rotation_euler = (math.radians(88), 0, math.radians(180))
    render("stand_back.png")
    cam.location = (-2.4, -3.2, 1.6)
    cam.rotation_euler = (math.radians(75), 0, math.radians(-37))
    for clip_id in ("stand", "push_up", "squat", "lunge", "plank", "sit_up", "hinge", "jumping_jack", "pull_up", "shoulder_press", "curl", "bent_row"):
        if clip_id not in POSES["clips"]:
            continue
        for track in arm.animation_data.nla_tracks:
            track.mute = track.name != clip_id
        n = len(POSES["clips"][clip_id]["frames"])
        for i in range(min(n, 2)):
            scene.frame_set(i * args.fps)
            scene.render.filepath = os.path.join(args.previews, f"{clip_id}_{i}.png")
            bpy.ops.render.render(write_still=True)
    print("[figure] previews written")
