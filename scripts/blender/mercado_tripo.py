"""Teste A do Mercado das Raízes (Tripo + Blender): a Loja e a Forja que o designer gerou no Tripo, completadas no
Blender (MCP).

Os dois modelos do Tripo (lobby1-claude-code/Tripo/: "Loja lobby 1.glb" e "Ferreiro Lobby 1.glb"; prédios de pedra com
cristais roxos, ~8.800 triângulos e textura de cor 1024 cada) vêm com o FUNDO ABERTO. O designer pediu:

- atrás, um morro de terra e grama em rampa, no estilo das tocas do Hobbit, AFASTADO da fachada (na 1ª versão o morro
  cobria a porta, o balcão de fora e as lanternas): cúpula arredondada que nasce atrás do prédio, cobre o fundo e o
  telhado (a pedra grande, a chaminé e os cristais ficam para fora) e desce em rampa até o chão;
- os cristais brilhando: as faces dos cristais (roxo claro e saturado na textura) saem da malha do prédio e viram três
  malhas por tom de face, como o Coração do Abismo (claras e médias em Neon no Roblox, escuras sem brilho). O toldo, a
  placa e os estandartes têm o mesmo roxo: ficam de fora pela posição (faixa da fachada), e o piso da frente (faces
  deitadas no chão) também;
- a loja um pouco maior (escala 24 em vez de 20).

Escala: o Tripo entrega o modelo com 1 unidade de largura. Frente do prédio = -Y do Blender (= +z do Roblox depois do
GLB; o .luau gira cada peça para onde ela olha).

Uso no Blender (pelo MCP):
    import sys, importlib
    sys.path.insert(0, r"<projeto>\\scripts\\blender")
    import lobby1_blender as LB, mercado_tripo as M
    importlib.reload(LB); importlib.reload(M)
    objetos = M.build(M.LOJA)          # ou M.FORJA
    print(M.export(M.LOJA, objetos))
"""

from __future__ import annotations

import colorsys
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

import lobby1_blender as LB

TRIPO_DIR = os.path.join(LB.ROOT, "lobby1-claude-code", "Tripo")
OUT_DIR = os.path.join(LB.ROOT, "lobby1-claude-code", "modelos", "mercado")

# Cada peça: arquivo do Tripo, escala, morro (em unidades do Tripo: fundo do prédio, altura, raios, onde ele começa) e a
# faixa da fachada onde o roxo NÃO é cristal (y < facade_y e facade_z0 < z < facade_z1, em unidades do Tripo).
LOJA = {
    "name": "Loja",
    "glb": "Loja lobby 1.glb",
    "out": "LojaTripo.glb",
    "scale": 24.0,
    "hill_y": 0.6,  # centro da cúpula (fundo do prédio em y = 0,44)
    "hill_h": 0.6,  # telhado a ~0,45-0,5
    "hill_rx": 1.05,
    "hill_ry": (0.7, 1.25),  # frente, trás (mais comprido atrás: a rampa)
    "mask_x": 0.6,  # na largura do prédio (e um pouco além) o morro só começa atrás da fachada...
    "front_y": 0.12,  # ...a partir daqui
    "facade_y": 0.05,
    "facade_z": (0.225, 0.625),
}
FORJA = {
    "name": "Forja",
    "glb": "Ferreiro Lobby 1.glb",
    "out": "ForjaTripo.glb",
    "scale": 24.0,
    # fundo do prédio em y = 0,33; telhado a ~0,54-0,63. Mais baixo e mais para trás que o da loja: com 0,62 o morro
    # engolia a chaminé e os cristais do topo
    "hill_y": 0.56,
    "hill_h": 0.53,
    "hill_rx": 1.05,
    "hill_ry": (0.6, 1.25),
    "mask_x": 0.6,
    "front_y": 0.1,
    "facade_y": 0.0,
    "facade_z": (0.2, 0.56),
}

STEP = 0.05  # grade do morro, em unidades do Tripo


