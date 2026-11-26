"""Cristais do Lobby 1: o Coração do Abismo (cristal central, núcleo que brilha, drusa em volta) e o pedestal dele.

Mesmo caminho das peças de pedra (scripts/lobby1-pedras.py): malha por código → GLB → upload (asset na conta do
Filipe) → montagem pelo scripts/lobby1-cristais.luau. Reaproveita o bloco lascado, o GLB e as verificações do
lobby1-pedras.py.

Referências 04 e 05: um cristal roxo alto e facetado no meio, cercado de cristais menores inclinados para fora, sobre
uma base redonda de pedra.

Cristal estilizado em TRÊS TONS: cada face vai para a malha clara, média ou escura conforme a direção para onde aponta
(como gema pintada à mão). No Roblox, Neon apaga o sombreamento (a primeira versão, toda Neon, saiu um borrão rosa sem
faces) e Glass à noite fica quase preto; com os tons separados as faces aparecem mesmo com o brilho.

Coordenadas locais: centro do pedestal na origem, chão do pedestal em y = 0 (o .luau põe no topo da Plataforma do
Altar, y = 8). 1 unidade = 1 stud, Y para cima.

Uso (na raiz do projeto):  python scripts/lobby1-cristais.py
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
add, sub, scale, norm, cross, oriented = P.add, P.sub, P.scale, P.norm, P.cross, P.oriented

OUT_DIR = os.path.join(P.ROOT, "lobby1-claude-code", "modelos", "cristais")
OUT = os.path.join(OUT_DIR, "CristaisLobby1.glb")
OUT_JSON = os.path.join(OUT_DIR, "CristaisLobby1.json")

P.BUDGET.update({
    "CoracaoClaro": 3000, "CoracaoMedio": 3000, "CoracaoEscuro": 3000, "PedestalDoCoracao": 3000,
    "AnelFita": 1000, "AnelRunas": 4000,
})


PEDESTAL_TOP = 3.0  # altura do pedestal (o cristal nasce aqui, um pouco enterrado)


def frame(axis: Vec) -> tuple[Vec, Vec, Vec]:
    axis = norm(axis)
    helper = (1.0, 0.0, 0.0) if abs(axis[0]) < 0.9 else (0.0, 0.0, 1.0)
    u = norm(cross(axis, helper))
    v = cross(axis, u)
    return axis, u, v


def crystal(
    rng: random.Random,
    base: Vec,
    axis: Vec,
    radius: float,
    height: float,
    sides: int = 6,
    tip: float = 0.26,
    taper: float = 0.9,
) -> list[Tri]:
    """Prisma de quartzo: corpo de `sides` faces (levemente torto e afinando), ponta facetada assimétrica.

    O anel do começo da ponta tem cada vértice numa altura diferente: as faces da ponta saem desiguais, como num
    cristal de verdade (com a mesma altura, a ponta vira um lápis apontado)."""
    w, u, v = frame(axis)
    a0 = rng.uniform(0, math.tau)
    radii = [radius * rng.uniform(0.8, 1.18) for _ in range(sides)]  # faces de larguras diferentes
    angles = [a0 + math.tau * i / sides + rng.uniform(-0.12, 0.12) for i in range(sides)]

    def ring(t: float, k: float, jitter_h: float = 0.0) -> list[Vec]:
        pts = []
        for i in range(sides):
            r = radii[i] * k
            h = height * t + (rng.uniform(-jitter_h, jitter_h) if jitter_h else 0.0)
            p = add(base, scale(w, h))
            p = add(p, add(scale(u, math.cos(angles[i]) * r), scale(v, math.sin(angles[i]) * r)))
            pts.append(p)
        return pts

    body_end = 1 - tip
    rings = [ring(0.0, 0.92), ring(body_end * 0.5, 1.0 * (1 + (taper - 1) * 0.5)),
             ring(body_end, taper, jitter_h=height * tip * 0.22)]
    apex_off = add(scale(u, rng.uniform(-0.15, 0.15) * radius), scale(v, rng.uniform(-0.15, 0.15) * radius))
    apex = add(add(base, scale(w, height)), apex_off)
    center = add(base, scale(w, height * 0.45))
    tris: list[Tri] = []
    for k in range(len(rings) - 1):
        lo, hi = rings[k], rings[k + 1]
        for i in range(sides):
            j = (i + 1) % sides
            tris.append(oriented(lo[i], lo[j], hi[j], center))
            tris.append(oriented(lo[i], hi[j], hi[i], center))
    top = rings[-1]
    for i in range(sides):
        j = (i + 1) % sides
        tris.append(oriented(top[i], top[j], apex, center))
    bottom = rings[0]
    for i in range(1, sides - 1):
        tris.append(oriented(bottom[0], bottom[i], bottom[i + 1], center))
    return tris


def tilted(rng: random.Random, angle: float, lean: float) -> Vec:
    """Eixo inclinado `lean` radianos para fora, na direção `angle`."""
    return (math.sin(lean) * math.cos(angle), math.cos(lean), math.sin(lean) * math.sin(angle))


def coracao() -> list[Tri]:
    rng = random.Random(3101)
    base = (0.0, PEDESTAL_TOP - 1.2, 0.0)
    tris = crystal(rng, base, (0.03, 1.0, -0.02), 6.4, 46.0, sides=6, tip=0.3, taper=0.88)
    # três médios encostados no grande e uma coroa de menores inclinados para fora
    for n in range(3):
        a = n * math.tau / 3 + rng.uniform(-0.3, 0.3)
        d = rng.uniform(4.0, 5.5)
        b = (math.cos(a) * d, PEDESTAL_TOP - 1.0, math.sin(a) * d)
        tris += crystal(rng, b, tilted(rng, a, rng.uniform(0.18, 0.3)), rng.uniform(2.6, 3.4),
                        rng.uniform(18, 26), sides=6, tip=0.3)
    count = 11
    for n in range(count):
        a = n * math.tau / count + rng.uniform(-0.2, 0.2)
        d = rng.uniform(6.0, 8.5)
        b = (math.cos(a) * d, PEDESTAL_TOP - 0.8, math.sin(a) * d)
        tris += crystal(rng, b, tilted(rng, a, rng.uniform(0.4, 0.85)), rng.uniform(1.2, 2.3),
                        rng.uniform(6, 14), sides=rng.choice([5, 6, 6]), tip=0.32)
    return tris


def tones(tris: list[Tri]) -> tuple[list[Tri], list[Tri], list[Tri]]:
    """Separa as faces em clara / média / escura pela direção horizontal da normal, em faixas de 60° que se alternam.

    Cada prisma tem ~6 faces a ~60° uma da outra, então faces vizinhas caem em tons diferentes, olhando de qualquer
    lado. (A primeira versão usava uma luz fixa: de lado, quase tudo virava "clara" e o cristal virava um borrão.)
    Faces bem viradas para cima (a ponta) ficam claras."""
    light: list[Tri] = []
    mid: list[Tri] = []
    dark: list[Tri] = []
    for t in tris:
        n = norm(cross(sub(t[1], t[0]), sub(t[2], t[0])))
        if n[1] > 0.6:
            light.append(t)
            continue
        band = int((math.atan2(n[2], n[0]) + math.pi + 0.35) / (math.tau / 6)) % 3
        (light, mid, dark)[band].append(t)
    return light, mid, dark


def pedestal() -> list[Tri]:
    """Base redonda em dois degraus de pedra lascada (20 lados), do chão (y = 0) até PEDESTAL_TOP."""
    rng = random.Random(3201)
    sides = 20
    tris: list[Tri] = []
    tiers = [(0.0, 1.6, 10.5), (1.6, PEDESTAL_TOP, 8.6)]
    for y0, y1, r in tiers:
        hs = [y0, y0 + 0.25, y1 - 0.3, y1]
        rings = []
        a0 = rng.uniform(0, math.tau)
        for idx, y in enumerate(hs):
            edge = idx in (0, len(hs) - 1)
            pts = []
            for s in range(sides):
                a = a0 + math.tau * s / sides + rng.uniform(-0.04, 0.04)
                rr = r * rng.uniform(0.97, 1.03) * (rng.uniform(0.92, 0.96) if idx == len(hs) - 1 else 1.0)
                yy = y if edge else y + rng.uniform(-0.08, 0.08)
                pts.append((math.cos(a) * rr, yy, math.sin(a) * rr))
            rings.append(pts)
        for _ in range(4):  # lascas na borda de cima
            s = rng.randrange(sides)
            for ds, f in ((0, 1.0), (1, 0.5), (-1, 0.5)):
                i = (s + ds) % sides
                for ri, g in ((3, 1.0), (2, 0.5)):
                    p = rings[ri][i]
                    radial = norm((p[0], 0.0, p[2]))
                    rings[ri][i] = sub(p, add(scale(radial, 0.6 * f * g), (0.0, 0.25 * f * g, 0.0)))
        mid = (0.0, (y0 + y1) / 2, 0.0)
        for k in range(len(rings) - 1):
            lo, hi = rings[k], rings[k + 1]
            for s in range(sides):
                t = (s + 1) % sides
                tris.append(oriented(lo[s], lo[t], hi[t], mid))
                tris.append(oriented(lo[s], hi[t], hi[s], mid))
        for ring, inside in ((rings[0], (0.0, y0 + 0.5, 0.0)), (rings[-1], (0.0, y1 - 0.5, 0.0))):
            c = (0.0, ring[0][1], 0.0)
            for s in range(sides):
                t = (s + 1) % sides
                tris.append(oriented(c, ring[s], ring[t], inside))
    return tris


# ---------------------------------------------------------------- Anéis Rúnicos

RING_HEIGHT = 2.2  # largura da fita
RING_THICK = 0.14


def on_ring(radius: float, angle: float, y: float, dr: float = 0.0) -> Vec:
    r = radius + dr
    return (math.cos(angle) * r, y, math.sin(angle) * r)


def fita(radius: float, segments: int = 48) -> list[Tri]:
    """Fita fina e fechada em volta do eixo Y (sólida: aparece por dentro e por fora)."""
    tris: list[Tri] = []
    h = RING_HEIGHT / 2
    t = RING_THICK / 2
    for i in range(segments):
        a0, a1 = math.tau * i / segments, math.tau * (i + 1) / segments
        am = (a0 + a1) / 2
        quads = [
            ((a0, -h, t), (a1, -h, t), (a1, h, t), (a0, h, t), +1),  # fora
            ((a0, -h, -t), (a1, -h, -t), (a1, h, -t), (a0, h, -t), -1),  # dentro
            ((a0, h, -t), (a1, h, -t), (a1, h, t), (a0, h, t), 0),  # borda de cima
            ((a0, -h, -t), (a1, -h, -t), (a1, -h, t), (a0, -h, t), 0),  # borda de baixo
        ]
        for q in quads:
            pts = [on_ring(radius, a, y, dr) for a, y, dr in q[:4]]
            # ponto "de dentro" do sólido da fita nesse trecho
            inside = on_ring(radius, am, 0.0, 0.0)
            tris.append(oriented(pts[0], pts[1], pts[2], inside))
            tris.append(oriented(pts[0], pts[2], pts[3], inside))
    return tris


def stroke(radius: float, a0: float, y0: float, a1: float, y1: float, width: float = 0.2) -> list[Tri]:
    """Traço de runa: barrinha que atravessa a fita (aparece dos dois lados), do ponto (a0, y0) ao (a1, y1)."""
    depth = RING_THICK + 0.12
    p0, p1 = on_ring(radius, a0, y0), on_ring(radius, a1, y1)
    am = (a0 + a1) / 2
    radial = (math.cos(am), 0.0, math.sin(am))
    along = norm(sub(p1, p0))
    side = norm(cross(radial, along))
    corners = []
    for p in (p0, p1):
        for sw in (-1, 1):
            for sd in (-1, 1):
                corners.append(add(add(p, scale(side, sw * width / 2)), scale(radial, sd * depth / 2)))
    center = scale(add(p0, p1), 0.5)
    faces = [(0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)]
    tris: list[Tri] = []
    for a, b, c, d in faces:
        tris.append(oriented(corners[a], corners[b], corners[c], center))
        tris.append(oriented(corners[a], corners[c], corners[d], center))
    return tris


def runas(seed: int, radius: float) -> list[Tri]:
    """Runas de Áuren em volta da fita: cada uma com uma haste e 2 ou 3 traços entre pontos de uma grade 3 × 4."""
    rng = random.Random(seed)
    cell_w, cell_h = 1.1, RING_HEIGHT * 0.62
    count = int(math.tau * radius / (cell_w * 1.9))
    tris: list[Tri] = []
    for n in range(count):
        ac = math.tau * n / count
        def pt(col: int, row: int) -> tuple[float, float]:
            x = (col / 2 - 0.5) * cell_w
            y = (row / 3 - 0.5) * cell_h
            return ac + x / radius, y
        stem = rng.randint(0, 2)
        segs = [((stem, 0), (stem, 3))]
        for _ in range(rng.randint(2, 3)):
            a = (rng.randint(0, 2), rng.randint(0, 3))
            b = (rng.randint(0, 2), rng.randint(0, 3))
            if a != b:
                segs.append((a, b))
        for a, b in segs:
            (a0, y0), (a1, y1) = pt(*a), pt(*b)
            tris += stroke(radius, a0, y0, a1, y1)
    return tris


def pieces() -> list[dict]:
    light, mid, dark = tones(coracao())
    return [
        {"name": "CoracaoClaro_1", "tris": light, "uv": "planar", "open": True},
        {"name": "CoracaoMedio_1", "tris": mid, "uv": "planar", "open": True},
        {"name": "CoracaoEscuro_1", "tris": dark, "uv": "planar", "open": True},
        {"name": "PedestalDoCoracao_1", "tris": pedestal(), "uv": "cyl"},
        {"name": "AnelFita_1", "tris": fita(15.0), "uv": "cyl"},
        {"name": "AnelRunas_1", "tris": runas(3301, 15.0), "uv": "planar"},
        {"name": "AnelFita_2", "tris": fita(12.0), "uv": "cyl"},
        {"name": "AnelRunas_2", "tris": runas(3302, 12.0), "uv": "planar"},
    ]


if __name__ == "__main__":
    data = P.write_glb(pieces(), OUT)
    with open(OUT_JSON, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, indent=1, ensure_ascii=False)
    print(f"ok: {OUT}")
