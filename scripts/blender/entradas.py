"""Entradas das torres do Lobby 1, montadas no Blender (MCP) e exportadas em GLB para o Roblox.

- Caverna das Profundezas (Torre 1, oeste, parede do rochedo em x = -62): a FENDA. Boca de rocha natural que sobe em
  zigue-zague até virar rachadura, com lábios de pedra salientes, túnel que entra na rocha e faz curva (o fundo não
  aparece), Veios da Fenda (rachaduras roxas que brilham, em raio, projetadas na superfície da rocha) e cristais no
  pé da boca e lá dentro. Referências: 02 (túnel de cristais roxos) e o lado esquerdo da 06 (parede rachada em roxo).

Tudo em coordenadas do Roblox (ver lobby1_blender.py). Semente fixa: sai igual toda vez.

Uso no Blender (pelo MCP):
    import sys, importlib
    sys.path.insert(0, r"<projeto>\\scripts\\blender")
    import lobby1_blender as LB, entradas as E
    importlib.reload(LB); importlib.reload(E)
    objetos = E.build_fenda()
"""

from __future__ import annotations

import math
import random

import bpy
from mathutils import Vector, noise
from mathutils.bvhtree import BVHTree

import lobby1_blender as LB

FACE_X = -62.0  # face do rochedo da Torre 1 (portão plano do Terrain em |x| = 62)
MOUTH_TOP = 27.0  # altura da boca no meio (a rachadura continua acima)

CR = LB.load_generator("lobby1-cristais.py", "cristais")
FO = LB.load_generator("lobby1-formacoes.py", "formacoes")

BUDGET = 10000  # peça principal (CLAUDE.md do lobby1)


def n3(p: tuple[float, float, float], scale: float, seed: float = 0.0) -> float:
    """Ruído fractal suave (-1..1) num ponto do Roblox."""
    return noise.fractal(Vector((p[0] * scale + seed, p[1] * scale, p[2] * scale - seed)), 0.8, 2.0, 3)


# ---------------------------------------------------------------- forma da boca


def fissure_outline(rng: random.Random) -> list[tuple[float, float]]:
    """Contorno da boca no plano (z, y): do pé esquerdo, sobe em zigue-zague até a ponta e desce pelo lado direito.

    Larga embaixo (~15 studs: o portal de 10 cabe na frente) e fina em cima, como uma rachadura que se abriu."""
    n = 15
    left, right = [], []
    for i in range(n + 1):
        t = i / n
        y = -1.0 + t * (MOUTH_TOP + 1.0)
        half = 7.4 * (1 - t**1.7) + 0.5
        zig = (0.6 if i % 2 else -0.4) * (0.3 + t)
        left.append((-half + zig + rng.uniform(-0.3, 0.3), y))
        right.append((half + zig * 0.8 + rng.uniform(-0.3, 0.3), y))
    top = (0.8 + rng.uniform(-0.3, 0.3), MOUTH_TOP + 1.6)
    return left + [top] + list(reversed(right))


def outward(p: tuple[float, float]) -> tuple[float, float]:
    """Direção "para fora da boca" (no plano z, y): embaixo é para o lado; no alto, para cima."""
    cz, cy = 0.4, min(p[1], MOUTH_TOP - 6.0)
    dz, dy = p[0] - cz, p[1] - cy
    length = math.hypot(dz, dy) or 1.0
    return dz / length, dy / length


# ---------------------------------------------------------------- rocha da boca e túnel


