"""Torre 2, Ruínas Subterrâneas: o Portal do Vigia do Sol e as Estelas Solares (Blender, MCP -> GLB -> Roblox).

Fachada de pedra lavrada na face do rochedo leste (x = +62): dois pilares com painéis de runas solares, lintel com
faixa de runas e um canto quebrado, um nicho oval VAZIO no meio e, embaixo, a porta em arco com a grade de ferro meio
erguida e um corredor escuro (o Terrain é escavado pelo .luau). Na frente, as Estelas Solares (duas variações, na
origem: o .luau põe as quatro).

O nicho já teve um rosto sereno (relevo por função de altura) e depois uma caveira (metaballs): o designer descartou
os dois (26/11/2026) e pediu o nicho sem nada.

Referências: 03 (monólito com estelas) e o lado direito da 06.

Coordenadas do Roblox (ver lobby1_blender.py). Semente fixa.

Uso no Blender (pelo MCP):
    import sys, importlib
    sys.path.insert(0, r"<projeto>\\scripts\\blender")
    import lobby1_blender as LB, vigia as V
    importlib.reload(LB); importlib.reload(V)
    objetos, relatorio = V.build_vigia()
    estelas, relatorio_estelas = V.build_estelas()
"""

from __future__ import annotations

import math
import random

import bmesh
from mathutils import Vector

import lobby1_blender as LB

PB = LB.load_generator("lobby1-pedras.py", "pedras")

VX = 59.0  # frente dos pilares (o portal no chão vai até x = 60)
NICHE_CENTER = (61.7, 30.0, 0.0)  # fundo do nicho oval (vazio)
NICHE_A, NICHE_B = 6.0, 8.2  # meia-largura (z) e meia-altura (y) do nicho
DOOR_HALF, DOOR_SPRING, DOOR_FLOOR = 5.5, 15.0, 2.2  # porta: meia-largura, começo do arco, soleira
PILLAR_Z = 13.6
PILLAR_DRUMS = ((-0.4, 14.6), (14.6, 27.4), (27.4, 40.0))
PANELS = ((5.0, 13.0), (16.5, 25.5), (29.0, 38.0))  # um painel rebaixado por tambor
BUDGET = 10000


# ---------------------------------------------------------------- formas básicas


def door_profile(half: float, spring: float, floor: float, segs: int = 10) -> list[tuple[float, float]]:
    """Contorno da porta em arco no plano (z, y), anti-horário."""
    pts = [(-half, floor), (half, floor)]
    for i in range(segs + 1):
        a = math.pi * i / segs
        pts.append((half * math.cos(a), spring + half * math.sin(a)))
    return pts


def ellipse(cz: float, cy: float, a: float, b: float, segs: int = 40) -> list[tuple[float, float]]:
    return [(cz + a * math.cos(math.tau * i / segs), cy + b * math.sin(math.tau * i / segs)) for i in range(segs)]


def prism(profile: list[tuple[float, float]], x0: float, x1: float, dz: float = 0.0) -> tuple[list, list]:
    """Prisma fechado do contorno (z, y) entre x0 e x1 (Roblox) -> vértices (Blender) e faces."""
    n = len(profile)
    verts = [LB.rb(x0, y, z + dz) for z, y in profile] + [LB.rb(x1, y, z + dz) for z, y in profile]
    faces = [tuple(range(n)), tuple(range(2 * n - 1, n - 1, -1))]
    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))
    return verts, faces


def rot_x(p, pivot, angle: float):
    """Gira um ponto (Roblox) em volta do eixo x que passa por `pivot`."""
    y, z = p[1] - pivot[1], p[2] - pivot[2]
    c, s = math.cos(angle), math.sin(angle)
    return (p[0], pivot[1] + y * c - z * s, pivot[2] + y * s + z * c)


def closed(name: str, tris: list, col, mat=None):
    ob = LB.tris_object(name, tris, col, mat)
    LB.recalc_normals(ob)
    return ob


# ---------------------------------------------------------------- glifos (placas finas de ouro)


def plate(poly: list[tuple[float, float]], origin, depth: float, facing: float = -1.0) -> list:
    """Placa fechada: contorno (u, v) no plano x = origin.x (u ao longo de z, v ao longo de y), espessura `depth`
    saindo para o lado `facing` (-1 = para a avenida, no leste)."""
    x0, y0, z0 = origin
    front = [(x0 + facing * depth, y0 + v, z0 + u) for u, v in poly]
    back = [(x0, y0 + v, z0 + u) for u, v in poly]
    tris = []
    n = len(poly)
    for i in range(1, n - 1):
        tris.append((front[0], front[i], front[i + 1]))
        tris.append((back[0], back[i + 1], back[i]))
    for i in range(n):
        j = (i + 1) % n
        tris.append((front[i], back[i], back[j]))
        tris.append((front[i], back[j], front[j]))
    return tris


