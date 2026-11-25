"""Peças de pedra lavrada do Lobby 1: colunas, capitéis, arcos e a escadaria do Altar do Coração.

O designer pediu (após o pacote do vídeo "Environmental Art") que nada de pedra tenha forma geométrica perfeita:
coluna não é um cilindro liso com textura, degrau não é um paralelepípedo reto. Aqui cada peça é feita de blocos e
tambores lascados: ruído nos vértices, arestas chanfradas de forma desigual, lascas arrancadas, tambores desalinhados.
A textura vem do material Rock (pedra pintada do pacote, via MaterialService); a base das colunas usa as rochas do
próprio pacote (Stone_1–5), montadas pelo scripts/lobby1-pedras.luau.

Saída: lobby1-claude-code/modelos/pedras/PedrasLobby1.glb (1 upload = 1 asset) e PedrasLobby1.json (centro da caixa
de cada malha, que o .luau usa para pôr cada MeshPart no lugar: o Roblox centraliza a malha na caixa dela).

Unidades: 1 unidade = 1 stud, Y para cima. Colunas, faixas, capitéis e arcos em coordenadas locais (eixo da coluna
na origem, chão em y = 0); escadaria e plataforma do altar já em coordenadas do mundo.

Uso (na raiz do projeto):  python scripts/lobby1-pedras.py
Só biblioteca padrão; semente fixa (o mesmo arquivo sai igual toda vez).
"""

from __future__ import annotations

import json
import math
import os
import random
import struct

Vec = tuple[float, float, float]
Tri = tuple[Vec, Vec, Vec]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "lobby1-claude-code", "modelos", "pedras")
OUT = os.path.join(OUT_DIR, "PedrasLobby1.glb")
OUT_JSON = os.path.join(OUT_DIR, "PedrasLobby1.json")

# Orçamento (CLAUDE.md do lobby1): módulos de coluna ≤ 3.000; peças principais ≤ 10.000
BUDGET = {
    "Fuste": 3000,
    "FaixaDourada": 600,
    "Capitel": 1500,
    "Abaco": 1500,
    "Arco": 3000,
    "Escadaria": 10000,
    "PlataformaDoAltar": 10000,
}

UV_TILE = 8.0  # studs por repetição da textura (o mesmo das formações)


def sub(a: Vec, b: Vec) -> Vec:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def scale(a: Vec, s: float) -> Vec:
    return (a[0] * s, a[1] * s, a[2] * s)


def cross(a: Vec, b: Vec) -> Vec:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a: Vec, b: Vec) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def norm(a: Vec) -> Vec:
    length = math.sqrt(dot(a, a)) or 1.0
    return (a[0] / length, a[1] / length, a[2] / length)


def oriented(a: Vec, b: Vec, c: Vec, inside: Vec) -> Tri:
    """Triângulo com a frente virada para fora, longe do ponto `inside`."""
    n = cross(sub(b, a), sub(c, a))
    centroid = scale(add(add(a, b), c), 1 / 3)
    if dot(n, sub(centroid, inside)) < 0:
        return (a, c, b)
    return (a, b, c)


def rot_y(p: Vec, angle: float) -> Vec:
    c, s = math.cos(angle), math.sin(angle)
    return (p[0] * c + p[2] * s, p[1], -p[0] * s + p[2] * c)


# ---------------------------------------------------------------- bloco lascado


