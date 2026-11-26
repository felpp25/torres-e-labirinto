"""Ferramentas para montar as peças do Lobby 1 no Blender (MCP for Blender) e exportar para o Roblox.

Roda DENTRO do Blender (bpy). As formas vêm dos mesmos geradores em Python puro do projeto (lobby1-pedras.py,
lobby1-cristais.py: bloco lascado, cristal, tons de face) ou de funções daqui; o Blender entra para montar, ver
(look), projetar detalhes na superfície (BVH) e exportar o GLB.

Coordenadas: tudo é pensado no espaço do Roblox (x, y, z; Y para cima; 1 stud = 1 m). No Blender (Z para cima):
    Blender (X, Y, Z) = Roblox (x, -z, y)          -> rb(x, y, z)
O exportador glTF do Blender (+Y up) devolve exatamente as coordenadas do Roblox: o GLB sai igual ao dos geradores
em Python, e o .luau monta do mesmo jeito (centro da caixa + CFrame.Angles(0, π, 0), porque o importador do Roblox
gira a malha 180° em Y).

Uso no Blender (pelo MCP):
    import sys, importlib
    sys.path.insert(0, r"<projeto>\\scripts\\blender")
    import lobby1_blender as LB; importlib.reload(LB)
"""

from __future__ import annotations

import importlib.util
import json
import math
import os
import struct

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.dirname(HERE)
ROOT = os.path.dirname(SCRIPTS)
TILE = 8.0  # studs por repetição da textura (o mesmo dos geradores)


def load_generator(filename: str, name: str):
    """Carrega um gerador do projeto (ex.: lobby1-cristais.py) como módulo, sem rodar o __main__ dele."""
    spec = importlib.util.spec_from_file_location(name, os.path.join(SCRIPTS, filename))
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def rb(x: float, y: float, z: float) -> Vector:
    """Ponto do Roblox -> Blender."""
    return Vector((x, -z, y))


def to_roblox(v) -> tuple[float, float, float]:
    """Ponto do Blender -> Roblox."""
    return (v[0], v[2], -v[1])


# ---------------------------------------------------------------- coleção e objetos


def collection(name: str, clear: bool = True):
    col = bpy.data.collections.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(col)
    if clear:
        for ob in list(col.objects):
            data = ob.data if ob.type == "MESH" else None
            bpy.data.objects.remove(ob, do_unlink=True)
            if data is not None and data.users == 0:
                bpy.data.meshes.remove(data)
    return col


def material(name: str, rgb: tuple[int, int, int], emission: float = 0.0):
    """Material só para ver no Blender (no Roblox o material e a cor são postos pelo .luau)."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    color = (rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1.0)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs[0].default_value = color  # Base Color
    for sock in bsdf.inputs:
        if sock.identifier == "Emission Color":
            sock.default_value = color
        elif sock.identifier == "Emission Strength":
            sock.default_value = emission
    return mat


def planar_uv(me, tile: float = TILE) -> None:
    """UV por projeção plana pela direção da normal (1 repetição a cada `tile` studs), igual aos geradores."""
    uv = me.uv_layers[0] if me.uv_layers else me.uv_layers.new(name="UVMap")
    for poly in me.polygons:
        n = poly.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        a, b = {0: (1, 2), 1: (0, 2), 2: (0, 1)}[ax]
        for li in poly.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = (co[a] / tile, co[b] / tile)


def mesh_object(name: str, verts: list, faces: list, col, mat=None, flat: bool = True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    me.validate()
    me.update()
    for poly in me.polygons:
        poly.use_smooth = not flat
    if mat is not None:
        me.materials.append(mat)
    planar_uv(me)
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    return ob


def tris_object(name: str, tris: list, col, mat=None):
    """Objeto a partir de triângulos no espaço do Roblox (o formato dos geradores em Python)."""
    verts, faces = [], []
    for t in tris:
        base = len(verts)
        for p in t:
            verts.append(rb(*p))
        faces.append((base, base + 1, base + 2))
    ob = mesh_object(name, verts, faces, col, mat)
    weld(ob)
    return ob


def weld(ob, dist: float = 1e-4) -> None:
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
    bm.to_mesh(ob.data)
    bm.free()
    for poly in ob.data.polygons:
        poly.use_smooth = False
    planar_uv(ob.data)


def roughen(ob, cuts: int, amp: float, scale: float, seed: float, edge_amp: float = 0.3) -> None:
    """Rocha orgânica: subdivide e empurra cada vértice pela normal com ruído fractal (duas escalas), depois triangula
    com diagonais "bonitas" e deixa as faces chapadas (low-poly estilizado).

    Sem isso, uma malha feita de anéis paralelos parece um bolo em camadas (medido na primeira Fenda). Os vértices da
    borda aberta (contorno da malha) mexem só `edge_amp` do total, para a costura com outras peças não abrir."""
    from mathutils import noise

    bm = bmesh.new()
    bm.from_mesh(ob.data)
    if cuts > 0:
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    bm.normal_update()
    moves = []
    for v in bm.verts:
        p = v.co
        n1 = noise.fractal(Vector((p.x * scale + seed, p.y * scale, p.z * scale - seed)), 0.7, 2.1, 3)
        n2 = noise.fractal(Vector((p.x * scale * 3 - seed, p.y * scale * 3 + seed, p.z * scale * 3)), 0.6, 2.0, 2)
        k = amp * (n1 + 0.35 * n2)
        if v.is_boundary:
            k *= edge_amp
        moves.append((v, v.normal * k))
    for v, d in moves:
        v.co += d
    bmesh.ops.triangulate(bm, faces=bm.faces[:], quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(ob.data)
    bm.free()
    for poly in ob.data.polygons:
        poly.use_smooth = False
    ob.data.update()
    planar_uv(ob.data)


def recalc_normals(ob) -> None:
    """Normais para fora em malhas fechadas (cada ilha)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def boolean(target, cutter, operation: str = "DIFFERENCE") -> None:
    """Aplica um booleano (sem bpy.ops): o resultado vira a malha do `target`; o `cutter` é apagado."""
    mod = target.modifiers.new("corte", "BOOLEAN")
    mod.operation = operation
    mod.object = cutter
    solvers = [i.identifier for i in mod.bl_rna.properties["solver"].enum_items]
    mod.solver = "EXACT" if "EXACT" in solvers else solvers[-1]
    # cortador feito de várias caixas que se cruzam (ex.: rachadura em zigue-zague): sem "self", o EXACT devolvia
    # lixo (o crânio da caveira sobrava com 2 triângulos)
    if hasattr(mod, "use_self"):
        mod.use_self = True
    if hasattr(mod, "use_hole_tolerant"):
        mod.use_hole_tolerant = True
    cutter.hide_set(True)
    dg = bpy.context.evaluated_depsgraph_get()
    new_mesh = bpy.data.meshes.new_from_object(target.evaluated_get(dg))
    target.modifiers.remove(mod)
    old = target.data
    target.data = new_mesh
    bpy.data.meshes.remove(old)
    cutter_mesh = cutter.data
    bpy.data.objects.remove(cutter, do_unlink=True)
    if cutter_mesh.users == 0:
        bpy.data.meshes.remove(cutter_mesh)
    for poly in target.data.polygons:
        poly.use_smooth = False
    planar_uv(target.data)