def sun_glyph(center, radius: float, depth: float = 0.25, rays: int = 8) -> list:
    """Runa solar: anel, raios em triângulo (alternando curto e longo) e um ponto no meio."""
    tris = []
    segs = 16
    r_in, r_out = radius * 0.62, radius * 0.86
    for i in range(segs):
        a0, a1 = math.tau * i / segs, math.tau * (i + 1) / segs
        quad = [(r_in * math.cos(a0), r_in * math.sin(a0)), (r_out * math.cos(a0), r_out * math.sin(a0)),
                (r_out * math.cos(a1), r_out * math.sin(a1)), (r_in * math.cos(a1), r_in * math.sin(a1))]
        tris += plate(quad, center, depth)
    for i in range(rays):
        a = math.tau * i / rays + math.pi / rays
        w = 0.2 * radius
        base_r, tip_r = radius * 1.0, radius * (1.55 if i % 2 == 0 else 1.32)
        perp = (-math.sin(a), math.cos(a))
        b = (math.cos(a) * base_r, math.sin(a) * base_r)
        tri = [(b[0] - perp[0] * w, b[1] - perp[1] * w), (math.cos(a) * tip_r, math.sin(a) * tip_r),
               (b[0] + perp[0] * w, b[1] + perp[1] * w)]
        tris += plate(tri, center, depth)
    dot = [(radius * 0.28 * math.cos(math.tau * i / 10), radius * 0.28 * math.sin(math.tau * i / 10)) for i in range(10)]
    tris += plate(dot, center, depth)
    return tris


def stroke_glyph(rng: random.Random, center, cell_w: float, cell_h: float, width: float = 0.22) -> list:
    """Runa de Áuren de traços (haste + 2 ou 3 traços numa grade 3 × 4), como as dos Anéis Rúnicos."""

    def pt(c: int, r: int) -> tuple[float, float]:
        return ((c / 2 - 0.5) * cell_w, (r / 3 - 0.5) * cell_h)

    stem = rng.randint(0, 2)
    segs = [((stem, 0), (stem, 3))]
    for _ in range(rng.randint(2, 3)):
        a, b = (rng.randint(0, 2), rng.randint(0, 3)), (rng.randint(0, 2), rng.randint(0, 3))
        if a != b:
            segs.append((a, b))
    tris = []
    for a, b in segs:
        (u0, v0), (u1, v1) = pt(*a), pt(*b)
        du, dv = u1 - u0, v1 - v0
        length = math.hypot(du, dv) or 1.0
        nu, nv = -dv / length * width / 2, du / length * width / 2
        quad = [(u0 + nu, v0 + nv), (u1 + nu, v1 + nv), (u1 - nu, v1 - nv), (u0 - nu, v0 - nv)]
        tris += plate(quad, center, 0.2)
    return tris


# ---------------------------------------------------------------- montagem do portal