def fenda_rings(rng: random.Random):
    """Anéis (abertos embaixo) do fundo do túnel até a borda de fora da moldura. Cada anel: lista de pontos Roblox."""
    outline = fissure_outline(rng)
    rings: list[list[tuple[float, float, float]]] = []
    # túnel: do mais fundo (j = 6) até a borda da boca; encolhe para o pé do meio e faz curva para a esquerda (-z)
    scales = [0.97, 0.93, 0.88, 0.82, 0.76, 0.7]
    bends = [0.2, 0.6, 1.2, 2.0, 3.0, 4.2]
    for j in range(6, 0, -1):
        s, b = scales[j - 1], bends[j - 1]
        x = FACE_X + 0.6 - 2.7 * j
        ring = []
        for z, y in outline:
            pz = 0.4 + (z - 0.4) * s - b
            py = -1.0 + (y + 1.0) * (0.92 + 0.08 * s)
            q = (x, py, pz)
            k = 0.55 * n3(q, 0.3, 11.0)
            dz, dy = outward((z, y))
            ring.append((x + 0.3 * n3(q, 0.4, 3.0), py + dy * k, pz + dz * k))
        rings.append(ring)
    # moldura: da borda da boca (que já entra na rocha) até o fim, enterrado atrás da parede do Terrain
    offsets = [0.0, 1.0, 2.6, 4.8, 7.8, 11.5, 16.0, 21.0]
    depths = [-61.4, -59.2, -58.5, -58.9, -59.9, -61.3, -63.5, -67.0]
    amps = [0.2, 0.6, 0.9, 1.0, 1.1, 1.0, 0.8, 0.5]
    for k, d in enumerate(offsets):
        ring = []
        for z, y in outline:
            dz, dy = outward((z, y))
            pz, py = z + dz * d, max(-1.0, y + dy * d)
            q = (depths[k], py, pz)
            x = depths[k] + amps[k] * 1.6 * n3(q, 0.16, 7.0)
            ring.append((x, py + 0.45 * n3(q, 0.3, 1.0), pz + 0.45 * n3(q, 0.3, 2.0)))
        rings.append(ring)
    return rings, outline


def sheet(rings: list, first: int, last: int) -> tuple[list, list]:
    """Faixa de quads entre os anéis first..last (os anéis são abertos: não fecha a volta)."""
    verts, faces = [], []
    width = len(rings[0])
    for r in rings[first : last + 1]:
        for p in r:
            verts.append(LB.rb(*p))
    for a in range(last - first):
        for i in range(width - 1):
            v0 = a * width + i
            faces.append((v0, v0 + 1, v0 + width + 1, v0 + width))
    return verts, faces


# ---------------------------------------------------------------- Veios da Fenda


def lightning(rng: random.Random, start, angle: float, length: float, width: float, depth: int, out: list) -> None:
    """Raio que se ramifica (no plano z, y)."""
    seg = 1.5
    pts = [start]
    a = angle
    p = start
    for _ in range(max(2, int(length / seg))):
        a += rng.uniform(-0.55, 0.55)
        p = (p[0] + math.cos(a) * seg, p[1] + math.sin(a) * seg)
        pts.append(p)
        if depth < 3 and rng.random() < 0.2:
            turn = rng.choice((-1, 1)) * rng.uniform(0.5, 1.1)
            lightning(rng, p, a + turn, length * rng.uniform(0.35, 0.6), width * 0.62, depth + 1, out)
    out.append((pts, width))


def vein_ribbons(rng: random.Random, target, col, mat):
    """Projeta os raios na superfície da rocha (raio de +x para -x) e faz fitas finas um pouco acima dela."""
    bvh = BVHTree.FromObject(target, bpy.context.evaluated_depsgraph_get())
    branches: list = []
    top = (0.8, MOUTH_TOP + 1.6)
    lightning(rng, top, math.pi / 2, 20, 0.6, 0, branches)
    lightning(rng, top, math.pi / 2 + 0.6, 12, 0.45, 1, branches)
    lightning(rng, top, math.pi / 2 - 0.7, 12, 0.45, 1, branches)
    for y in (6.0, 13.0, 19.0):
        lightning(rng, (-7.5 + y * 0.2, y), math.pi + rng.uniform(-0.4, 0.4), rng.uniform(9, 14), 0.42, 1, branches)
        lightning(rng, (7.0 - y * 0.2, y), rng.uniform(-0.4, 0.4), rng.uniform(9, 14), 0.42, 1, branches)
    verts, faces = [], []
    for pts, width in branches:
        hits = []
        for z, y in pts:
            origin = LB.rb(-45.0, y, z)
            loc, normal, _, _ = bvh.ray_cast(origin, Vector((-1.0, 0.0, 0.0)), 40.0)
            hits.append((loc, normal) if loc is not None else None)
        run: list = []
        for h in hits + [None]:
            if h is None:
                if len(run) >= 2:
                    _ribbon(run, width, verts, faces)
                run = []
            else:
                run.append(h)
    return LB.mesh_object("FendaVeios_1", verts, faces, col, mat)