def join(objects: list, name: str, col, mat=None):
    """Junta várias malhas num objeto só (bmesh), apagando as originais."""
    bm = bmesh.new()
    for ob in objects:
        bm.from_mesh(ob.data)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for ob in objects:
        data = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if data.users == 0:
            bpy.data.meshes.remove(data)
    me.materials.clear()
    if mat is not None:
        me.materials.append(mat)
    for poly in me.polygons:
        poly.use_smooth = False
    planar_uv(me)
    ob = bpy.data.objects.new(name, me)
    col.objects.link(ob)
    return ob


def decimate(ob, ratio: float) -> None:
    """Reduz os triângulos (modificador Decimate, colapso) mantendo o sombreamento suave/chapado de antes."""
    smooth = any(p.use_smooth for p in ob.data.polygons)
    mod = ob.modifiers.new("reduzir", "DECIMATE")
    mod.ratio = ratio
    dg = bpy.context.evaluated_depsgraph_get()
    new_mesh = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    ob.modifiers.remove(mod)
    old = ob.data
    ob.data = new_mesh
    bpy.data.meshes.remove(old)
    ob.data.name = ob.name
    for poly in ob.data.polygons:
        poly.use_smooth = smooth
    planar_uv(ob.data)


def triangles(ob) -> int:
    return sum(len(p.vertices) - 2 for p in ob.data.polygons)


def outward_ok(ob, probe_world: Vector, expect: Vector) -> bool:
    """A face mais perto de `probe_world` tem a normal para o lado de `expect`?"""
    best, best_d = None, math.inf
    for p in ob.data.polygons:
        d = (ob.matrix_world @ p.center - probe_world).length
        if d < best_d:
            best, best_d = p, d
    return best is not None and best.normal.dot(expect) > 0


def flip(ob) -> None:
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()


# ---------------------------------------------------------------- exportação


def export_glb(objects: list, path: str) -> dict:
    """Exporta só `objects` num GLB (modificadores aplicados, +Y para cima) e devolve, por malha, o centro e o tamanho
    da caixa em coordenadas do glTF (= Roblox antes do giro do importador), lidos do próprio arquivo."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objects:
        ob.hide_set(False)
        ob.data.name = ob.name  # o nó e a malha com o mesmo nome (o .luau procura a peça por ele)
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    props = bpy.ops.export_scene.gltf.get_rna_type().properties.keys()
    kwargs = {"filepath": path, "export_format": "GLB", "use_selection": True}
    for key, value in (("export_apply", True), ("export_yup", True), ("export_extras", False),
                       ("export_animations", False), ("export_cameras", False), ("export_lights", False)):
        if key in props:
            kwargs[key] = value
    bpy.ops.export_scene.gltf(**kwargs)
    return glb_boxes(path)


def glb_boxes(path: str) -> dict:
    with open(path, "rb") as f:
        data = f.read()
    length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20 : 20 + length])
    out = {}
    for mesh in gltf["meshes"]:
        lo = [math.inf] * 3
        hi = [-math.inf] * 3
        for prim in mesh["primitives"]:
            acc = gltf["accessors"][prim["attributes"]["POSITION"]]
            for i in range(3):
                lo[i] = min(lo[i], acc["min"][i])
                hi[i] = max(hi[i], acc["max"][i])
        out[mesh["name"]] = {
            "center": [round((lo[i] + hi[i]) / 2, 3) for i in range(3)],
            "size": [round(hi[i] - lo[i], 3) for i in range(3)],
        }
    return out
