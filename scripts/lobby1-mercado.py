"""Peças do Mercado das Raízes (Lobby 1): as bancas e as mercadorias.

Mesmo caminho das pedras e dos cristais (scripts/lobby1-pedras.py): malha por código → GLB → upload (asset na conta
do Filipe) → montagem pelo scripts/lobby1-mercado.luau. Reaproveita o bloco lascado, o GLB e as verificações do
lobby1-pedras.py.

Referência 07 (canto inferior direito): bancas de madeira com toldo de pano, mercadoria em caixotes, barris, sacos e
cestos, cristais roxos à venda. Padrão de beleza do jogo (GDD): nada reto e perfeito; a madeira é de tábuas tortas e
gastas, o pano cai entre as vigas e tem babado recortado na frente.

Cada material é uma malha separada (no Roblox o material e a cor vão por MeshPart): madeira, pano (duas listras),
metal dos aros, pano dos sacos, cristal (tons claro e escuro) e cogumelo (haste e chapéu que brilha).

Coordenadas locais. Banca: centro do balcão no chão na origem, frente (o lado do freguês) para -z. Mercadorias: base
no chão, centro na origem. 1 unidade = 1 stud, Y para cima.

Uso (na raiz do projeto):  python scripts/lobby1-mercado.py
"""

from __future__ import annotations

import importlib.util
import json
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("pedras", os.path.join(HERE, "lobby1-pedras.py"))
assert _spec and _spec.loader
P = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(P)

Vec = P.Vec
Tri = P.Tri
add, sub, scale, norm, cross, dot, oriented = P.add, P.sub, P.scale, P.norm, P.cross, P.dot, P.oriented

OUT_DIR = os.path.join(P.ROOT, "lobby1-claude-code", "modelos", "mercado")
OUT = os.path.join(OUT_DIR, "MercadoLobby1.glb")
OUT_JSON = os.path.join(OUT_DIR, "MercadoLobby1.json")

# Orçamento (CLAUDE.md do lobby1): props de roleplay ≤ 2.000 por malha
P.BUDGET.update({
    "BancaMadeira": 2000, "ToldoA": 2000, "ToldoB": 2000,
    "Caixote": 600, "Barril": 600, "AroBarril": 400, "Saco": 600, "Cesto": 600,
    "CristalClaro": 600, "CristalEscuro": 600, "CogumeloHaste": 600, "CogumeloChapeu": 800,
})


# ---------------------------------------------------------------- transformações


def rot_x(p: Vec, a: float) -> Vec:
    c, s = math.cos(a), math.sin(a)
    return (p[0], p[1] * c - p[2] * s, p[1] * s + p[2] * c)


def rot_z(p: Vec, a: float) -> Vec:
    c, s = math.cos(a), math.sin(a)
    return (p[0] * c - p[1] * s, p[0] * s + p[1] * c, p[2])


def moved(tris: list[Tri], fn) -> list[Tri]:
    return [(fn(a), fn(b), fn(c)) for a, b, c in tris]


def wood(rng: random.Random, size: Vec, seg=None) -> list[Tri]:
    """Tábua ou viga de madeira gasta, centrada na origem: pouco ruído, quina levemente comida, uma lasca."""
    return P.block(rng, (0.0, 0.0, 0.0), size, seg=seg, noise=0.04, chamfer=0.06, chips=1, chip_depth=0.12,
                   flat_bottom=False)


def beam(rng: random.Random, a: Vec, b: Vec, thick: float) -> list[Tri]:
    """Viga de seção quadrada de `a` até `b` (qualquer direção)."""
    d = sub(b, a)
    length = math.sqrt(dot(d, d))
    tris = wood(rng, (thick, length, thick), seg=(1, max(2, round(length / 2.5)), 1))
    axis = norm(d)
    # gira o eixo Y local para `axis`: primeiro inclina em x (pitch), depois gira em y (yaw)
    pitch = math.acos(max(-1.0, min(1.0, axis[1])))
    yaw = math.atan2(axis[0], axis[2])
    mid = scale(add(a, b), 0.5)
    return moved(tris, lambda p: add(P.rot_y(rot_x(p, pitch), yaw), mid))