def _ribbon(run: list, width: float, verts: list, faces: list) -> None:
    count = len(run)
    for i, (loc, normal) in enumerate(run):
        prev_loc = run[max(0, i - 1)][0]
        next_loc = run[min(count - 1, i + 1)][0]
        tangent = (next_loc - prev_loc).normalized()
        side = normal.cross(tangent).normalized()
        w = width * (1.0 - 0.65 * i / max(1, count - 1))
        base = loc + normal * 0.12
        verts.append(base - side * w / 2)
        verts.append(base + side * w / 2)
        if i > 0:
            v = len(verts) - 4
            faces.append((v, v + 1, v + 3, v + 2))


# ---------------------------------------------------------------- cristais


def crystal_clusters(rng: random.Random) -> list:
    """Cristais no pé da boca, nos lábios e lá dentro do túnel (o brilho que dá profundidade)."""
    tris: list = []
    spots = [
        # (base x, y, z), direção para onde inclinam, quantos, altura mín/máx, raio mín/máx
        ((FACE_X + 0.9, -0.6, -7.4), (0.5, 1.0, -0.4), 6, 4.0, 11.0, 0.9, 1.8),
        ((FACE_X + 0.9, -0.6, 7.2), (0.5, 1.0, 0.4), 5, 3.5, 9.5, 0.8, 1.6),
        ((FACE_X + 2.6, 12.5, -6.6), (0.8, 0.5, -0.5), 3, 2.4, 5.0, 0.5, 1.0),
        ((FACE_X + 2.8, 18.0, 4.8), (0.8, 0.5, 0.5), 3, 2.0, 4.4, 0.45, 0.9),
        ((FACE_X + 2.0, 29.5, 1.0), (0.7, 1.0, 0.1), 3, 2.5, 5.5, 0.5, 1.0),
        ((FACE_X - 10.0, -0.6, -6.8), (0.3, 1.0, 0.6), 4, 4.5, 9.0, 0.8, 1.5),
        ((FACE_X - 15.0, -0.6, 2.6), (0.2, 1.0, -0.7), 5, 5.0, 11.0, 0.9, 1.7),
    ]
    for base, lean, count, h0, h1, r0, r1 in spots:
        lean_v = Vector(lean).normalized()
        for _ in range(count):
            off = (rng.uniform(-1.2, 1.2), 0.0, rng.uniform(-1.2, 1.2))
            b = (base[0] + off[0], base[1], base[2] + off[2])
            axis = (lean_v + Vector((rng.uniform(-0.35, 0.35), 0.0, rng.uniform(-0.35, 0.35)))).normalized()
            tris += CR.crystal(rng, b, tuple(axis), rng.uniform(r0, r1), rng.uniform(h0, h1),
                               sides=rng.choice([5, 6, 6]), tip=0.32)
    return tris


# ---------------------------------------------------------------- montagem


