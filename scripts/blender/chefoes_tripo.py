"""Chefões do Tripo (lobby1-claude-code/Tripo/Bosses/), preparados no Blender (MCP).

- Golem de Obsidiana e Magma (~10 mil triângulos, textura de cor 1024): o Tripo gerou partes erradas, que saem aqui
  por pedaço solto da malha (depois de soldar as costuras da UV):
  - um golem PEQUENO, cópia do grande, flutuando atrás do ombro esquerdo (o maior pedaço depois do corpo);
  - o pedestal redondo de pedra e os pedregulhos em cima dele (pedaços que não passam de 0,08 de altura);
  - cartões planos com textura (a placa de lava com a haste no peito, lascas nas mãos): pedaços pequenos com todas as
    faces para o mesmo lado;
  - o monte de cacos e cristais voando ao lado da mão direita: pedaços que não encostam no corpo (> 0,012).
  Os cristais presos no corpo e o brilho de lava da mão direita ficam. Depois, os pés descem até o chão (z = 0).
- Lindwyrm púrpura (~4.300 triângulos): sem erros (a língua e a fitinha perto da cauda são do desenho).

Unidades do Tripo: 1 de altura (a escala em studs vai no Roblox ou no export). Frente = -Y do Blender.

Uso no Blender (pelo MCP):
    import sys, importlib
    sys.path.insert(0, r"<projeto>\\scripts\\blender")
    import lobby1_blender as LB, chefoes_tripo as C
    importlib.reload(LB); importlib.reload(C)
    golem = C.importar("Golem de Obsidiana e Magma.glb", "Golem", "GolemTripo")
    print(C.limpar_golem(golem))
"""

from __future__ import annotations

import collections
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector, noise
from mathutils.bvhtree import BVHTree

import lobby1_blender as LB

BOSSES_DIR = os.path.join(LB.ROOT, "lobby1-claude-code", "Tripo", "Bosses")


def importar(arquivo: str, colecao: str, nome: str):
    col = LB.collection(colecao)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(BOSSES_DIR, arquivo))
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    assert len(meshes) == 1, f"esperava 1 malha em {arquivo}, veio {len(meshes)}"
    for o in new:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)
    meshes[0].name = nome
    return meshes[0]


def _pedacos(bm) -> list:
    """Pedaços soltos (faces ligadas por vértice), do maior para o menor."""
    bm.faces.ensure_lookup_table()
    seen: set[int] = set()
    comps = []
    for f in bm.faces:
        if f.index in seen:
            continue
        stack = [f]
        seen.add(f.index)
        comp = []
        while stack:
            g = stack.pop()
            comp.append(g)
            for v in g.verts:
                for h in v.link_faces:
                    if h.index not in seen:
                        seen.add(h.index)
                        stack.append(h)
        comps.append(comp)
    comps.sort(key=len, reverse=True)
    return comps