def block(
    rng: random.Random,
    center: Vec,
    size: Vec,
    seg: tuple[int, int, int] | None = None,
    noise: float = 0.12,
    chamfer: float = 0.35,
    chips: int = 2,
    chip_depth: float = 0.7,
    top_noise: float | None = None,
    flat_bottom: bool = True,
    yaw: float = 0.0,
    taper: float = 0.0,
) -> list[Tri]:
    """Paralelepípedo de pedra lavrada e gasta.

    - grade em cada face (seg = divisões em x, y, z), vértices compartilhados entre faces;
    - ruído em todos os vértices (noise, em studs), menor no topo (top_noise: o topo dos degraus é pisável);
    - arestas puxadas para dentro de forma desigual (chamfer) e cantos mais ainda;
    - `chips` lascas: um vértice de aresta e os vizinhos afundam chip_depth;
    - taper > 0: o topo fica mais largo que a base (capitel).
    """
    w, h, d = size
    if seg is None:
        seg = (max(2, round(w / 3)), max(1, round(h / 2.5)), max(2, round(d / 3)))
    nx, ny, nz = seg
    if top_noise is None:
        top_noise = noise
    verts: dict[tuple[int, int, int], Vec] = {}

    def on_surface(i: int, j: int, k: int) -> bool:
        return i in (0, nx) or j in (0, ny) or k in (0, nz)

    for i in range(nx + 1):
        for j in range(ny + 1):
            for k in range(nz + 1):
                if not on_surface(i, j, k):
                    continue
                u, v, t = i / nx - 0.5, j / ny - 0.5, k / nz - 0.5
                spread = 1 + taper * (v + 0.5)
                p = [u * w * spread, v * h, t * d * spread]
                boundary = (i in (0, nx)) + (j in (0, ny)) + (k in (0, nz))
                amp = top_noise if j == ny else noise
                for axis in range(3):
                    p[axis] += rng.uniform(-amp, amp)
                if boundary >= 2:  # aresta ou canto: chanfro desigual, puxado para o centro
                    pull = chamfer * rng.uniform(0.5, 1.4) * (1.6 if boundary == 3 else 1.0)
                    if i in (0, nx):
                        p[0] -= math.copysign(pull, u)
                    if k in (0, nz):
                        p[2] -= math.copysign(pull, t)
                    if j == ny:
                        p[1] -= pull * 0.6
                if flat_bottom and j == 0:
                    p[1] = -h / 2
                verts[(i, j, k)] = (p[0], p[1], p[2])

    # lascas: vértices de aresta (não da base) afundam para o centro, com os vizinhos pela metade
    edge_keys = [key for key in verts if sum((key[0] in (0, nx), key[1] in (0, ny), key[2] in (0, nz))) >= 2]
    edge_keys = [key for key in edge_keys if key[1] != 0 or not flat_bottom]
    for _ in range(chips):
        key = rng.choice(edge_keys)
        depth = chip_depth * rng.uniform(0.6, 1.2)
        for other, p in list(verts.items()):
            dist = abs(other[0] - key[0]) + abs(other[1] - key[1]) + abs(other[2] - key[2])
            if dist > 1 or (flat_bottom and other[1] == 0):
                continue
            f = 1.0 if dist == 0 else 0.45
            direction = norm((p[0], p[1] * 0.6, p[2]))
            verts[other] = sub(p, scale(direction, depth * f))

    tris: list[Tri] = []

    def quad(a, b, c, e) -> None:
        pa, pb, pc, pe = verts[a], verts[b], verts[c], verts[e]
        tris.append(oriented(pa, pb, pc, (0.0, 0.0, 0.0)))
        tris.append(oriented(pa, pc, pe, (0.0, 0.0, 0.0)))

    for i in range(nx):
        for k in range(nz):
            for j in (0, ny):
                quad((i, j, k), (i + 1, j, k), (i + 1, j, k + 1), (i, j, k + 1))
    for i in range(nx):
        for j in range(ny):
            for k in (0, nz):
                quad((i, j, k), (i + 1, j, k), (i + 1, j + 1, k), (i, j + 1, k))
    for j in range(ny):
        for k in range(nz):
            for i in (0, nx):
                quad((i, j, k), (i, j + 1, k), (i, j + 1, k + 1), (i, j, k + 1))

    out: list[Tri] = []
    for tri in tris:
        out.append(tuple(add(rot_y(p, yaw), center) for p in tri))  # type: ignore[misc]
    return out


# ---------------------------------------------------------------- coluna


JOINTS = [0.0, 9.0, 21.0, 33.0, 45.5, 58.0, 69.5, 81.0, 90.0]  # juntas dos tambores; as faixas douradas cobrem 9, 33, 58, 81
SHAFT_RADIUS = 6.0
SIDES = 16