def lathe(profile: list[tuple[float, float]], sides: int, rng: random.Random, jitter: float = 0.0,
          lumps: float = 0.0, phase: float = 0.0) -> list[Tri]:
    """Superfície de revolução fechada. `profile` = [(raio, altura)] de baixo para cima; raio 0 nas pontas fecha a
    malha. `lumps` deforma o raio por ângulo (saco cheio, irregular)."""
    rings = []
    for r, h in profile:
        ring = []
        for k in range(sides):
            ang = phase + math.tau * k / sides
            rr = r * (1 + lumps * math.sin(3 * ang + h * 2.1) * math.cos(2 * ang - h)) + rng.uniform(-jitter, jitter)
            ring.append((rr * math.cos(ang), h + rng.uniform(-jitter, jitter) * 0.5, rr * math.sin(ang)))
        rings.append(ring)
    tris: list[Tri] = []
    for i in range(len(rings) - 1):
        lo, hi = rings[i], rings[i + 1]
        for k in range(sides):
            k2 = (k + 1) % sides
            a, b, c, d = lo[k], lo[k2], hi[k2], hi[k]
            if profile[i][0] > 1e-6:
                tris.append((a, c, b))
            if profile[i + 1][0] > 1e-6:
                tris.append((a, d, c))
    volume = sum(dot(a, cross(b, c)) for a, b, c in tris)
    if volume < 0:
        tris = [(a, c, b) for a, b, c in tris]
    return tris


# ---------------------------------------------------------------- banca


