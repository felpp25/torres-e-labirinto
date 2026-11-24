"""Gerador das formações de rocha do Lobby 1 (Fase 4 do BRIEFING-LOBBY1.md).

Malhas low-poly facetadas (sombreamento chapado), feitas por código porque o gerador de malhas do Studio não roda pelo
MCP. Saída: um único GLB com todas as variações (1 upload = 1 asset na conta), em
lobby1-claude-code/modelos/formacoes/FormacoesLobby1.glb.

Unidades: 1 unidade do glTF = 1 stud (o importador do Roblox traz GLB em 1 m = 1 stud). Eixo Y para cima.
Pivô de cada peça: Presas do Teto e Gotas da Fenda penduradas a partir de y = 0 (o topo encosta no teto); Agulhas e
Rochedos apoiados em y = 0.

Uso (na raiz do projeto):  python scripts/lobby1-formacoes.py
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
OUT = os.path.join(ROOT, "lobby1-claude-code", "modelos", "formacoes", "FormacoesLobby1.glb")

# Orçamento do briefing (triângulos por malha)
BUDGET = {"PresaDoTeto": 1000, "GotaDaFenda": 1500, "AgulhaDePedra": 1000, "RochedoCaido": 1500}


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
    """Triângulo com a frente (anti-horária) virada para fora, longe do ponto `inside`."""
    n = cross(sub(b, a), sub(c, a))
    centroid = scale(add(add(a, b), c), 1 / 3)
    if dot(n, sub(centroid, inside)) < 0:
        return (a, c, b)
    return (a, b, c)


def spike(
    rng: random.Random,
    radius: float,
    height: float,
    sides: int,
    rings: int,
    direction: int,
    base: Vec = (0.0, 0.0, 0.0),
    bend: float = 0.5,
    flare: float = 1.25,
    stop: float = 1.0,
    falloff: float = 0.85,
) -> tuple[list[Tri], list[Vec]]:
    """Cone facetado e torto (estalactite se direction = -1, estalagmite se +1).

    stop < 1 corta a ponta (fica um anel aberto, para encaixar o cristal das Gotas da Fenda). Devolve os triângulos e o
    último anel (para o cristal)."""
    angle0 = rng.uniform(0, math.tau)
    bend_dir = (math.cos(rng.uniform(0, math.tau)), 0.0, math.sin(rng.uniform(0, math.tau)))
    ring_pts: list[list[Vec]] = []
    centers: list[Vec] = []
    for k in range(rings + 1):
        t = (k / rings) * stop
        r = radius * (1 - t) ** falloff  # < 1: cone encorpado (com 1,35 as Presas viravam agulhas finas)
        if k == 0:
            r = radius * flare  # base mais larga, entra no teto/chão
        offset = scale(bend_dir, bend * height * 0.15 * t * t)
        y = direction * height * t + (rng.uniform(-0.04, 0.04) * height if 0 < k < rings else 0.0)
        center = add(base, (offset[0], y, offset[2]))
        centers.append(center)
        pts = []
        for i in range(sides):
            a = angle0 + math.tau * i / sides + rng.uniform(-0.12, 0.12)
            rr = r * rng.uniform(0.82, 1.15)
            pts.append(add(center, (math.cos(a) * rr, 0.0, math.sin(a) * rr)))
        ring_pts.append(pts)
    tris: list[Tri] = []
    # com ponta (stop = 1), o último anel tem raio 0: a última faixa vira um leque até a ponta (abaixo)
    bands = rings - 1 if stop >= 1.0 else rings
    for k in range(bands):
        lo, hi = ring_pts[k], ring_pts[k + 1]
        mid = scale(add(centers[k], centers[k + 1]), 0.5)
        for i in range(sides):
            j = (i + 1) % sides
            tris.append(oriented(lo[i], lo[j], hi[j], mid))
            tris.append(oriented(lo[i], hi[j], hi[i], mid))
    # tampa da base (encostada no teto/chão)
    cap_inside = add(centers[0], (0.0, direction * 1.0, 0.0))
    for i in range(1, sides - 1):
        tris.append(oriented(ring_pts[0][0], ring_pts[0][i], ring_pts[0][i + 1], cap_inside))
    last = ring_pts[-1]
    if stop >= 1.0:
        tip = centers[-1]
        prev = ring_pts[-2]
        mid = scale(add(centers[-2], tip), 0.5)
        for i in range(sides):
            j = (i + 1) % sides
            tris.append(oriented(prev[i], prev[j], tip, mid))
    else:
        # fecha o anel cortado (fica escondido dentro do cristal)
        for i in range(1, sides - 1):
            tris.append(oriented(last[0], last[i], last[i + 1], centers[-2]))
    return tris, last


def bipyramid(
    rng: random.Random, center: Vec, axis: Vec, radius: float, up: float, down: float, sides: int = 6
) -> list[Tri]:
    """Cristal: bipirâmide hexagonal ao longo de `axis` (pontas em center + axis*up e center - axis*down)."""
    axis = norm(axis)
    helper = (1.0, 0.0, 0.0) if abs(axis[0]) < 0.9 else (0.0, 0.0, 1.0)
    u = norm(cross(axis, helper))
    v = cross(axis, u)
    ring = []
    a0 = rng.uniform(0, math.tau)
    for i in range(sides):
        a = a0 + math.tau * i / sides
        rr = radius * rng.uniform(0.9, 1.1)
        ring.append(add(center, add(scale(u, math.cos(a) * rr), scale(v, math.sin(a) * rr))))
    top = add(center, scale(axis, up))
    bottom = sub(center, scale(axis, down))
    tris: list[Tri] = []
    for i in range(sides):
        j = (i + 1) % sides
        tris.append(oriented(ring[i], ring[j], top, center))
        tris.append(oriented(ring[i], ring[j], bottom, center))
    return tris


def icosphere(subdivisions: int) -> tuple[list[Vec], list[tuple[int, int, int]]]:
    t = (1 + math.sqrt(5)) / 2
    verts = [norm(v) for v in [
        (-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t),
        (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1),
    ]]
    faces = [
        (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
        (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
        (8, 6, 7), (9, 8, 1),
    ]
    # cada subdivisão multiplica as faces por 4 (0 = 20 faces, 1 = 80)
    cache: dict[tuple[int, int], int] = {}

    def midpoint(a: int, b: int) -> int:
        key = (min(a, b), max(a, b))
        if key not in cache:
            verts.append(norm(scale(add(verts[a], verts[b]), 0.5)))
            cache[key] = len(verts) - 1
        return cache[key]

    for _ in range(subdivisions):
        new_faces = []
        for a, b, c in faces:
            ab, bc, ca = midpoint(a, b), midpoint(b, c), midpoint(c, a)
            new_faces += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        faces = new_faces
    return verts, faces


def boulder(rng: random.Random, center: Vec, size: Vec) -> list[Tri]:
    """Pedra angulosa: icosaedro (20 faces grandes, estilo das referências) deformado, base reta (apoiada)."""
    verts, faces = icosphere(0)
    pts = []
    for v in verts:
        k = rng.uniform(0.75, 1.2)
        p = (v[0] * size[0] * k, v[1] * size[1] * k, v[2] * size[2] * k)
        p = (p[0], max(p[1], -size[1] * 0.35), p[2])  # corta embaixo: pedra assentada
        pts.append(add(center, p))
    return [oriented(pts[a], pts[b], pts[c], center) for a, b, c in faces]


# ---------------------------------------------------------------- variações (semente fixa por peça)


def presa(seed: int, radius: float, height: float, sides: int, rings: int, extra: bool = False) -> list[Tri]:
    rng = random.Random(seed)
    tris, _ = spike(rng, radius, height, sides, rings, -1, bend=rng.uniform(0.3, 0.9))
    if extra:
        off = (radius * 0.95, 0.0, radius * 0.4)
        more, _ = spike(rng, radius * 0.55, height * 0.5, sides - 1, max(3, rings - 2), -1, base=off)
        tris += more
    return tris


def gota(seed: int, radius: float, height: float, crystal: float) -> tuple[list[Tri], list[Tri]]:
    rng = random.Random(seed)
    rock, last = spike(rng, radius, height, 7, 5, -1, bend=rng.uniform(0.2, 0.6), stop=0.72)
    cx = sum(p[0] for p in last) / len(last)
    cy = sum(p[1] for p in last) / len(last)
    cz = sum(p[2] for p in last) / len(last)
    ring_r = max(math.dist((cx, cy, cz), p) for p in last)
    center = (cx, cy - crystal * 0.2, cz)
    gem = bipyramid(rng, center, (0.0, -1.0, 0.0), max(ring_r * 1.3, crystal * 0.32), crystal * 0.4, crystal)
    for _ in range(2):  # dois cristais menores de lado
        tilt = (rng.uniform(-0.6, 0.6), -1.0, rng.uniform(-0.6, 0.6))
        side = add(center, (rng.uniform(-1, 1) * ring_r, crystal * 0.1, rng.uniform(-1, 1) * ring_r))
        gem += bipyramid(rng, side, tilt, crystal * 0.18, crystal * 0.25, crystal * 0.6)
    return rock, gem


def agulha(seed: int, radius: float, height: float, sides: int, rings: int, cluster: int = 1) -> list[Tri]:
    rng = random.Random(seed)
    tris, _ = spike(rng, radius, height, sides, rings, 1, bend=rng.uniform(0.2, 0.7), flare=1.35)
    for n in range(cluster - 1):
        a = rng.uniform(0, math.tau)
        d = radius * rng.uniform(1.0, 1.5)
        k = rng.uniform(0.35, 0.65)
        base = (math.cos(a) * d, 0.0, math.sin(a) * d)
        more, _ = spike(rng, radius * k, height * k, max(5, sides - 1), max(3, rings - 1), 1, base=base, flare=1.3)
        tris += more
    return tris


def rochedo(seed: int, rocks: list[tuple[float, float, float, float, float]]) -> list[Tri]:
    """rocks: (x, z, largura, altura, profundidade) de cada pedra."""
    rng = random.Random(seed)
    tris: list[Tri] = []
    for x, z, w, h, d in rocks:
        # raio vertical ry: a base cortada fica em centro - 0,35·ry (0,3 stud abaixo do chão, assentada) e o topo em
        # ~centro + 1,15·ry, então a pedra sobe ~h acima do chão
        ry = (h + 0.3) / 1.5
        tris += boulder(rng, (x, ry * 0.35 - 0.3, z), (w / 2, ry, d / 2))
    return tris


def pieces() -> list[dict]:
    """Cada peça: nome, posição no arquivo (só para não se sobreporem ao importar) e malhas."""
    items: list[dict] = []
    presas = [
        presa(101, 3.2, 20, 7, 5),
        presa(102, 4.2, 28, 8, 6),
        presa(103, 2.6, 14, 6, 4),
        presa(104, 3.6, 24, 7, 5, extra=True),
    ]
    for i, tris in enumerate(presas, 1):
        items.append({"name": f"PresaDoTeto_{i}", "pos": (i * 16.0, 0.0, 0.0), "meshes": [("Rocha", tris)]})
    gotas = [gota(201, 2.8, 12, 5), gota(202, 3.4, 16, 6), gota(203, 2.4, 10, 4.5)]
    for i, (rock, gem) in enumerate(gotas, 1):
        items.append(
            {
                "name": f"GotaDaFenda_{i}",
                "pos": (i * 16.0, 0.0, 24.0),
                "meshes": [("Rocha", rock), ("Cristal", gem)],
            }
        )
    agulhas = [
        agulha(301, 2.4, 12, 7, 5),
        agulha(302, 3.4, 18, 8, 6),
        agulha(303, 2.0, 8, 6, 4, cluster=2),
        agulha(304, 2.8, 14, 7, 5, cluster=3),
    ]
    for i, tris in enumerate(agulhas, 1):
        items.append({"name": f"AgulhaDePedra_{i}", "pos": (i * 16.0, 0.0, 48.0), "meshes": [("Rocha", tris)]})
    rochedos = [
        rochedo(401, [(0, 0, 6, 4, 5), (3.5, 1.5, 4, 3, 4), (-2.5, 2.5, 3, 2.5, 3)]),
        rochedo(402, [(0, 0, 8, 5, 7), (4.5, -2, 5, 4, 5), (-4, 1.5, 5, 3.5, 4), (1, 4, 3.5, 2.5, 3.5)]),
        rochedo(403, [(0, 0, 5, 2.2, 4), (4, 1, 4, 2, 3.5), (-3.5, -1, 3.5, 1.8, 3), (1, -3.5, 3, 1.5, 3),
                      (-1.5, 3.5, 2.5, 1.4, 2.5)]),
    ]
    for i, tris in enumerate(rochedos, 1):
        items.append({"name": f"RochedoCaido_{i}", "pos": (i * 16.0, 0.0, 72.0), "meshes": [("Rocha", tris)]})
    return items


# ---------------------------------------------------------------- GLB


def srgb_to_linear(c: int) -> float:
    s = c / 255
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


def hex_linear(h: str) -> list[float]:
    return [srgb_to_linear(int(h[i : i + 2], 16)) for i in (0, 2, 4)] + [1.0]


def mesh_arrays(tris: list[Tri]) -> tuple[bytes, bytes, bytes, bytes, list[float], list[float], int]:
    """Vértices duplicados por face (sombreamento chapado) e UV planar por face (1 repetição a cada 8 studs)."""
    pos, nrm, uv, idx = bytearray(), bytearray(), bytearray(), bytearray()
    lo = [math.inf] * 3
    hi = [-math.inf] * 3
    n_vert = 0
    for a, b, c in tris:
        n = norm(cross(sub(b, a), sub(c, a)))
        ax = max(range(3), key=lambda i: abs(n[i]))
        u_axis, v_axis = [(1, 2), (0, 2), (0, 1)][ax]
        for p in (a, b, c):
            pos += struct.pack("<3f", *p)
            nrm += struct.pack("<3f", *n)
            uv += struct.pack("<2f", p[u_axis] / 8, p[v_axis] / 8)
            idx += struct.pack("<H", n_vert)
            n_vert += 1
            for i in range(3):
                lo[i] = min(lo[i], p[i])
                hi[i] = max(hi[i], p[i])
    return bytes(pos), bytes(nrm), bytes(uv), bytes(idx), lo, hi, n_vert


def write_glb(items: list[dict], path: str) -> list[str]:
    materials = [
        {"name": "Rocha", "pbrMetallicRoughness": {"baseColorFactor": hex_linear("4A4462"), "metallicFactor": 0.0,
                                                   "roughnessFactor": 0.95}},
        {"name": "Cristal", "pbrMetallicRoughness": {"baseColorFactor": hex_linear("8A3CFF"), "metallicFactor": 0.0,
                                                     "roughnessFactor": 0.2},
         "emissiveFactor": hex_linear("8A3CFF")[:3]},
    ]
    mat_index = {"Rocha": 0, "Cristal": 1}
    gltf: dict = {"asset": {"version": "2.0", "generator": "lobby1-formacoes.py"}, "scene": 0, "scenes": [{"nodes": []}],
                  "nodes": [], "meshes": [], "materials": materials, "accessors": [], "bufferViews": [],
                  "buffers": []}
    blob = bytearray()
    report = []

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
        child_nodes = []
        for part_name, tris in item["meshes"]:
            pos, nrm, uv, idx, lo, hi, count = mesh_arrays(tris)
            prim = {
                "attributes": {
                    "POSITION": accessor(view(pos, 34962), 5126, count, "VEC3", lo, hi),
                    "NORMAL": accessor(view(nrm, 34962), 5126, count, "VEC3"),
                    "TEXCOORD_0": accessor(view(uv, 34962), 5126, count, "VEC2"),
                },
                "indices": accessor(view(idx, 34963), 5123, count, "SCALAR"),
                "material": mat_index[part_name],
            }
            name = item["name"] if len(item["meshes"]) == 1 else f"{item['name']}_{part_name}"
            gltf["meshes"].append({"name": name, "primitives": [prim]})
            gltf["nodes"].append({"name": name, "mesh": len(gltf["meshes"]) - 1})
            child_nodes.append(len(gltf["nodes"]) - 1)
            kind = item["name"].split("_")[0]
            size = [round(hi[i] - lo[i], 1) for i in range(3)]
            assert len(tris) <= BUDGET[kind], f"{name}: {len(tris)} triângulos passa do orçamento {BUDGET[kind]}"
            # volume com sinal > 0 = faces viradas para fora (malha do avesso ficaria invisível no Roblox)
            volume = sum(dot(a, cross(b, c)) for a, b, c in tris) / 6
            assert volume > 0, f"{name}: faces viradas para dentro (volume {volume:.1f})"
            report.append(
                f"{name}: {len(tris)} triângulos, tamanho {size} (x, y, z), y de {lo[1]:.1f} a {hi[1]:.1f}, "
                f"volume {volume:.0f}"
            )
        if len(child_nodes) == 1:
            gltf["nodes"][child_nodes[0]]["translation"] = list(item["pos"])
            gltf["scenes"][0]["nodes"].append(child_nodes[0])
        else:
            gltf["nodes"].append({"name": item["name"], "translation": list(item["pos"]), "children": child_nodes})
            gltf["scenes"][0]["nodes"].append(len(gltf["nodes"]) - 1)

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
    return report


if __name__ == "__main__":
    lines = write_glb(pieces(), OUT)
    print("\n".join(lines))
    print(f"-> {OUT} ({os.path.getsize(OUT)} bytes)")