def fuste(seed: int) -> list[Tri]:
    """Fuste de 90 studs em 8 tambores lascados, levemente desalinhados, com êntase (afina para cima)."""
    rng = random.Random(seed)
    tris: list[Tri] = []
    for n in range(len(JOINTS) - 1):
        y0, y1 = JOINTS[n], JOINTS[n + 1]
        offset = (rng.uniform(-0.15, 0.15), 0.0, rng.uniform(-0.15, 0.15))
        angle0 = rng.uniform(0, math.tau)
        hs = [y0, y0 + 0.45, y0 + (y1 - y0) * 0.35, y0 + (y1 - y0) * 0.7, y1 - 0.45, y1]
        rings: list[list[Vec]] = []
        for r_i, y in enumerate(hs):
            base_r = SHAFT_RADIUS * (1 - 0.05 * y / 90)
            edge = r_i in (0, len(hs) - 1)
            pts = []
            for s in range(SIDES):
                a = angle0 + math.tau * s / SIDES + rng.uniform(-0.05, 0.05)
                r = base_r * rng.uniform(0.965, 1.025) * (rng.uniform(0.9, 0.95) if edge else 1.0)
                yy = y if edge else y + rng.uniform(-0.25, 0.25)
                pts.append((offset[0] + math.cos(a) * r, yy, offset[2] + math.sin(a) * r))
            rings.append(pts)
        # lascas: 1 a 3 por tambor, nas arestas de cima/baixo (anéis 0-1 ou 4-5) ou no meio da face
        for _ in range(rng.randint(1, 3)):
            ring = rng.choice([0, 1, 1, 2, 3, 4, 4, 5])
            s = rng.randrange(SIDES)
            depth = rng.uniform(0.35, 0.9)
            for ds, f in ((0, 1.0), (-1, 0.5), (1, 0.5)):
                for dr, g in ((0, 1.0), (-1, 0.5), (1, 0.5)):
                    rr = ring + dr
                    if 0 <= rr < len(rings):
                        idx = (s + ds) % SIDES
                        p = rings[rr][idx]
                        radial = norm((p[0] - offset[0], 0.0, p[2] - offset[2]))
                        rings[rr][idx] = sub(p, scale(radial, depth * f * g))
        mid_c = (offset[0], (y0 + y1) / 2, offset[2])
        for r_i in range(len(rings) - 1):
            lo, hi = rings[r_i], rings[r_i + 1]
            for s in range(SIDES):
                t = (s + 1) % SIDES
                tris.append(oriented(lo[s], lo[t], hi[t], mid_c))
                tris.append(oriented(lo[s], hi[t], hi[s], mid_c))
        for ring, inside_y in ((rings[0], y0 + 1), (rings[-1], y1 - 1)):
            c = (offset[0], ring[0][1], offset[2])
            inside = (offset[0], inside_y, offset[2])
            for s in range(SIDES):
                t = (s + 1) % SIDES
                tris.append(oriented(c, ring[s], ring[t], inside))
    return tris


def faixa(seed: int) -> list[Tri]:
    """Faixa de ouro gasto em volta da junta: anel de 18 lados, 1,4 de altura, amassado."""
    rng = random.Random(seed)
    sides = 18
    rings = []
    for y, k in ((-0.7, 0.97), (-0.45, 1.0), (0.45, 1.0), (0.7, 0.97)):
        pts = []
        for s in range(sides):
            a = math.tau * s / sides
            r = 6.55 * k * rng.uniform(0.985, 1.015)
            pts.append((math.cos(a) * r, y + rng.uniform(-0.06, 0.06), math.sin(a) * r))
        rings.append(pts)
    tris: list[Tri] = []
    for r_i in range(len(rings) - 1):
        lo, hi = rings[r_i], rings[r_i + 1]
        for s in range(sides):
            t = (s + 1) % sides
            tris.append(oriented(lo[s], lo[t], hi[t], (0.0, 0.0, 0.0)))
            tris.append(oriented(lo[s], hi[t], hi[s], (0.0, 0.0, 0.0)))
    for ring, inside_y in ((rings[0], 0.5), (rings[-1], -0.5)):
        c = (0.0, ring[0][1], 0.0)
        for s in range(sides):
            t = (s + 1) % sides
            tris.append(oriented(c, ring[s], ring[t], (0.0, inside_y, 0.0)))
    return tris


def capitel(seed: int) -> list[Tri]:
    """Capitel: tronco de pirâmide lascado (13 embaixo, 15,5 em cima, 5 de altura), centro em y = 0."""
    rng = random.Random(seed)
    return block(rng, (0, 0, 0), (13.0, 5.0, 13.0), seg=(4, 2, 4), noise=0.15, chamfer=0.45, chips=4,
                 chip_depth=0.9, taper=0.2, flat_bottom=False)