def build_vigia():
    rng = random.Random(4201)
    col = LB.collection("Entrada Torre 2 - Vigia do Sol")
    stone = LB.material("Pedra", (175, 168, 195))
    gold = LB.material("Ouro", (235, 150, 60), emission=3.0)
    iron = LB.material("Ferro", (60, 55, 66))
    dark = LB.material("Tunel", (90, 80, 115))
    black = LB.material("Fundo", (8, 6, 14))

    parts = []
    # degraus da base (a frente fica atrás do portal no chão, que vai até x = 60)
    parts.append(closed("p_degrau1", PB.block(rng, (61.9, 0.3, 0.0), (3.8, 1.6, 34.0), noise=0.1, chamfer=0.25,
                                               chips=4, chip_depth=0.5, top_noise=0.05), col))
    parts.append(closed("p_degrau2", PB.block(rng, (62.3, 1.65, 0.0), (3.0, 1.1, 32.0), noise=0.1, chamfer=0.22,
                                               chips=3, chip_depth=0.4, top_noise=0.05), col))
    # pilares, cada um em 3 tambores lascados, com um painel rebaixado em cada (onde vão as runas)
    for side in (-1.0, 1.0):
        z = side * PILLAR_Z
        for (y0, y1), (p0, p1) in zip(PILLAR_DRUMS, PANELS):
            drum = closed("p_pilar", PB.block(
                rng, (VX + 2.1 + rng.uniform(-0.08, 0.08), (y0 + y1) / 2, z + rng.uniform(-0.08, 0.08)),
                (4.2, y1 - y0 - 0.08, 5.0), noise=0.12, chamfer=0.35, chips=3, chip_depth=0.6,
                flat_bottom=False), col)
            v, f = prism([(-1.6, p0), (1.6, p0), (1.6, p1), (-1.6, p1)], 58.0, VX + 0.45, dz=z)
            LB.boolean(drum, LB.mesh_object("corte_painel", v, f, col))
            parts.append(drum)
    # lintel (com a faixa de runas rebaixada) e cornija, os dois com o canto quebrado
    lintel = closed("p_lintel", PB.block(rng, (VX + 2.2, 42.8, 0.0), (5.0, 5.6, 35.0), noise=0.14, chamfer=0.4,
                                          chips=5, chip_depth=0.8, flat_bottom=False), col)
    v, f = prism([(-14.5, 41.4), (14.5, 41.4), (14.5, 44.2), (-14.5, 44.2)], 58.0, VX + 0.05)
    LB.boolean(lintel, LB.mesh_object("corte_faixa", v, f, col))
    cornice = closed("p_cornija", PB.block(rng, (VX + 2.0, 46.3, 0.0), (6.0, 1.6, 37.5), noise=0.14,
                                            chamfer=0.35, chips=6, chip_depth=0.7, flat_bottom=False), col)
    for target in (lintel, cornice):
        pivot = (VX + 2.0, 47.0, 16.5)
        chunk = PB.block(rng, pivot, (8.0, 6.0, 6.5), noise=0.6, chamfer=0.8, chips=4, chip_depth=1.0,
                         flat_bottom=False)
        chunk = [tuple(rot_x(p, pivot, 0.5) for p in t) for t in chunk]
        LB.boolean(target, closed("corte_canto", chunk, col))
    parts += [lintel, cornice]
    # laje do meio, atrás dos pilares, com a porta em arco e o nicho oval (vazio) escavados
    slab = closed("p_laje", PB.block(rng, (62.0, 21.1, 0.0), (3.0, 37.8, 22.6), seg=(1, 8, 6), noise=0.08,
                                     chamfer=0.2, chips=2, chip_depth=0.4, flat_bottom=False), col)
    v, f = prism(door_profile(DOOR_HALF, DOOR_SPRING, DOOR_FLOOR - 0.6), 58.0, 66.0)
    LB.boolean(slab, LB.mesh_object("corte_porta", v, f, col))
    v, f = prism(ellipse(0.0, NICHE_CENTER[1], NICHE_A, NICHE_B), 59.0, NICHE_CENTER[0])
    LB.boolean(slab, LB.mesh_object("corte_nicho", v, f, col))
    parts.append(slab)
    # pedras da moldura da porta (jambas e aduelas), um pouco salientes
    jamb = []
    for side in (-1.0, 1.0):
        for y0, y1 in ((2.2, 6.0), (6.0, 10.4), (10.4, 15.0)):
            jamb += PB.block(rng, (60.6, (y0 + y1) / 2, side * (DOOR_HALF + 0.75)), (1.6, y1 - y0 - 0.1, 1.6),
                             noise=0.08, chamfer=0.22, chips=1, chip_depth=0.3, flat_bottom=False)
    stones = 7
    for k in range(stones):
        am = math.pi * (k + 0.5) / stones
        r = DOOR_HALF + 0.75
        center = (60.6, DOOR_SPRING + math.sin(am) * r, math.cos(am) * r)
        block = PB.block(rng, center, (1.6, 1.6, 2.4), noise=0.07, chamfer=0.2, chips=1, chip_depth=0.25,
                         flat_bottom=False)
        jamb += [tuple(rot_x(p, center, am - math.pi / 2) for p in t) for t in block]
    parts.append(closed("p_aduelas", jamb, col))
    frame = LB.join(parts, "VigiaMoldura_1", col, stone)


    # runas de ouro: sol nos painéis de cima e de baixo, runa de traços no do meio; runas na faixa do lintel
    glyphs = []
    for side in (-1.0, 1.0):
        z = side * PILLAR_Z
        glyphs += sun_glyph((VX + 0.45, 9.0, z), 1.25)
        glyphs += stroke_glyph(rng, (VX + 0.45, 21.0, z), 1.6, 3.6, 0.32)
        glyphs += sun_glyph((VX + 0.45, 33.5, z), 1.25)
    n = 11
    for i in range(n):
        glyphs += stroke_glyph(rng, (VX + 0.05, 42.8, -13.0 + 26.0 * i / (n - 1)), 1.0, 2.0, 0.2)
    runes = closed("VigiaRunas_1", glyphs, col, gold)

    # grade de ferro meio erguida (a parte de baixo da porta fica livre), pontas para baixo
    bars = []
    for i in range(9):
        z = -DOOR_HALF + 0.65 + i * (2 * DOOR_HALF - 1.3) / 8
        top = DOOR_SPRING + math.sqrt(max(0.0, DOOR_HALF**2 - z * z)) - 0.3
        bars += PB.block(rng, (61.1, (9.5 + top) / 2, z), (0.36, top - 9.5, 0.36), seg=(1, 3, 1), noise=0.0,
                         chamfer=0.05, chips=0, flat_bottom=False)
        bars += PB.block(rng, (61.1, 9.0, z), (0.15, 1.0, 0.15), seg=(1, 1, 1), noise=0.0, chamfer=0.0, chips=0,
                         flat_bottom=False, taper=1.4)
    for y in (11.5, 15.5):
        bars += PB.block(rng, (61.1, y, 0.0), (0.4, 0.45, 2 * DOOR_HALF - 0.4), seg=(1, 1, 4), noise=0.0,
                         chamfer=0.06, chips=0, flat_bottom=False)
    gate = closed("VigiaPortao_1", bars, col, iron)

    # corredor escuro atrás da porta (sem as tampas: aberto na porta) e o fundo preto
    profile = door_profile(DOOR_HALF - 0.1, DOOR_SPRING, DOOR_FLOOR)
    v, f = prism(profile, 60.6, 72.0)
    corridor = LB.mesh_object("VigiaCorredor_1", v, f, col, dark)
    LB.recalc_normals(corridor)
    LB.flip(corridor)  # normais para dentro
    bm = bmesh.new()
    bm.from_mesh(corridor.data)
    bmesh.ops.delete(bm, geom=[fc for fc in bm.faces if len(fc.verts) > 4], context="FACES")
    bm.to_mesh(corridor.data)
    bm.free()
    corridor.data.update()
    LB.planar_uv(corridor.data)
    v, f = prism(profile, 71.8, 72.2)
    end = LB.mesh_object("VigiaFundo_1", v, f, col, black)
    LB.recalc_normals(end)

    objects = [frame, runes, gate, corridor, end]
    report = {ob.name: LB.triangles(ob) for ob in objects}
    total = sum(report.values())
    assert total <= BUDGET * 2, f"Vigia: {total} triângulos"
    return objects, report