def smooth(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def morro_altura(cfg: dict, x: float, y: float) -> float:
    """Altura do morro (unidades do Tripo) em (x, y): cúpula de topo cheio (1 - d³)^1,6, que se funde no chão em todas
    as bordas, com contorno ondulado e montinhos; na largura do prédio ela só começa atrás da fachada."""
    hy, hh, rx = cfg["hill_y"], cfg["hill_h"], cfg["hill_rx"]
    ry = cfg["hill_ry"][0] if y < hy else cfg["hill_ry"][1]
    wobble = 1 + 0.07 * noise.noise(Vector((math.atan2(y - hy, x) * 2.0, 3.3, 0.0)))
    d = math.sqrt((x / rx) ** 2 + ((y - hy) / ry) ** 2) / wobble
    h = hh * max(0.0, 1 - d**3) ** 1.6
    center = 1 - smooth((abs(x) - cfg["mask_x"]) / 0.15)
    front = smooth((y - cfg["front_y"]) / 0.25)
    h *= 1 - center * (1 - front)
    lump = noise.fractal(Vector((x * 5.0, y * 5.0, 1.7)), 0.7, 2.0, 3)
    # borda afundada no chão: o recorte em degraus da grade fica escondido sob o Terrain
    return h + 0.02 * lump * min(1.0, h * 6) - 0.035


def build_morro(cfg: dict, col) -> list:
    """Lençol de altura do morro, dividido em grama (o que dá para pisar) e terra (o barranco atrás da fachada)."""
    scale = cfg["scale"]
    x0, y0 = -1.1, -0.45
    nx, ny = round(2.2 / STEP), round(2.4 / STEP)
    grid = {}
    for i in range(nx + 1):
        for j in range(ny + 1):
            x, y = x0 + i * STEP, y0 + j * STEP
            grid[(i, j)] = Vector((x, y, morro_altura(cfg, x, y))) * scale

    prefix = cfg["name"]
    parts = {f"{prefix}MorroGrama": ([], []), f"{prefix}MorroTerra": ([], [])}
    for i in range(nx):
        for j in range(ny):
            a, b, c, d = grid[(i, j)], grid[(i + 1, j)], grid[(i + 1, j + 1)], grid[(i, j + 1)]
            if max(a.z, b.z, c.z, d.z) < 0.05:  # chão: sem morro aqui
                continue
            for tri in ((a, b, c), (a, c, d)):
                n = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
                key = f"{prefix}MorroGrama" if n.z > 0.55 else f"{prefix}MorroTerra"
                verts, faces = parts[key]
                base = len(verts)
                verts.extend(tri)
                faces.append((base, base + 1, base + 2))

    objects = []
    for name, (verts, faces) in parts.items():
        color = (70, 120, 60) if name.endswith("Grama") else (110, 80, 55)
        ob = LB.mesh_object(name, verts, faces, col, LB.material(name, color))
        LB.weld(ob)
        LB.planar_uv(ob.data)
        objects.append(ob)
    return objects


def import_tripo(cfg: dict, col):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(TRIPO_DIR, cfg["glb"]))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    assert len(meshes) == 1, f"esperava 1 malha no GLB do Tripo, veio {len(meshes)}"
    ob = meshes[0]
    for o in new:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)
    # escala aplicada na própria malha (o GLB exportado não leva escala no nó)
    ob.data.transform(Matrix.Scale(cfg["scale"], 4))
    ob.name = f"{cfg['name']}Tripo"
    return ob


# ------------------------------------------------------------------ cristais

LIGHT = Vector((0.35, -0.6, 1.0)).normalized()  # de onde vem a "luz" dos tons (cima, frente)


def is_crystal(rgb: tuple[float, float, float]) -> bool:
    """Roxo claro e saturado da textura do Tripo (a pedra também é violeta, mas apagada e escura)."""
    h, s, v = colorsys.rgb_to_hsv(*rgb)
    return 0.70 < h < 0.86 and s > 0.42 and v > 0.62


def split_crystals(cfg: dict, ob, col) -> list:
    """Tira da malha do prédio as faces dos cristais (pela cor da textura) e devolve três malhas por tom de face."""
    me = ob.data
    mat = me.materials[0]
    img = next(n.image for n in mat.node_tree.nodes if n.type == "TEX_IMAGE")
    w, h = img.size
    px = img.pixels[:]
    scale = cfg["scale"]
    z0, z1 = cfg["facade_z"][0] * scale, cfg["facade_z"][1] * scale
    fy = cfg["facade_y"] * scale

    bm = bmesh.new()
    bm.from_mesh(me)
    uv_layer = bm.loops.layers.uv.active

    def sample(u: float, v: float) -> tuple[float, float, float]:
        x = min(w - 1, max(0, int((u % 1.0) * w)))
        y = min(h - 1, max(0, int((v % 1.0) * h)))
        i = (y * w + x) * 4
        return px[i], px[i + 1], px[i + 2]

    tones: dict[str, tuple[list, list]] = {f"{cfg['name']}CristalClaro": ([], []), f"{cfg['name']}CristalMedio": ([], []),
                                           f"{cfg['name']}CristalEscuro": ([], [])}
    keys = list(tones)
    remove = []
    for f in bm.faces:
        cs = [sample(*loop[uv_layer].uv) for loop in f.loops]
        rgb = (sum(c[0] for c in cs) / len(cs), sum(c[1] for c in cs) / len(cs), sum(c[2] for c in cs) / len(cs))
        if not is_crystal(rgb):
            continue
        c = f.calc_center_median()
        if c.y < fy and z0 < c.z < z1:
            continue  # toldo, placa, estandartes (mesmo roxo, na fachada)
        if c.z < 1.2 and f.normal.z > 0.9:
            continue  # piso da frente (as rachaduras roxas pegariam triângulos grandes do chão)
        lit = f.normal.dot(LIGHT)
        key = keys[0] if lit > 0.35 else keys[1] if lit > -0.2 else keys[2]
        verts, faces = tones[key]
        base = len(verts)
        verts.extend(v.co.copy() for v in f.verts)
        faces.append(tuple(range(base, base + len(f.verts))))
        remove.append(f)
    bmesh.ops.delete(bm, geom=remove, context="FACES_ONLY")
    bm.to_mesh(me)
    bm.free()

    objects = []
    colors = {keys[0]: (100, 78, 232), keys[1]: (78, 36, 200), keys[2]: (58, 26, 130)}
    for name, (verts, faces) in tones.items():
        if faces:
            o = LB.mesh_object(name, verts, faces, col, LB.material(name, colors[name], 2.0 if name != keys[2] else 0))
            objects.append(o)
    return objects


# ------------------------------------------------------------------ tudo


def build(cfg: dict) -> list:
    col = LB.collection(f"{cfg['name']} Tripo")
    building = import_tripo(cfg, col)
    crystals = split_crystals(cfg, building, col)
    return [building] + crystals + build_morro(cfg, col)


def export(cfg: dict, objects: list) -> dict:
    return LB.export_glb(objects, os.path.join(OUT_DIR, cfg["out"]))


def triangulos(objects: list) -> dict:
    return {o.name: LB.triangles(o) for o in objects}