def abaco(seed: int) -> list[Tri]:
    """Ábaco: laje grossa e gasta sobre o capitel (17 × 2 × 17)."""
    rng = random.Random(seed)
    return block(rng, (0, 0, 0), (17.0, 2.0, 17.0), seg=(5, 1, 5), noise=0.14, chamfer=0.4, chips=4,
                 chip_depth=0.8, flat_bottom=False)


def arco(seed: int) -> list[Tri]:
    """Viga entre as colunas (8 × 6 × 34): três blocos de pedra encaixados, cada um com as suas lascas."""
    rng = random.Random(seed)
    tris: list[Tri] = []
    z = -17.0
    lengths = [rng.uniform(10, 12.5), 0.0, rng.uniform(10, 12.5)]
    lengths[1] = 34 - lengths[0] - lengths[2]
    for length in lengths:
        c = (rng.uniform(-0.12, 0.12), rng.uniform(-0.1, 0.1), z + length / 2)
        tris += block(rng, c, (8.0, 6.0, length - 0.1), seg=(3, 2, 4), noise=0.13, chamfer=0.4, chips=3,
                      chip_depth=0.8, flat_bottom=False, yaw=rng.uniform(-0.015, 0.015))
        z += length
    return tris


# ---------------------------------------------------------------- altar (coordenadas do mundo)

# Degraus medidos no place: 8 degraus de 34 de largura, 2,5 de fundo, topo em y = k (k = 1..8), centro z da lista;
# Plataforma do Altar: 34 × 8 × 16, centro (0, 4, -106). As Parts originais ficam invisíveis, só para colisão: o topo
# de cada pedra fica a ±0,1 do topo da Part (o pé do personagem não afunda nem flutua).
STEP_Z = [-79.2, -81.8, -84.2, -86.8, -89.2, -91.8, -94.2, -96.8]
STAIR_HALF = 17.0


def escadaria(seed: int) -> list[Tri]:
    rng = random.Random(seed)
    tris: list[Tri] = []
    for k, zc in enumerate(STEP_Z, 1):
        top = float(k)
        depth = 2.5
        # pedras do degrau (o espelho visível vai de k-1 a k; a pedra desce um pouco mais e some atrás do degrau de baixo)
        h = 1.6 if k > 1 else 1.05
        x = -STAIR_HALF + 2.2  # as pontas ficam com as pedras de flanco
        end = STAIR_HALF - 2.2
        while x < end - 0.5:
            wdt = min(rng.uniform(5.0, 8.5), end - x)
            if end - (x + wdt) < 3.0:
                wdt = end - x
            # 3,2 de fundo, recuada 0,3: a frente fica na frente da Part e o fundo entra embaixo da fileira de cima
            # (com 2,65 de fundo sobrava um vão escuro entre as fileiras: os degraus pareciam tábuas soltas)
            c = (x + wdt / 2, top - h / 2 + rng.uniform(-0.06, 0.04), zc - 0.3 + rng.uniform(-0.05, 0.1))
            tris += block(rng, c, (wdt - 0.08, h, depth + 0.7), seg=(max(2, round(wdt / 2.5)), 1, 2),
                          noise=0.1, chamfer=0.2, chips=2, chip_depth=0.45, top_noise=0.05,
                          yaw=rng.uniform(-0.012, 0.012), flat_bottom=False)
            x += wdt
        # flancos: um bloco alto em cada ponta, do chão até o topo do degrau
        for side in (-1, 1):
            fw = 2.3
            c = (side * (STAIR_HALF - fw / 2 + 0.05), top / 2, zc)
            tris += block(rng, c, (fw, top + 0.02, depth + 0.1), seg=(1, max(1, round(top / 2)), 2), noise=0.1,
                          chamfer=0.25, chips=1, chip_depth=0.4, top_noise=0.05)
    return tris