def build_fenda():
    rng = random.Random(4101)
    col = LB.collection("Entrada Torre 1 - Fenda")
    rock = LB.material("Rocha", (150, 140, 175))
    dark = LB.material("Tunel", (90, 80, 115))
    black = LB.material("Fundo", (8, 6, 14))
    vein = LB.material("Veio", (138, 60, 255), emission=4.0)
    tone_mats = [LB.material(n, c, emission=e) for n, c, e in (
        ("CristalClaro", (100, 78, 232), 3.0), ("CristalMedio", (78, 36, 200), 2.0), ("CristalEscuro", (58, 26, 130), 0.0))]

    rings, outline = fenda_rings(rng)
    mouth = 6  # índice do anel da borda da boca (depois dos 6 do túnel)
    verts, faces = sheet(rings, mouth, len(rings) - 1)
    frame = LB.mesh_object("FendaRocha_1", verts, faces, col, rock)
    verts, faces = sheet(rings, 0, mouth)
    tunnel = LB.mesh_object("FendaTunel_1", verts, faces, col, dark)
    # a frente da moldura aponta para a avenida (+x); o túnel aponta para dentro do vão
    if not LB.outward_ok(frame, LB.rb(FACE_X + 3.5, MOUTH_TOP + 6, 0.5), Vector((1, 0, 0))):
        LB.flip(frame)
    if not LB.outward_ok(tunnel, LB.rb(FACE_X - 8, 8, -7.5), Vector((0, -1, 0))):
        LB.flip(tunnel)
    for ob in (frame, tunnel):
        ob.data.update()
    # rocha orgânica (sem isso a moldura de anéis parecia um bolo em camadas)
    LB.roughen(frame, cuts=2, amp=1.4, scale=0.11, seed=3.0)
    LB.roughen(tunnel, cuts=1, amp=0.7, scale=0.2, seed=9.0)

    # pedras grandes encaixadas em volta da boca (quebram o contorno, como os rochedos das referências)
    boulders: list = []
    for z, y, w, h in ((-10.5, 2.0, 6.0, 5.0), (-11.0, 9.5, 4.6, 4.0), (-8.8, 17.0, 4.0, 3.4), (10.2, 1.6, 6.4, 5.2),
                       (10.6, 10.0, 4.4, 3.8), (7.4, 19.5, 3.6, 3.0), (-3.6, 31.5, 4.4, 3.6), (4.2, 33.0, 3.8, 3.2)):
        x = FACE_X + 2.2 + rng.uniform(-0.4, 0.3)
        tris = FO.boulder(rng, (x, y, z), (w * 0.55, h * 0.6, w * 0.5))
        boulders += tris
    rocks = LB.tris_object("FendaPedras_1", boulders, col, rock)

    # chão do túnel (o Terrain é escavado por baixo) e o fundo escuro, no anel mais fundo
    floor_v, floor_f = [], []
    for j in range(mouth + 1):
        ring = rings[j]
        floor_v.append(LB.rb(ring[0][0], 0.06, ring[0][2] - 0.6))
        floor_v.append(LB.rb(ring[-1][0], 0.06, ring[-1][2] + 0.6))
        if j > 0:
            v = len(floor_v) - 4
            floor_f.append((v, v + 2, v + 3, v + 1))
    floor = LB.mesh_object("FendaChao_1", floor_v, floor_f, col, dark)
    if floor.data.polygons[0].normal.z < 0:
        LB.flip(floor)
    deep = rings[0]
    cx = sum(p[0] for p in deep) / len(deep)
    center = LB.rb(cx - 0.5, sum(p[1] for p in deep) / len(deep), sum(p[2] for p in deep) / len(deep))
    cap_v = [center] + [LB.rb(*p) for p in deep]
    cap_f = [(0, i, i + 1) for i in range(1, len(deep))] + [(0, len(deep), 1)]
    cap = LB.mesh_object("FendaFundo_1", cap_v, cap_f, col, black)
    if cap.data.polygons[0].normal.x < 0:
        LB.flip(cap)

    veins = vein_ribbons(rng, frame, col, vein)
    if veins.data.polygons and veins.data.polygons[0].normal.x < 0:
        LB.flip(veins)

    light, mid, darkf = CR.tones(crystal_clusters(rng))
    crystals = [
        LB.tris_object(name, tris, col, m)
        for name, tris, m in zip(("FendaCristalClaro_1", "FendaCristalMedio_1", "FendaCristalEscuro_1"),
                                 (light, mid, darkf), tone_mats)
    ]
    objects = [frame, tunnel, rocks, floor, cap, veins, *crystals]
    report = {ob.name: LB.triangles(ob) for ob in objects}
    total = sum(report.values())
    assert total <= BUDGET, f"Fenda: {total} triângulos passa do orçamento {BUDGET}"
    return objects, report
