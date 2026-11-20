# Torres dos Labirintos — Resumo do GDD

> Resumo do documento de design do projeto. Consulte antes de qualquer decisão de gameplay.
> Se algo não estiver aqui (ou estiver ambíguo), pergunte em vez de inventar.

## Visão geral

- **Jogo:** "Torres dos Labirintos" (título provisório).
- **Gênero:** RPG de ação coop, 1 a 4 jogadores, baseado em runs.
- **Run:** uma torre com 5 andares-labirinto curtos + boss final.
- **Duração:** 15 a 20 min por run (~3 min por andar).
- **Plataforma:** celular primeiro.

## Andares

- Cada andar é um labirinto gerado a partir de salas sorteadas: **8 a 12 salas**, sempre com caminho garantido
  da entrada até a sala do puzzle.
- Um **puzzle simples (30 a 90 s)** abre a escada (o **checkpoint**) para o próximo andar.
- **Todo puzzle precisa de versão solo.**
- **Dificuldade por andar:** a cada andar, +1 mob por sala de combate e +15% de vida e dano nos mobs
  (valores iniciais, ajustáveis).

## Recompensas

- Mobs dão **XP e Gold**.
- **XP no coop:** todos os jogadores perto do mob quando ele morre ganham o XP inteiro.
- **Gold e loot são individuais:** cada jogador recebe a sua parte.

## Atributos

Sete atributos, iguais para todas as classes (substituem a lista antiga com Agilidade e Foco):

| Atributo | Efeito |
|---|---|
| **Força** | Aumenta o dano físico: golpes, espadas, arcos, adagas, tudo que causa dano físico. |
| **Vitalidade** | Aumenta a vida máxima (pontos fixos por ponto de atributo). |
| **Inteligência** | Aumenta o dano mágico e o dano de armas mágicas. |
| **Sabedoria** | Aumenta a mana máxima. |
| **Destreza** | Aumenta a stamina. Mais stamina = mais habilidades usadas em sequência. A stamina regenera depois de alguns segundos sem uso. |
| **Defesa** | Aumenta a armadura, que reduz o dano físico e o mágico na mesma proporção. Atributo do tank. |
| **Sorte** | Aumenta a chance de crítico, a taxa de drop dos mobs e a chance de achar baús secretos no mapa. |

- **Recursos:** ações **físicas** (golpes especiais, esquiva) gastam **stamina**; ações **mágicas** gastam **mana**.
- **Defesa:** `redução de dano = Defesa / (Defesa + 100)` (50 → 33%, 100 → 50%; nunca chega a 100%).
- **Sorte (protótipo):** `chance de crítico = 5% + 0,5% × Sorte`, crítico causa **1,5×** de dano.
  Drop e baús secretos ficam para depois do protótipo.
- Cada classe tem **2 atributos com scaling extra**.
- **Fórmula de dano:** `Dano = Base × (1 + 0,02 × Atributo × M)`
  - `Atributo` = Força para dano físico, Inteligência para dano mágico;
  - `M = 1` para atributos comuns; `M = 1,5` para os atributos de scaling da classe.
- **3 pontos de atributo por nível.**
- Botão **"distribuir recomendado"**: coloca os pontos nos atributos de scaling da classe.

## Classes e builds

Cada classe primária evolui para uma classe avançada (detalhes de habilidades em `Ideias.md`):

| Primária | Avançada |
|---|---|
| Mago | Arcanista |
| Bruxo | Necromante |
| Soldado | Pistoleiro |
| Engenheiro | Ciborgue |
| Arqueiro | Caçador |
| Assassino | Ninja |
| Lutador | Monge |
| Curandeiro | Sacerdote |
| Guerreiro | Paladino |
| Berserker | (classe única, sem evolução) |

- **A classe avançada mantém as habilidades da classe primária.**
- **O que define as habilidades de fato é a build: arma + árvore de skills.**
- O jogador equipa **3 habilidades + 1 ultimate**, escolhidas entre os "caminhos" da classe.

**Classe do protótipo: Lutador** (o jogador começa como Lutador e depois evolui para Monge).

### Lutador → Monge

- **Tema:** artes marciais e chi.
- **Papel:** linha de frente.
- **Scaling:** Força e Vitalidade.
- **Caminhos (Monge):** Punhos, Chi, Postura.

## Morte e checkpoint

- Quem morre **não renasce sozinho**. Volta à vida só com:
  - um **item de renascimento** (dropável, bem raro); ou
  - o **checkpoint**: quando um sobrevivente passa pelo checkpoint do andar, todos os mortos do grupo renascem ali.
- O andar pode ser concluído com **apenas um jogador vivo**.
- Enquanto está morto, o jogador fica em **modo espectador**: a câmera segue um aliado vivo (com botão para trocar).
- **Todos morreram antes de concluir o andar:** a run volta ao **andar 1** (labirinto novo), mantendo nível e XP.
- **No checkpoint**, vida e mana voltam ao máximo antes do próximo andar.
- Versão completa: perder a run custa os itens da run, mas mantém nível e XP.

## Regra técnica

- O servidor tem autoridade sobre tudo: dano, XP, Gold e drops.