def plataforma(seed: int) -> list[Tri]:
    """Plataforma do Altar: lajes grandes no topo e fiadas de blocos nas laterais e no fundo."""
    rng = random.Random(seed)
    tris: list[Tri] = []
    x0, x1, z0, z1, top = -17.0, 17.0, -114.0, -98.0, 8.0
    # topo: 3 × 2 lajes irregulares de 0,9 de espessura
    xs = [x0, -6.0 + rng.uniform(-1, 1), 6.0 + rng.uniform(-1, 1), x1]
    zs = [z0, -106.0 + rng.uniform(-1, 1), z1]
    for i in range(3):
        for j in range(2):
            w, d = xs[i + 1] - xs[i], zs[j + 1] - zs[j]
            c = ((xs[i] + xs[i + 1]) / 2, top - 0.45 + rng.uniform(-0.04, 0.03), (zs[j] + zs[j + 1]) / 2)
            tris += block(rng, c, (w - 0.1, 0.9, d - 0.1), seg=(4, 1, 3), noise=0.08, chamfer=0.3, chips=2,
                          chip_depth=0.4, top_noise=0.04, flat_bottom=False)
    # paredes: 3 fiadas (0 a 7,1) de blocos de 4 a 7 studs; juntas desencontradas entre as fiadas
    courses = [(0.0, 2.4), (2.4, 4.8), (4.8, 7.15)]
    walls = [  # (início, fim, fixo, eixo do comprimento, lado de fora)
        ((x0, x1), z0, "x", -1),
        ((z0, z1), x0, "z", -1),
        ((z0, z1), x1, "z", 1),
    ]
    for (a0, a1), fixed, axis, out_sign in walls:
        for n, (y0, y1) in enumerate(courses):
            pos = a0 + (rng.uniform(1.0, 3.0) if n % 2 else 0.0)
            if n % 2:
                pos = a0
                first = rng.uniform(2.0, 3.5)
            else:
                first = rng.uniform(4.0, 7.0)
            length = first
            while pos < a1 - 0.3:
                length = min(length, a1 - pos)
                if a1 - (pos + length) < 2.5:
                    length = a1 - pos
                mid = pos + length / 2
                thick = 2.0
                inset = fixed - out_sign * (thick / 2 - rng.uniform(0.0, 0.12))
                if axis == "x":
                    c, size = (mid, (y0 + y1) / 2, inset), (length - 0.1, y1 - y0 - 0.06, thick)
                    seg = (max(2, round(length / 2.5)), 1, 1)
                else:
                    c, size = (inset, (y0 + y1) / 2, mid), (thick, y1 - y0 - 0.06, length - 0.1)
                    seg = (1, 1, max(2, round(length / 2.5)))
                tris += block(rng, c, size, seg=seg, noise=0.1, chamfer=0.3, chips=2, chip_depth=0.5,
                              flat_bottom=(n == 0))
                pos += length
                length = rng.uniform(4.0, 7.0)
    return tris


# ---------------------------------------------------------------- GLB


def srgb_to_linear(c: int) -> float:
    s = c / 255
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


def hex_linear(h: str) -> list[float]:
    return [srgb_to_linear(int(h[i : i + 2], 16)) for i in (0, 2, 4)] + [1.0]


def mesh_arrays(tris: list[Tri], uv_mode: str):
    """Vértices por face (sombreamento chapado). UV: 'planar' (projeção pelo eixo da normal) ou 'cyl' (em volta do
    eixo Y: a textura dá a volta no fuste sem costura entre as faces)."""
    pos, nrm, uv, idx = bytearray(), bytearray(), bytearray(), bytearray()
    lo = [math.inf] * 3
    hi = [-math.inf] * 3
    n_vert = 0
    for a, b, c in tris:
        n = norm(cross(sub(b, a), sub(c, a)))
        uvs = []
        if uv_mode == "cyl" and abs(n[1]) < 0.7:
            angles = [math.atan2(p[2], p[0]) for p in (a, b, c)]
            ref = angles[0]
            angles = [x + math.tau if x - ref < -math.pi else x - math.tau if x - ref > math.pi else x for x in angles]
            uvs = [(ang * SHAFT_RADIUS / UV_TILE, p[1] / UV_TILE) for ang, p in zip(angles, (a, b, c))]
        else:
            ax = max(range(3), key=lambda i: abs(n[i]))
            u_axis, v_axis = [(2, 1), (0, 2), (0, 1)][ax]
            uvs = [(p[u_axis] / UV_TILE, p[v_axis] / UV_TILE) for p in (a, b, c)]
        for p, t in zip((a, b, c), uvs):
            pos += struct.pack("<3f", *p)
            nrm += struct.pack("<3f", *n)
            uv += struct.pack("<2f", *t)
            idx += struct.pack("<H", n_vert)
            n_vert += 1
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    assert n_vert < 65536, "índices de 16 bits"
    return bytes(pos), bytes(nrm), bytes(uv), bytes(idx), lo, hi, n_vert