def banca(seed: int, width: float, counter_depth: float, counter_h: float, back: float) -> dict[str, list[Tri]]:
    """Banca de feira: balcão de tábuas na frente, quatro postes um pouco tortos, prateleira atrás, vigas e o toldo
    de pano listrado que cai entre as vigas e tem babado recortado na frente. Devolve madeira e as duas listras."""
    rng = random.Random(seed)
    hw = width / 2
    z_f = -counter_depth / 2 - 0.15  # postes da frente, encostados no balcão
    z_b = counter_depth / 2 + back  # postes de trás (o vendedor fica entre o balcão e eles)
    h_f, h_b = 8.0, 9.6  # altura dos postes: o toldo desce para a frente
    post = 0.55
    madeira: list[Tri] = []

    tops: dict[tuple[int, int], Vec] = {}
    for sx in (-1, 1):
        for front in (True, False):
            x = sx * (hw - 0.3)
            z = z_f if front else z_b
            h = h_f if front else h_b
            lean = (rng.uniform(-0.05, 0.05), rng.uniform(-0.05, 0.05))
            top = (x + lean[0] * h, h, z + lean[1] * h)
            madeira += beam(rng, (x, 0.0, z), top, post)
            tops[(sx, 1 if front else 0)] = top

    # vigas de cima: frente, fundo e os lados inclinados (o toldo apoia nelas)
    lift = post / 2
    for key_a, key_b in (((-1, 1), (1, 1)), ((-1, 0), (1, 0)), ((-1, 0), (-1, 1)), ((1, 0), (1, 1))):
        a, b = tops[key_a], tops[key_b]
        madeira += beam(rng, add(a, (0, -lift, 0)), add(b, (0, -lift, 0)), 0.45)

    # balcão: corpo de tábuas em pé (uma por vez, alturas um pouco diferentes) + tampo grosso que sobra para fora
    body_h = counter_h - 0.35
    n_boards = max(4, round((width - 1.0) / 1.1))
    board_w = (width - 1.0) / n_boards
    for i in range(n_boards):
        x = -hw + 0.5 + board_w * (i + 0.5)
        h = body_h - rng.uniform(0.0, 0.15)
        for z_face in (-counter_depth / 2 + 0.12, counter_depth / 2 - 0.12):
            tris = wood(rng, (board_w - 0.06, h, 0.24), seg=(1, 2, 1))
            madeira += moved(tris, lambda p, x=x, h=h, z=z_face: add(P.rot_y(p, rng.uniform(-0.02, 0.02)),
                                                                        (x, h / 2, z)))
    for sx in (-1, 1):  # laterais do balcão
        tris = wood(rng, (0.24, body_h, counter_depth - 0.2), seg=(1, 2, 2))
        madeira += moved(tris, lambda p, sx=sx: add(p, (sx * (hw - 0.62), body_h / 2, 0.0)))
    top_w = width - 0.4
    for dz in (-0.25, 0.25):  # tampo em duas tábuas largas, desalinhadas
        depth = counter_depth / 2 + 0.25
        tris = wood(rng, (top_w - rng.uniform(0, 0.3), 0.32, depth), seg=(max(2, round(top_w / 2.5)), 1, 1))
        z = dz * counter_depth
        madeira += moved(tris, lambda p, z=z: add(P.rot_y(p, rng.uniform(-0.015, 0.015)),
                                                   (rng.uniform(-0.08, 0.08), counter_h - 0.16, z)))

    # prateleira dos fundos: duas tábuas entre os postes de trás, com mão-francesa
    for y in (3.4, 5.6):
        tris = wood(rng, (width - 1.4, 0.22, 1.0), seg=(max(2, round(width / 2.5)), 1, 1))
        madeira += moved(tris, lambda p, y=y: add(P.rot_y(p, rng.uniform(-0.01, 0.01)), (0.0, y, z_b - 0.65)))
        for sx in (-1, 1):
            x = sx * (hw - 1.0)
            madeira += beam(rng, (x, y - 1.0, z_b - 0.2), (x, y - 0.1, z_b - 0.95), 0.2)

    # toldo: lençol de pano com espessura, preso nas vigas (as bordas) e caído no meio; sobra para os lados e para a
    # frente, e na frente desce o babado recortado
    nu, nv = 14, 7
    x0, x1 = -hw - 0.6, hw + 0.6
    z_back, z_front = z_b + 0.35, z_f - 1.3
    y_back, y_front = h_b + 0.12, h_f - 0.25
    thick = 0.12

    def sheet(u: float, v: float) -> Vec:
        x = x0 + (x1 - x0) * u
        z = z_back + (z_front - z_back) * v
        y = y_back + (y_front - y_back) * v
        inner = max(0.0, min(1.0, (x + hw - 0.3) / (2 * (hw - 0.3))))
        sag = 0.45 * math.sin(math.pi * inner) * (0.5 + 0.5 * math.sin(math.pi * min(v / 0.82, 1.0)))
        droop = 0.5 * max(0.0, abs(x) - (hw - 0.3)) ** 1.3  # passa da viga lateral e cai
        wrinkle = 0.06 * math.sin(u * 37.0 + v * 5.0) + rng.uniform(-0.03, 0.03)
        return (x, y - sag - droop + wrinkle, z)

    grid = [[sheet(i / nu, j / nv) for i in range(nu + 1)] for j in range(nv + 1)]
    toldo: dict[str, list[Tri]] = {"ToldoA": [], "ToldoB": []}

    def stripe(i: int) -> str:
        return "ToldoA" if (i // 2) % 2 == 0 else "ToldoB"

    def slab(quads: list[tuple[Vec, Vec, Vec, Vec]], key: str, offset: Vec) -> None:
        """Cada quadrado vira as duas faces do pano (cima e baixo), separadas por `offset` (a espessura)."""
        for a, b, c, d in quads:
            lo = [sub(p, offset) for p in (a, b, c, d)]
            mid_hi = scale(add(add(a, b), add(c, d)), 0.25)
            mid_lo = sub(mid_hi, offset)
            toldo[key].append(oriented(a, b, c, mid_lo))
            toldo[key].append(oriented(a, c, d, mid_lo))
            toldo[key].append(oriented(lo[0], lo[1], lo[2], mid_hi))
            toldo[key].append(oriented(lo[0], lo[2], lo[3], mid_hi))

    for j in range(nv):
        for i in range(nu):
            slab([(grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i])], stripe(i), (0.0, thick, 0.0))

    # babado da frente: pendurado na borda da frente, recortado em ondas (uma onda por listra)
    front_edge = grid[nv]
    for i in range(nu):
        a, b = front_edge[i], front_edge[i + 1]
        depth_a = 1.05 - 0.45 * abs(math.cos(math.pi * i / 2))
        depth_b = 1.05 - 0.45 * abs(math.cos(math.pi * (i + 1) / 2))
        mid = scale(add(a, b), 0.5)
        mid_bottom = add(mid, (0.0, -1.15 + rng.uniform(-0.05, 0.05), -0.08))
        a_bottom = add(a, (0.0, -depth_a, -0.05))
        b_bottom = add(b, (0.0, -depth_b, -0.05))
        quads = [(a, mid, mid_bottom, a_bottom), (mid, b, b_bottom, mid_bottom)]
        slab(quads, stripe(i), (0.0, 0.0, -thick))

    return {"BancaMadeira": madeira, **toldo}


# ---------------------------------------------------------------- mercadorias


def caixote(seed: int) -> list[Tri]:
    """Caixote de ripas: corpo um pouco recuado e as ripas das quinas e das bordas por fora."""
    rng = random.Random(seed)
    s = 2.0
    tris = moved(wood(rng, (s - 0.2, s - 0.2, s - 0.2)), lambda p: add(p, (0, s / 2, 0)))
    for sx in (-1, 1):
        for sz in (-1, 1):
            tris += moved(wood(rng, (0.28, s, 0.28), seg=(1, 1, 1)), lambda p, sx=sx, sz=sz: add(
                p, (sx * (s / 2 - 0.14), s / 2, sz * (s / 2 - 0.14))))
    for y in (0.14, s - 0.14):
        for sx in (-1, 1):
            tris += moved(wood(rng, (0.2, 0.26, s - 0.3), seg=(1, 1, 1)), lambda p, sx=sx, y=y: add(
                p, (sx * (s / 2 - 0.08), y, 0)))
        for sz in (-1, 1):
            tris += moved(wood(rng, (s - 0.3, 0.26, 0.2), seg=(1, 1, 1)), lambda p, sz=sz, y=y: add(
                p, (0, y, sz * (s / 2 - 0.08))))
    return tris


