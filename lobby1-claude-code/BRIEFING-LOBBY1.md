# Briefing — construir o Lobby 1 (Abismo de Áuren)

Objetivo: montar no Roblox Studio o Lobby 1 do Ascending Labyrinths, com o visual das imagens **ALVO** em `referencias/` e o layout de `referencias/08-mapa-layout.png`. O design completo está resumido em `docs/lobby1-resumo.md`.

Trabalhe **uma fase por vez**. No fim de cada fase: captura de tela, comparação com as referências e OK do Filipe.

---

## Fase 0 — Ferramentas e conexões MCP

Confira o que já existe antes de instalar qualquer coisa (`claude mcp list`, versões instaladas). Peça confirmação antes de instalar.

### 0.1 Roblox Studio (obrigatório)
Passos do Filipe, no Studio (versão mais recente):
1. **Assistant** → configurações → **MCP Servers**.
2. Ligar **Enable Studio as MCP server**.
3. Em **Quick connect**, ligar **Claude Code**. Se o Claude Code não aparecer na lista, reiniciar o Studio.
4. Reiniciar o Claude Code. Um indicador verde no Studio mostra os clientes conectados.

Se o quick connect não funcionar, o mesmo painel mostra a configuração em JSON e o comando para a linha de comando. Use o que ele mostrar.

Teste: listar o conteúdo do Workspace e tirar uma captura de tela.

### 0.2 Blender + MCP (para ajustes de malha)
1. Filipe instala o **Blender** (blender.org), se ainda não tiver.
2. Instalar o `uv`, se faltar, pelo instalador oficial (não por `pip install uv`).
3. Configurar o servidor e o addon. O instalador oficial do projeto `mcp-for-blender` (antigo `blender-mcp`) faz os dois: `uvx mcp-for-blender setup`. Manualmente: `claude mcp add blender uvx mcp-for-blender` e `uvx mcp-for-blender install-addon`.
4. No Blender: Edit → Preferences → Add-ons → ativar **Interface: Blender MCP**. Na barra lateral (N), aba BlenderMCP → **Connect**.
5. Reiniciar o Claude Code e testar com uma captura do viewport.

Não rodar o `uvx` do servidor à mão no terminal: quem inicia o servidor é o Claude Code.

### 0.3 Tripo (peças principais)
- Caminho mais confiável: o Filipe gera no **app web do Tripo** (tripo3d.ai) usando os prompts da Fase 5, ativa a opção de malha leve (Smart Mesh / Smart Low-Poly) e exporta em **FBX**. Os arquivos vão para `modelos/tripo/`.
- Opcional: o servidor oficial `tripo-mcp` (em alpha) gera pelo Blender. Exige o **addon do Tripo para Blender** (site do Tripo) com a chave de API do Filipe. Configuração: `claude mcp add tripo uvx tripo-mcp`. Se der problema, volte para o app web.
- **Nunca** escreva a chave de API em arquivos desta pasta.

---

## Fase 1 — Blockout com Parts (escala e caminhada)

Só caixas e cilindros cinza, nada de detalhe. Serve para testar o tamanho.

- Lobby inteiro: ~600 × 600 studs. Nave central: ~70 de largura × 220 de comprimento, de sul (spawn) a norte (altar).
- Duas fileiras de 6 colunas (10–14 studs de diâmetro, 80–100 de altura).
- **Círculo Rúnico** (spawn) na ponta sul; **Marco dos Recordes** ao lado.
- **Altar do Coração** (degraus + base do cristal) na ponta norte.
- Entradas das torres no meio da nave: **Caverna das Profundezas** a oeste, **Ruínas Subterrâneas** a leste (com 30+ studs de altura, visíveis do spawn).
- Áreas de roleplay como caixas, ligadas à nave por arcos entre as colunas: **Acampamento dos Exploradores** (SO), **Mercado das Raízes** (SE), **Arquivo Soterrado** (NO), **Lago Espelhado** (NE), **Galerias Altas** (em volta, no alto). Cada uma com 120–150 studs.
- Playtest com velocidade padrão (16 studs/s): spawn → torres ≈ 6 s; spawn → altar ≈ 13 s; nada obrigatório a mais de 15 s.