def limpar_golem(ob) -> dict:
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.0015)  # solda as costuras da UV
    comps = _pedacos(bm)
    body = comps[0]
    bverts = list({v for f in body for v in f.verts})
    vmap = {v: i for i, v in enumerate(bverts)}
    tree = BVHTree.FromPolygons([v.co.copy() for v in bverts], [[vmap[v] for v in f.verts] for f in body])

    motivos: collections.Counter = collections.Counter()
    dead = []
    for c in comps[1:]:
        pts = [v.co for f in c for v in f.verts]
        lo_z = min(p.z for p in pts)
        hi_z = max(p.z for p in pts)
        area = sum(f.calc_area() for f in c)
        normal = sum((f.normal * f.calc_area() for f in c), Vector())
        planar = normal.length / max(area, 1e-9)
        motivo = None
        if len(c) > 1000:
            motivo = "golem pequeno"
        elif lo_z < 0.03 and hi_z < 0.08:
            motivo = "pedestal"
        elif planar > 0.97 and len(c) <= 30:
            motivo = "cartão plano"
        elif min(tree.find_nearest(v.co)[3] for f in c for v in f.verts) > 0.012:
            motivo = "voando"
        if motivo:
            motivos[motivo] += len(c)
            dead.extend(c)
    bmesh.ops.delete(bm, geom=dead, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(me)
    bm.free()
    zmin = min(v.co.z for v in me.vertices)
    me.transform(Matrix.Translation((0, 0, -zmin)))  # sem o pedestal, os pés descem até o chão
    return {"tirado": dict(motivos), "triangulos": LB.triangles(ob)}


# Altura no jogo (studs) e giro em volta do eixo vertical. O corpo de colisão do chefão continua o do código
# (Balance/Bosses: Golem 8 x 10 x 8, Kokuryū 7 x 11 x 7); o modelo é só a aparência, um pouco maior que ele.
# O Kokuryū (dragão-serpente enrolado em pé, de lado, cabeça para -X) gira 45°: a cabeça olha para a frente e o corpo
# enrolado continua aparecendo (de frente, de lado, ele ficaria fino).
# O Golem do Tripo vinha girado 45° (corpo na diagonal, visto de cima): gira -45° para ficar de frente.
CHEFOES = {
    "Golem": {"arquivo": "Golem de Obsidiana e Magma.glb", "nome": "GolemTripo", "altura": 11.0, "giro": -45.0},
    "Kokuryu": {"arquivo": "Lindwyrm púrpura.glb", "nome": "KokuryuTripo", "altura": 14.0, "giro": 45.0},
}
OUT_DIR = os.path.join(LB.ROOT, "lobby1-claude-code", "modelos", "chefoes")


def preparar(chave: str):
    """Importa, limpa (Golem), põe na escala do jogo e gira; devolve o objeto pronto para exportar."""
    cfg = CHEFOES[chave]
    ob = importar(cfg["arquivo"], chave, cfg["nome"])
    if chave == "Golem":
        limpar_golem(ob)
    me = ob.data
    zmin = min(v.co.z for v in me.vertices)
    zmax = max(v.co.z for v in me.vertices)
    k = cfg["altura"] / (zmax - zmin)
    me.transform(Matrix.Rotation(math.radians(cfg["giro"]), 4, "Z") @ Matrix.Scale(k, 4))
    return ob


def exportar(chave: str, ob) -> dict:
    return LB.export_glb([ob], os.path.join(OUT_DIR, f"{chave}.glb"))


# ------------------------------------------------------------------ Golem em pedaços (animado por código)
#
# Decisão do designer (26/11/2026): o Golem não tem esqueleto; em vez de rig, ele vira PEDAÇOS DE PEDRA presos por
# juntas de lava, e o jogo anima cada pedaço por código (client/Controllers/BossVisualController). As juntas abaixo
# são do Golem já na escala do jogo e de frente (o modelo do Tripo vinha girado 45°: GIRO_GOLEM). Coordenadas do
# Blender (frente = -Y); no Roblox (frente = -z) uma junta (x, y, z) fica em (-x, z, y) no espaço do modelo.

GIRO_GOLEM = -45.0
JUNTAS = {
    "Pelvis": (-0.15, 0.0, 4.2),
    "Pescoco": (-0.2, 0.0, 9.2),
    "Topo": (-0.2, 0.0, 11.0),
    "OmbroD": (-2.7, 0.1, 8.1),
    "CotoveloD": (-3.9, 0.1, 6.3),
    "MaoD": (-4.4, -0.2, 4.6),
    "OmbroE": (2.2, 0.1, 8.0),
    "CotoveloE": (3.0, 0.2, 6.6),
    "MaoE": (3.0, -1.2, 6.0),
    "QuadrilD": (-1.9, 0.0, 3.8),
    "JoelhoD": (-2.0, 0.0, 2.0),
    "PeD": (-2.6, 0.0, 0.5),
    "QuadrilE": (1.6, 0.0, 3.8),
    "JoelhoE": (1.8, 0.0, 2.0),
    "PeE": (2.4, 0.0, 0.5),
}
# pedaço: (junta de cima, junta de baixo, "raio" do pedaço: as faces vão para o osso de menor distância - raio)
OSSOS = {
    "Tronco": ("Pelvis", "Pescoco", 2.0),
    "Cabeca": ("Pescoco", "Topo", 0.9),
    "BracoD": ("OmbroD", "CotoveloD", 0.9),
    "AntebracoD": ("CotoveloD", "MaoD", 1.1),
    "BracoE": ("OmbroE", "CotoveloE", 0.9),
    "AntebracoE": ("CotoveloE", "MaoE", 1.0),
    "CoxaD": ("QuadrilD", "JoelhoD", 0.9),
    "CanelaD": ("JoelhoD", "PeD", 1.1),
    "CoxaE": ("QuadrilE", "JoelhoE", 0.9),
    "CanelaE": ("JoelhoE", "PeE", 1.1),
}


def _dist_segmento(p: Vector, a: Vector, b: Vector) -> float:
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / max(ab.length_squared, 1e-9)))
    return (p - (a + ab * t)).length


def _osso(p: Vector) -> str:
    # acima do pescoço, perto do meio: cabeça (pela distância, o tronco largo engolia a cabeça inteira)
    pescoco = JUNTAS["Pescoco"]
    if p.z > pescoco[2] + 0.1 and abs(p.x - pescoco[0]) < 1.7:
        return "Cabeca"
    best, best_d = "Tronco", math.inf
    for nome, (ja, jb, raio) in OSSOS.items():
        d = _dist_segmento(p, Vector(JUNTAS[ja]), Vector(JUNTAS[jb])) - raio
        if d < best_d:
            best, best_d = nome, d
    return best