BARREL_H = 3.0


def barrel_radius(h: float) -> float:
    return 1.0 + 0.16 * math.sin(math.pi * h / BARREL_H)


def barril(seed: int) -> tuple[list[Tri], list[Tri]]:
    """Barril bojudo de aduelas (raio desigual por aduela) com tampa afundada, e os três aros de metal."""
    rng = random.Random(seed)
    sides = 14
    prof = [(0.0, 0.05), (0.92, 0.0)]
    for k in range(7):
        h = BARREL_H * k / 6
        prof.append((barrel_radius(h), h))
    prof += [(0.92, BARREL_H - 0.02), (0.88, BARREL_H - 0.12), (0.0, BARREL_H - 0.12)]
    corpo = lathe(prof, sides, rng, jitter=0.025)
    aros: list[Tri] = []
    for h in (0.35, BARREL_H / 2, BARREL_H - 0.35):
        r = barrel_radius(h) + 0.04
        ring = [(r - 0.04, h - 0.13), (r + 0.03, h - 0.12), (r + 0.03, h + 0.12), (r - 0.04, h + 0.13)]
        # anel fechado: perfil quadrado que dá a volta (sem tampa nas pontas)
        rings = []
        for rr, hh in ring:
            rings.append([(rr * math.cos(math.tau * k / sides), hh, rr * math.sin(math.tau * k / sides))
                          for k in range(sides)])
        for i in range(4):
            lo, hi = rings[i], rings[(i + 1) % 4]
            for k in range(sides):
                k2 = (k + 1) % sides
                aros.append((lo[k], hi[k2], lo[k2]))
                aros.append((lo[k], hi[k], hi[k2]))
    if sum(dot(a, cross(b, c)) for a, b, c in aros) < 0:
        aros = [(a, c, b) for a, b, c in aros]
    return corpo, aros


def saco(seed: int) -> list[Tri]:
    """Saco cheio, irregular, com a boca amarrada e o pano sobrando em cima."""
    rng = random.Random(seed)
    prof = [(0.0, 0.0), (0.9, 0.02), (1.15, 0.5), (1.12, 1.0), (0.85, 1.5), (0.38, 1.85), (0.3, 2.0), (0.5, 2.25),
            (0.36, 2.45), (0.0, 2.4)]
    return lathe(prof, 11, rng, jitter=0.03, lumps=0.08, phase=rng.uniform(0, math.tau))


def cesto(seed: int) -> list[Tri]:
    """Cesto raso de vime (borda grossa), para os cogumelos."""
    rng = random.Random(seed)
    prof = [(0.0, 0.0), (0.9, 0.0), (1.3, 0.55), (1.45, 0.8), (1.35, 0.9), (1.2, 0.62), (0.0, 0.45)]
    return lathe(prof, 14, rng, jitter=0.03)


def cristais_venda(seed: int) -> tuple[list[Tri], list[Tri]]:
    """Punhado de cristais de seis faces (os pequenos que se vendem), em dois tons por direção da face: as que olham
    para cima/frente ficam claras (Neon no Roblox), as outras escuras (o contraste mostra as faces)."""
    rng = random.Random(seed)
    claro: list[Tri] = []
    escuro: list[Tri] = []
    light = norm((0.3, 1.0, -0.6))
    for _ in range(5):
        r = rng.uniform(0.22, 0.38)
        h = rng.uniform(0.9, 1.7)
        tip = r * 1.1
        base = (rng.uniform(-0.5, 0.5), 0.0, rng.uniform(-0.4, 0.4))
        tilt_x, tilt_z = rng.uniform(-0.35, 0.35), rng.uniform(-0.35, 0.35)
        ring_lo, ring_hi = [], []
        for k in range(6):
            ang = math.tau * k / 6 + rng.uniform(-0.1, 0.1)
            ring_lo.append((r * math.cos(ang), -0.1, r * math.sin(ang)))
            ring_hi.append((r * 1.05 * math.cos(ang), h - tip, r * 1.05 * math.sin(ang)))
        apex = (rng.uniform(-0.05, 0.05), h, rng.uniform(-0.05, 0.05))
        bottom = (0.0, -0.1, 0.0)

        def place(p, tilt_x=tilt_x, tilt_z=tilt_z, base=base):
            return add(rot_z(rot_x(p, tilt_x), tilt_z), base)

        faces: list[Tri] = []
        for k in range(6):
            k2 = (k + 1) % 6
            faces.append((ring_lo[k], ring_hi[k2], ring_lo[k2]))
            faces.append((ring_lo[k], ring_hi[k], ring_hi[k2]))
            faces.append((ring_hi[k], apex, ring_hi[k2]))
            faces.append((ring_lo[k], ring_lo[k2], bottom))
        for a, b, c in faces:
            tri = (place(a), place(b), place(c))
            n = norm(cross(sub(tri[1], tri[0]), sub(tri[2], tri[0])))
            # a orientação: para fora do eixo do cristal
            center = place((0.0, h / 2, 0.0))
            mid = scale(add(add(tri[0], tri[1]), tri[2]), 1 / 3)
            if dot(n, sub(mid, center)) < 0:
                tri = (tri[0], tri[2], tri[1])
                n = scale(n, -1)
            (claro if dot(n, light) > 0.15 else escuro).append(tri)
    return claro, escuro