Comparar com `08-mapa-layout.png` e `07-ALVO-roblox-aerea-caverna.jpg`.

## Fase 2 — A caverna em Terrain

- Casca da caverna em Terrain com **Rock**, **Slate** e **Basalt**: paredes irregulares com saliências (onde ficam as Galerias Altas), teto entre 120 e 150 studs e chão irregular nas bordas.
- **Buraco natural no teto** acima do Coração do Abismo, por onde entra o feixe. O poço acima pode ser falso (neblina e um pontinho de luz no alto).
- Rochedos grandes em Terrain separando as áreas de roleplay.
- **Piso de Áuren só na avenida central:** Parts escuras com uma MaterialVariant de rugosidade baixa (parecer molhado). O resto do chão é rocha.
- Lago Espelhado com água do Terrain e a Cascata do Abismo.

## Fase 3 — Iluminação e atmosfera (valores iniciais)

| Onde | Propriedade | Valor |
| --- | --- | --- |
| Lighting | Technology | Future (ShadowMap se pesar no celular) |
| Lighting | ClockTime | 0 |
| Lighting | Ambient | 24, 20, 34 |
| Lighting | OutdoorAmbient | 18, 15, 28 |
| Atmosphere | Density | 0,4 |
| Atmosphere | Color / Decay | 40, 30, 60 / 60, 30, 90 |
| BloomEffect | Intensity / Size / Threshold | 0,8 / 24 / 1,5 |
| ColorCorrection | Contrast / Saturation | 0,1 / 0,1 |

Quatro camadas de luz: o **feixe** ciano sobre o Coração (o ponto mais claro), os **cristais roxos** (luz principal), as **lanternas douradas** de Áuren (pontos quentes) e o **reflexo** do chão molhado. Regra: o perigo é marcado por movimento (roxo que pulsa e solta faíscas), só na rachadura e nas Ruínas Subterrâneas.

## Fase 4 — Formações de rocha (gerador do Studio primeiro)

Gere de 3 a 4 variações de cada com `generate_mesh`. Use uma Part como caixa de tamanho para cada uma:

| Nome | Prompt sugerido (inglês) | Triângulos |
| --- | --- | --- |
| **Presas do Teto** | stylized low-poly cave stalactite, dark violet-grey rock, game asset | ≤ 1.000 |
| **Gotas da Fenda** | stylized low-poly cave stalactite with a glowing purple crystal tip | ≤ 1.500 |
| **Agulhas de Pedra** | stylized low-poly cave stalagmite, dark violet-grey rock, game asset | ≤ 1.000 |
| **Rochedos Caídos** | stylized low-poly boulder pile, dark slate rock, game asset | ≤ 1.500 |

Se a qualidade não servir, gere no Tripo (Fase 5). Distribua por script com semente fixa: rotação e escala aleatórias (0,6–1,6×), mais densas nas bordas, e nunca bloqueando a avenida ou as entradas. As **Presas do Teto** cobrem o teto inteiro. As **Gotas da Fenda** ficam no teto da avenida, perto do altar. As **Agulhas de Pedra** ficam entre as colunas e nas áreas de roleplay.

## Fase 5 — Peças principais (Tripo → Blender → Studio)

Gerar no Tripo. Quando houver imagem, usar imagem-para-3D com um recorte da referência indicada; senão, o prompt. Prompts em inglês, sempre com "stylized low-poly game asset".