def segmentar_golem(ob, col) -> list:
    """Separa a malha do Golem (já limpa, na escala e de frente) em um objeto por pedaço. Cada face do corpo vai para o
    osso mais perto; os pedaços soltos pequenos (cristais) vão inteiros para o osso do centro deles."""
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    comps = _pedacos(bm)
    dono: dict[int, str] = {}
    for i, c in enumerate(comps):
        if i == 0:
            for f in c:
                dono[f.index] = _osso(f.calc_center_median())
        else:
            centro = sum((f.calc_center_median() for f in c), Vector()) / len(c)
            nome = _osso(centro)
            for f in c:
                dono[f.index] = nome
    bm.free()

    objetos = []
    for nome in OSSOS:
        novo = ob.copy()
        novo.data = me.copy()
        novo.name = f"Golem{nome}"
        col.objects.link(novo)
        bm = bmesh.new()
        bm.from_mesh(novo.data)
        bm.faces.ensure_lookup_table()
        fora = [f for f in bm.faces if dono.get(f.index) != nome]
        bmesh.ops.delete(bm, geom=fora, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(novo.data)
        bm.free()
        objetos.append(novo)
    return objetos


# Bolas de lava nas juntas: escondem o corte entre os pedaços quando eles giram (o magma segurando as pedras). Cada uma
# fica presa ao pedaço de cima (o ombro no tronco, o cotovelo no braço...): (junta, raio, pedaço dono).
# (com o dobro destes raios elas saltavam do corpo como bolas: a lava só deve aparecer nas frestas)
LAVA = {
    "Pescoco": (0.55, "Tronco"),
    "OmbroD": (0.65, "Tronco"),
    "OmbroE": (0.6, "Tronco"),
    "CotoveloD": (0.55, "BracoD"),
    "CotoveloE": (0.5, "BracoE"),
    "QuadrilD": (0.6, "CoxaD"),
    "QuadrilE": (0.6, "CoxaE"),
    "JoelhoD": (0.55, "CoxaD"),
    "JoelhoE": (0.55, "CoxaE"),
}


def bolas_de_lava(col) -> list:
    """Uma bola irregular (icosfera com ruído) por junta, para o Neon de lava no Roblox."""
    objetos = []
    mat = LB.material("Lava", (240, 110, 30), 4.0)
    for i, (junta, (raio, _dono)) in enumerate(LAVA.items()):
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=2, radius=raio)
        for v in bm.verts:
            v.co *= 1 + 0.18 * noise.noise(v.co * 1.7 + Vector((i * 3.1, 0.0, 0.0)))
        me = bpy.data.meshes.new(f"GolemLava{junta}")
        bm.to_mesh(me)
        bm.free()
        for poly in me.polygons:
            poly.use_smooth = False
        me.materials.append(mat)
        ob = bpy.data.objects.new(f"GolemLava{junta}", me)
        ob.location = JUNTAS[junta]
        col.objects.link(ob)
        ob.data.transform(Matrix.Translation(ob.location))  # posição na própria malha (o GLB não leva o nó)
        ob.location = (0, 0, 0)
        objetos.append(ob)
    return objetos


# ------------------------------------------------------------------ Golem com esqueleto (Tripo, rig Mixamo)
#
# O designer gerou um Golem novo no Tripo já com esqueleto (rig humanoide, predefinição Mixamo: 65 ossos com os
# dedos), em pose A, de frente e sem pedestal ("Golem rig.glb"). Com esqueleto o corpo dobra sem cortes: o jogo gira
# os OSSOS por código (client/Controllers/BossVisualController), com as mesmas poses dos pedaços.

GOLEM_RIG = "Golem rig.glb"
GOLEM_RIG_ALTURA = 11.0
GOLEM_RIG_TRIANGULOS = 9800  # peça principal: até 10 mil (o Tripo entregou ~10.500)


def preparar_golem_rig():
    """Importa o Golem com esqueleto, põe na altura do jogo (escala aplicada no esqueleto e na malha), reduz os
    triângulos (Decimate antes do Armature: os grupos de vértices continuam) e devolve (malha, esqueleto)."""
    col = LB.collection("Golem Rig")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(BOSSES_DIR, GOLEM_RIG))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        for c in list(o.users_collection):
            c.objects.unlink(o)
        col.objects.link(o)
    arm = next(o for o in new if o.type == "ARMATURE")
    # a malha presa ao esqueleto (o importador de glTF também cria uma "Esfera icosaédrica" para desenhar os ossos)
    mesh = next(o for o in new if o.type == "MESH" and o.parent == arm and len(o.vertex_groups) > 0)
    for o in new:
        if o.type == "MESH" and o is not mesh:
            o.hide_set(True)
    arm.name = "GolemRigEsqueleto"
    mesh.name = "GolemRig"

    zs = [(mesh.matrix_world @ v.co).z for v in mesh.data.vertices]
    k = GOLEM_RIG_ALTURA / (max(zs) - min(zs))
    arm.scale = (k, k, k)
    bpy.context.view_layer.update()
    bpy.ops.object.select_all(action="DESELECT")
    for o in (arm, mesh):
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)

    tris = LB.triangles(mesh)
    if tris > GOLEM_RIG_TRIANGULOS:
        mod = mesh.modifiers.new("Reducao", "DECIMATE")
        mod.ratio = GOLEM_RIG_TRIANGULOS / tris
        mesh.modifiers.move(mesh.modifiers.find(mod.name), 0)  # antes do Armature
        bpy.context.view_layer.objects.active = mesh
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return mesh, arm


def exportar_golem_rig(mesh, arm) -> dict:
    return LB.export_glb([mesh, arm], os.path.join(OUT_DIR, "GolemRig.glb"))