def cogumelos(seed: int) -> tuple[list[Tri], list[Tri]]:
    """Touceira de cogumelos-lume (Musgo-Lume): hastes claras e chapéus que brilham (Neon verde no Roblox)."""
    rng = random.Random(seed)
    hastes: list[Tri] = []
    chapeus: list[Tri] = []
    for _ in range(6):
        h = rng.uniform(0.5, 1.2)
        r = rng.uniform(0.07, 0.12)
        cap = rng.uniform(0.25, 0.48)
        base = (rng.uniform(-0.6, 0.6), 0.0, rng.uniform(-0.6, 0.6))
        tilt_x, tilt_z = rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3)

        def place(tris, tilt_x=tilt_x, tilt_z=tilt_z, base=base):
            return moved(tris, lambda p: add(rot_z(rot_x(p, tilt_x), tilt_z), base))

        hastes += place(lathe([(0.0, 0.0), (r * 1.3, 0.0), (r, h * 0.5), (r * 0.9, h), (0.0, h)], 6, rng))
        chapeus += place(lathe([(0.0, h - 0.05), (cap, h - 0.02), (cap * 0.95, h + cap * 0.25),
                                (cap * 0.65, h + cap * 0.55), (0.0, h + cap * 0.68)], 8, rng, jitter=0.015))
    return hastes, chapeus


# ---------------------------------------------------------------- arquivo


def pieces() -> list[dict]:
    items: list[dict] = []

    def add_parts(parts: dict[str, list[Tri]], suffix: int) -> None:
        for name, tris in parts.items():
            items.append({"name": f"{name}_{suffix}", "tris": tris, "uv": "planar",
                          "open": name.startswith("Toldo")})

    # 1 e 2: bancas comuns (variações); 3: a Banca do Tanu, em volta do balcão da loja (10 x 4 x 4 no código)
    add_parts(banca(2001, 9.0, 1.8, 3.4, 2.6), 1)
    add_parts(banca(2002, 8.0, 1.8, 3.4, 2.4), 2)
    add_parts(banca(2003, 11.6, 4.2, 4.05, 2.6), 3)
    for i in range(1, 3):
        items.append({"name": f"Caixote_{i}", "tris": caixote(2100 + i), "uv": "planar"})
    corpo, aros = barril(2201)
    items.append({"name": "Barril_1", "tris": corpo, "uv": "planar"})
    items.append({"name": "AroBarril_1", "tris": aros, "uv": "planar"})
    for i in range(1, 3):
        items.append({"name": f"Saco_{i}", "tris": saco(2300 + i), "uv": "planar"})
    items.append({"name": "Cesto_1", "tris": cesto(2401), "uv": "planar"})
    claro, escuro = cristais_venda(2501)
    items.append({"name": "CristalClaro_1", "tris": claro, "uv": "planar", "open": True})
    items.append({"name": "CristalEscuro_1", "tris": escuro, "uv": "planar", "open": True})
    hastes, chapeus = cogumelos(2601)
    items.append({"name": "CogumeloHaste_1", "tris": hastes, "uv": "planar"})
    items.append({"name": "CogumeloChapeu_1", "tris": chapeus, "uv": "planar"})
    return items


if __name__ == "__main__":
    data = P.write_glb(pieces(), OUT)
    with open(OUT_JSON, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1, ensure_ascii=False)
    print(f"ok: {OUT}")