def build_estelas():
    """Duas variações de Estela Solar (pedra lascada de topo arredondado com a runa solar de ouro), na origem: o
    .luau põe as quatro na frente do portal. A frente (com a runa) fica virada para -x (a avenida)."""
    objects = []
    stone = LB.material("Pedra", (175, 168, 195))
    gold = LB.material("Ouro", (235, 150, 60), emission=3.0)
    col = LB.collection("Estelas Solares")
    for n, seed in ((1, 4301), (2, 4302)):
        rng = random.Random(seed)
        half = rng.uniform(2.4, 2.9)
        height = rng.uniform(8.6, 10.0)
        top = rng.uniform(1.8, 2.6)
        prof = [(-half, -0.6), (half, -0.6)]
        for i in range(13):
            a = math.pi * i / 12
            prof.append((half * math.cos(a), height + top * math.sin(a)))
        v, f = prism(prof, -0.8, 0.8)
        slab = LB.mesh_object(f"EstelaSolar_{n}", v, f, col, stone)
        LB.recalc_normals(slab)
        LB.roughen(slab, cuts=2, amp=0.22, scale=0.45, seed=float(seed))
        LB.recalc_normals(slab)
        v, f = prism(ellipse(0.0, height - 1.6, 1.95, 1.95, 24), -1.4, -0.55)
        LB.boolean(slab, LB.mesh_object("corte_runa", v, f, col))
        slab.data.materials.clear()
        slab.data.materials.append(stone)
        rune = closed(f"EstelaRuna_{n}", sun_glyph((-0.55, height - 1.6, 0.0), 1.15, depth=0.35), col, gold)
        objects += [slab, rune]
    report = {ob.name: LB.triangles(ob) for ob in objects}
    return objects, report
