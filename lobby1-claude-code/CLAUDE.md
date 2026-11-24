# Ascending Labyrinths — construção no Roblox

Este é o projeto do jogo **Ascending Labyrinths** (Roblox), do Filipe. O design e a lore são definidos no projeto "Ascending Labyrinths" do claude.ai; esta pasta é onde o jogo é **construído**. Tudo o que for de design já está decidido nos arquivos abaixo: siga-os em vez de reinventar.

- Plano de construção do Lobby 1, por fases: `BRIEFING-LOBBY1.md` (comece por ele)
- Resumo do design do Lobby 1: `docs/lobby1-resumo.md`
- Imagens de referência: `referencias/` (as marcadas como **ALVO** são o visual a perseguir)

## Ferramentas e papéis

| Ferramenta | Papel |
| --- | --- |
| **Roblox Studio** (servidor MCP embutido) | Centro de tudo: Terrain, Parts, iluminação, efeitos, scripts em Luau, playtest, capturas de tela |
| **Gerador de malhas do Studio** (Cube, ferramenta `generate_mesh` do MCP) | Peças pequenas e repetidas (estalactites, estalagmites, pedras). Gratuito; testar primeiro |
| **Tripo** (app web/API; MCP `tripo-mcp` opcional, em alpha, via Blender) | Peças principais e props de roleplay |
| **Blender** (MCP `blender`) | Ajustes: escala em studs, reduzir triângulos, pivô, dividir peças modulares, variações (ex.: olhos do Vigia do Sol). Rig do dragão Kokuryū |

Regra geral: **Terrain e Parts primeiro; malha só quando a forma pedir.** A caverna (paredes, teto, chão das bordas, rochedos grandes) é Terrain, não malha.

## Regras do projeto

- **Nomes:** use exatamente os nomes em português do design (Círculo Rúnico, Avenida das Colunas, Coração do Abismo, Vigia do Sol, Presas do Teto, etc.) nos nomes dos objetos do Studio. Não invente nomes novos para coisas que já têm nome; se precisar de um nome novo, proponha ao Filipe.
- **Visual: caverna primeiro, ruína depois** (~70% caverna natural, ~30% ruína de Áuren). Piso de Áuren só na avenida central.
- **Cores fixas:** pedra violeta escura (#1A1726, #2E2A3D) · roxo cristal (#8A3CFF, #C08CFF) · dourado de Áuren (#C9A24A metal, #FFB85C luz) · verde musgo (#2F5A3A, #5BE37D) · ciano Mana (#3FE0FF, só feixe, faíscas e Observador).
- **Orçamento de triângulos por malha:** peças principais ≤ 10.000 · módulos de coluna ≤ 3.000 · props de roleplay ≤ 2.000 · formações de rocha repetidas ≤ 1.500. O Roblox recusa ou simplifica malhas grandes demais.
- **Escala:** 1 stud ≈ 0,28 m. Modelos do Tripo vêm em metros: ajustar no Blender (ou no importador) antes de usar.
- **Celular conta:** Neon + Bloom para brilho, poucas PointLights, modelos repetidos, StreamingEnabled ligado.

## Como trabalhar

- Organize tudo em `Workspace/Lobby1/` com subpastas: `Terreno`, `Nave`, `Torres`, `Altar`, `Roleplay/<Área>`, `Formacoes`, `Luzes`, `Efeitos`.
- Antes de mudanças grandes no place, peça ao Filipe para salvar uma cópia (ou salve uma versão, se a ferramenta permitir).
- **Nunca apague** o que o Filipe construiu sem perguntar.
- Ao fim de cada fase: tire uma captura de tela pelo MCP, compare com `referencias/06-ALVO-roblox-em-jogo-caverna.jpg` e `07-ALVO-roblox-aerea-caverna.jpg`, diga o que ficou parecido e o que falta, e espere o OK antes de seguir.
- Passos que só o Filipe pode fazer (instalar programas, criar conta, colar chave de API, importar arquivo pelo menu do Studio): explique em poucas linhas e espere.
- Fale com o Filipe em português.