| Peça | Referência | Prompt base | Triângulos | No Blender |
| --- | --- | --- | --- | --- |
| **Coração do Abismo** | 04, 06 | giant jagged purple amethyst crystal cluster, one tall central crystal surrounded by smaller ones, flat base | ≤ 10.000 | Pivô na base |
| **Colunas Engolidas** (módulos: base, corpo, topo quebrado) | 04, 06 | ancient dark stone column with worn gold trim bands and a diamond-shaped purple crystal inset, partly broken, rock and moss growing over it | ≤ 3.000 por módulo | Dividir em módulos; uma variação fundida com estalagmite e uma caída |
| **Vigia do Sol** | 03, 05 | ancient ruined stone gate with a huge carved stone face monolith, eyes closed, sun-shaped runes on the sides | ≤ 10.000 | Fazer a **variação de olhos abertos** |
| **Estelas Solares** | 03 | carved stone stele with a sun-shaped rune | ≤ 1.500 | — |
| **Lanterna de cristal** (Correntes-Candeia) | 01 | hanging lantern made of a purple crystal in a small dark metal frame | ≤ 1.000 | Pivô no topo |
| **Lanterna de Áuren** e **Braseiro de Áuren** | 01, 03 | small ancient golden lantern / stone brazier | ≤ 1.500 | — |
| **Forja de Cristal** | — | stylized fantasy forge with an anvil and a furnace made of purple crystal, built into tree roots | ≤ 5.000 | — |
| Props de roleplay: tenda, baú, mesa de mapa, banca de raiz, balcão, estante de tábuas de pedra, mesa de leitura | 06, 07 | stylized low-poly fantasy explorer tent / chest / market stall built inside giant tree roots / etc. | ≤ 2.000 cada | — |
| **Casa partida de Áuren** (modular) | 07 | small ruined stone house carved into a rock ledge, partly buried | ≤ 3.000 | Módulos encaixáveis |

**No Blender**, para cada peça: corrigir a escala para studs (comparar com um bloco de referência de 5 studs, a altura de um avatar), reduzir até o orçamento (Decimate), aplicar transformações, pivô na base e exportar em **FBX**.

**Importar no Studio:** se o MCP do Studio não importar arquivos locais, o Filipe usa **File → Import 3D** e você posiciona, nomeia e organiza depois.

Peças que **não** precisam de malha: degraus do altar, base da avenida, Marco dos Recordes (Parts com materiais).

> **Atualização (24/11/2026, decisão do Filipe):** as **Colunas Engolidas** e os **degraus do altar** já foram feitos
> por código em pedra lavrada irregular (`scripts/lobby1-pedras.py` / `.luau`) e NÃO vão mais para o Tripo. Padrão
> visual do jogo inteiro: ver `docs/GDD-resumo.md` > Lobby 1 > "Padrão de beleza".

## Fase 6 — Áreas de roleplay

- Montar cada área com os props da Fase 5 e algumas Parts, seguindo `06` e `07`.
- Lugares para sentar (Seat) em todas: bancos, tendas, degraus do altar, beira do lago.
- Lanternas e braseiros que acendem e apagam com ProximityPrompt.
- Portas das casas das Galerias Altas que abrem e fecham.
- Quadro de avisos no Acampamento, **só com mensagens prontas** (texto livre de jogador exige o filtro de texto do Roblox).
- **Túnel dos Ecos:** passagem secreta atrás da cascata, ligando o Lago ao Arquivo, com um fragmento de lore escondido.

## Fase 7 — Efeitos e estados

- **Feixe Ascendente:** Beam ciano com luz do buraco do teto até o Coração; poeira no feixe (ParticleEmitter).
- **Anéis Rúnicos:** anéis de runas douradas girando com Tween atrás do Coração.
- **Círculo Rúnico:** runas acendem quando um jogador aparece.
- Partículas: **Esporos-Lume** (verdes, sobem devagar do musgo) e **Faíscas de Mana** (ciano, perto dos cristais).
- **O Sono de Kokuryū:** a cada 2–4 min, ronco grave vindo das Ruínas Subterrâneas, tremor leve de câmera, poeira do teto e um pulso do Coração. Mais forte depois da Torre 1 e desligado depois de vencer Kokuryū.
- **Estados por jogador** (só no cliente, porque jogadores com progressos diferentes dividem o lobby): Vigia do Sol de olhos fechados e runas apagadas até vencer a Torre 1; Feixe Ascendente fraco até vencer Kokuryū. Deixe uma flag de teste para alternar os estados.

## Fase 8 — Desempenho e revisão final

- StreamingEnabled ligado; cada área de roleplay como um Model separado.
- PointLights só no Coração, no feixe, nas entradas das torres e em poucas lanternas grandes.
- Testar no emulador de celular do Studio.
- Captura final do spawn olhando para o altar e uma vista aérea; comparar lado a lado com `06` e `07` e listar as diferenças para o Filipe.

---

## Pendências de design (não inventar; perguntar ao Filipe)
- Chefão da Torre 1 (o Filipe vai mandar a imagem).
- Roteiro da primeira fala do Observador (o Filipe já escreveu).
