# Torres dos Labirintos — Resumo do GDD

> Resumo do documento de design do projeto. Consulte antes de qualquer decisão de gameplay.
> Se algo não estiver aqui (ou estiver ambíguo), pergunte em vez de inventar.

## Progressão global e torres

- **Nível, atributos, XP e Gold são GLOBAIS** (da conta, acumulam entre runs; salvos em DataStore no jogo final).
- **Cada torre (run) exige um nível mínimo** para entrar (ex.: Torre 1 livre, Torre 2 a partir do nível 10).
- **Torre concluída:** tudo o que foi ganho na run fica. **Game over:** perde só o que foi ganho NESTA run
  (XP, níveis, pontos, Gold) e volta a como estava antes de entrar.
- *Protótipo:* uma torre só, andares infinitos, progresso global só na memória do servidor (sem DataStore) e sem
  exigência de nível. Teto de nível 10 (vai subir quando houver mais torres).

## Vidas

- **3 vidas do GRUPO por run.** Morrer com aliado vivo não gasta vida (espera o checkpoint).
  **Wipe** (todos mortos) gasta 1 vida e recomeça o andar atual.
- **Sem vidas: game over** (ver acima) e a torre recomeça do andar 1 com labirinto novo.
- **Coração:** item raro dropado por mobs, devolve 1 vida (máximo 3). Chance base **0,1% por mob**; no futuro a
  Sorte aumenta essa chance.

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
- *Protótipo:* puzzle de 2 a 3 placas de pressão na sala do Puzzle; cada placa fica ativada depois de pisada
  (solo: uma por vez; grupo: cada um pisa uma). Todas ativas = a saída (escada) abre; pisar nela = checkpoint.
- *Protótipo:* a sala de Entrada é zona segura para ACORDAR mobs (um mob dormindo não acorda vendo alguém lá
  dentro; um mob já acordado continua perseguindo). Evita emboscada no instante em que o andar começa.
- *Protótipo:* andares infinitos com dificuldade crescente (o limite de 5 andares + boss vem depois).
- **Dificuldade por andar:** +1 mob por sala de combate **a cada 2 andares** e +15% de vida e dano nos mobs
  a cada andar (valores iniciais, ajustáveis).

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
- **O jogador escolhe em qual atributo colocar cada ponto.** Botão **"distribuir recomendado"**: coloca os pontos
  nos atributos de scaling da classe.
  - *Protótipo:* os pontos vão automaticamente para o "recomendado". A escolha manual (painel com +1 por atributo,
    validado no servidor) fica para depois do protótipo. Ainda a decidir: se dá para resetar pontos (ex.: item ou Gold).

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
- **Todos morreram antes de concluir o andar (wipe):** gasta 1 vida do grupo e todos voltam ao **início do andar
  atual**. O labirinto **não muda** (mesmo layout); mobs e placas voltam ao estado inicial do andar.
  Sem vidas: game over (ver "Vidas").
- **No checkpoint**, vida e mana voltam ao máximo antes do próximo andar.

## Regra técnica

- O servidor tem autoridade sobre tudo: dano, XP, Gold e drops.