def pieces() -> list[dict]:
    items: list[dict] = []
    for i in range(1, 4):
        items.append({"name": f"Fuste_{i}", "tris": fuste(500 + i), "uv": "cyl"})
    for i in range(1, 3):
        items.append({"name": f"FaixaDourada_{i}", "tris": faixa(600 + i), "uv": "cyl"})
    for i in range(1, 4):
        items.append({"name": f"Capitel_{i}", "tris": capitel(700 + i), "uv": "planar"})
    for i in range(1, 4):
        items.append({"name": f"Abaco_{i}", "tris": abaco(800 + i), "uv": "planar"})
    for i in range(1, 4):
        items.append({"name": f"Arco_{i}", "tris": arco(900 + i), "uv": "planar"})
    items.append({"name": "Escadaria_1", "tris": escadaria(1001), "uv": "planar"})
    items.append({"name": "PlataformaDoAltar_1", "tris": plataforma(1101), "uv": "planar"})
    return items


def write_glb(items: list[dict], path: str) -> dict:
    material = {"name": "Pedra", "pbrMetallicRoughness": {"baseColorFactor": hex_linear("4A4462"), "metallicFactor": 0.0,
                                                          "roughnessFactor": 0.95}}
    gltf: dict = {"asset": {"version": "2.0", "generator": "lobby1-pedras.py"}, "scene": 0, "scenes": [{"nodes": []}],
                  "nodes": [], "meshes": [], "materials": [material], "accessors": [], "bufferViews": [],
                  "buffers": []}
    blob = bytearray()
    info: dict = {}

    def view(data: bytes, target: int) -> int:
        while len(blob) % 4:
            blob.append(0)
        gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob.extend(data)
        return len(gltf["bufferViews"]) - 1

    def accessor(view_index: int, comp: int, count: int, kind: str, lo=None, hi=None) -> int:
        acc = {"bufferView": view_index, "componentType": comp, "count": count, "type": kind}
        if lo is not None:
            acc["min"], acc["max"] = lo, hi
        gltf["accessors"].append(acc)
        return len(gltf["accessors"]) - 1

    for item in items:
        name, tris = item["name"], item["tris"]
        kind = name.split("_")[0]
        assert len(tris) <= BUDGET[kind], f"{name}: {len(tris)} triângulos passa do orçamento {BUDGET[kind]}"
        volume = sum(dot(a, cross(b, c)) for a, b, c in tris) / 6
        assert volume > 0, f"{name}: faces viradas para dentro (volume {volume:.1f})"
        pos, nrm, uv, idx, lo, hi, count = mesh_arrays(tris, item["uv"])
        prim = {
            "attributes": {
                "POSITION": accessor(view(pos, 34962), 5126, count, "VEC3", lo, hi),
                "NORMAL": accessor(view(nrm, 34962), 5126, count, "VEC3"),
                "TEXCOORD_0": accessor(view(uv, 34962), 5126, count, "VEC2"),
            },
            "indices": accessor(view(idx, 34963), 5123, count, "SCALAR"),
            "material": 0,
        }
        gltf["meshes"].append({"name": name, "primitives": [prim]})
        # cada peça é um nó na origem: no arquivo elas se sobrepõem, mas o importador separa por nó e o .luau
        # posiciona cada uma pelo centro da caixa (json)
        gltf["nodes"].append({"name": name, "mesh": len(gltf["meshes"]) - 1})
        gltf["scenes"][0]["nodes"].append(len(gltf["nodes"]) - 1)
        center = [round((lo[i] + hi[i]) / 2, 3) for i in range(3)]
        size = [round(hi[i] - lo[i], 3) for i in range(3)]
        info[name] = {"center": center, "size": size, "tris": len(tris)}
        print(f"{name}: {len(tris)} triângulos, tamanho {size}, centro {center}, volume {volume:.0f}")

    while len(blob) % 4:
        blob.append(0)
    gltf["buffers"].append({"byteLength": len(blob)})
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4:
        json_bytes += b" "
    total = 12 + 8 + len(json_bytes) + 8 + len(blob)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(json_bytes), 0x4E4F534A))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(blob), 0x004E4942))
        f.write(blob)
    return info


if __name__ == "__main__":
    data = write_glb(pieces(), OUT)
    with open(OUT_JSON, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1, ensure_ascii=False)
    print(f"ok: {OUT}")
