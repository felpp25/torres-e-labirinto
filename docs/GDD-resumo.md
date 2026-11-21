# Torres dos Labirintos — Resumo do GDD

> Resumo do documento de design do projeto. Consulte antes de qualquer decisão de gameplay.
> Se algo não estiver aqui (ou estiver ambíguo), pergunte em vez de inventar.

## Progressão global e torres

- **Nível, atributos, XP e Gold são GLOBAIS** (da conta, acumulam entre runs; salvos em DataStore no jogo final).
- **Cada torre (run) exige um nível mínimo** para entrar (ex.: Torre 1 livre, Torre 2 a partir do nível 10).
- **XP, níveis e Gold ganhos NUNCA se perdem**: nem no game over, nem saindo da run por conta própria.
  O que se perde no game over é a tentativa (a torre recomeça do andar 1) e o prêmio do boss.
- **Recompensas: mobs dão pouco, o boss dá o grosso** (XP, Gold e drops). Meta a definir quando o boss existir
  (ex.: ~30% do XP da run nos mobs e ~70% no boss). Evita farm de mobs e faz do boss o objetivo da run.
  *Protótipo:* mobs 8 XP e 1-3 Gold; boss 1500 XP e 300 Gold por jogador. Uma torre completa leva do nível 1 a
  perto do 10 (teto atual).
- **Salvamento (DataStore):** uma chave por jogador com **vários personagens** por conta (slots); cada personagem
  tem classe, nível, XP, atributos e pontos livres. O **Gold é da CONTA**, compartilhado por todos os personagens:
  o jogador troca de personagem no lobby para atender o grupo (ex.: o time precisa de um curandeiro) sem recomeçar
  a economia. A **run em andamento não é salva** (sair no
  meio da torre = run nova ao voltar; o que foi ganho fica). Salva ao sair, ao fechar o servidor, a cada 2 min e
  ao concluir uma torre. Trava de sessão evita perder dados ao trocar de servidor.
  *Protótipo:* 1 personagem (Lutador) criado automaticamente; a escolha de personagem vem com o lobby.
- *Protótipo:* uma torre só e sem exigência de nível. Teto de nível 10 (vai subir quando houver mais torres).

## Vidas

- **3 vidas do GRUPO por run.** Morrer com aliado vivo não gasta vida (espera o checkpoint).
  **Wipe** (todos mortos) gasta 1 vida e recomeça o andar atual.
- **Sem vidas: game over**: a torre recomeça do andar 1 com labirinto novo (XP e Gold ficam, ver acima).
- **Vida extra comprada** (Developer Product, no futuro): com limite por run (ex.: 1), para não virar
  "pague para não perder" perto do boss. O Coração continua como alternativa grátis.
- **Coração:** item raro dropado por mobs, devolve 1 vida (máximo 3). Chance base **0,1% por mob**, multiplicada
  pela Sorte (regra de achados raros: Sorte 50 = 0,2%, Sorte 100 = 0,3%).

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
- **Boss:** no último andar da torre (andar 5), a sala do puzzle é substituída por uma **arena** (2 salas de
  comprimento, na borda do labirinto) com o boss. Vencer o boss conclui a torre.
- **Cada boss é único** (tema, habilidades e moveset próprios). Os ataques são dados (Balance/Bosses): a IA é
  genérica e executa a lista de cada boss.
- *Protótipo:* boss "Guardião da Torre": golpe pesado à frente + pisão em círculo, ambos com aviso no chão;
  1200 de vida (+50% por jogador extra), Defesa 10, imune a empurrão; dá 1500 XP e 300 Gold a cada jogador.
- **Torre concluída:** aviso "TORRE CONCLUÍDA" e uma run nova começa no andar 1. *Futuro:* voltar a um **lobby**
  onde os jogadores escolhem a torre (e outras funções a definir).
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

- **Recursos: cada habilidade declara o próprio recurso, pela NATUREZA dela** (não pela classe):
  - **Stamina:** golpes, armas e movimento. A **esquiva** sempre gasta stamina, em todas as classes.
  - **Mana:** Chi, sagrado, elemental e cura.
  - Cada classe fica num ponto do espectro: **Lutador** quase só stamina; **Monge** híbrido (o caminho Chi gasta
    mana); **Paladino** golpes de arma (stamina) + poderes sagrados (mana); **Mago e Sacerdote** quase só mana
    (stamina para esquivar). Assim Sabedoria e Destreza valem conforme a build e as três poções servem para alguém.
  - Descartados: um recurso por classe (Sabedoria inútil para físicos, Destreza inútil para magos) e custo duplo
    (duas barras a gerenciar em toda ação).
  - **Mana e stamina começam em 100** para todas as classes (Sabedoria e Destreza somam a partir daí).
  - O **Lutador já tem uma habilidade de mana** (Foco Interior, ver Classes), para a Sabedoria ter uso desde a
    classe inicial.
- **Defesa:** `redução de dano = Defesa / (Defesa + 40)` (10 → 20%, 27 → 40%, 100 → 71%; **nunca chega a
  100%**: tank invencível é antijogo). A constante era 100, mas a bateria de atributos mostrou que a Defesa rendia
  pouco nos valores reais (27 pts = 21%) e perdia sempre para a Vitalidade.
  - **Objetivo de design do tank:** o tank precisa se sentir **útil e até indispensável na party**, e um jogador
    focado em Defesa/Força/Vitalidade deve conseguir **zerar uma run solo** (com bastante desafio).
  - *A decidir (próximo passo de design):* sistema de **aggro** (mobs focam o tank) para o tank ter papel claro no
    grupo; hoje os mobs atacam o jogador mais próximo.
- **Sorte é GLOBAL:** afeta tudo que é chance de coisa boa.
  - **Crítico:** `5% + 0,5% × Sorte`, crítico causa **1,5×** de dano.
  - **Achados raros** (regra única, `Formulas.luckChance`): `chance base × (1 + Sorte / 50)` (a cada 50 pts as
    chances dobram). Hoje: **Coração**. Futuro: drops de itens, baús, salas secretas.
  - No coop, os achados usam a **maior Sorte entre os jogadores perto** (ter alguém sortudo ajuda o grupo).
- **Inteligência** não tem uso para o Lutador (sem dano mágico); o painel não avisa (decisão do designer).
  A **Sabedoria** serve ao Lutador pelo Foco Interior (mais mana = mais usos seguidos).
- Cada classe tem **2 atributos com scaling extra**.
- **Fórmula de dano:** `Dano = Base × (1 + 0,02 × Atributo × M)`
  - `Atributo` = Força para dano físico, Inteligência para dano mágico;
  - `M = 1` para atributos comuns; `M = 1,5` para os atributos de scaling da classe.
- **3 pontos de atributo por nível.**
- **O jogador escolhe em qual atributo colocar cada ponto.** Botão **"distribuir recomendado"**: coloca os pontos
  nos atributos de scaling da classe.
  - *Implementado:* ao subir de nível os pontos ficam LIVRES; painel de atributos (tecla C / botão X / botão
    "+N pontos" na tela) com +1 por atributo, prévia do efeito, ★ nos atributos de scaling e botão "Recomendado".
    O servidor valida cada pedido. Ponto colocado é definitivo (sem reset por enquanto).
  - Ainda a decidir: se dá para resetar pontos (ex.: item ou Gold).

## Classes e builds

Cada classe primária evolui para uma classe avançada (detalhes de habilidades em [Ideias.md](Ideias.md)):

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
- **Kit do Lutador (3 habilidades + 1 ultimate, decidido pelo designer):**
  - **Palma de Ferro** (tecla 1 / Y): golpe forte à frente com empurrão. 30 de **stamina**, recarga 6 s.
  - **Foco Interior** (tecla 2 / R1): cura **12% da vida** e dá **+12% de dano por 6 s** (vale para todo golpe e
    habilidade; aura azul visível para o grupo). 50 de **mana**, recarga 10 s. A **mana é o limite**, não a
    recarga: com 100 de mana são 3 usos no ritmo máximo e cada +20 de mana (4 pontos de Sabedoria) dá mais 1.
  - **Chute Giratório** (tecla 3 / L2): acerta **todos em volta** (raio 7), 22 de dano e empurrão leve para longe.
    35 de **stamina**, recarga 8 s. Para quando o Lutador está cercado.
  - **Ultimate: Rajada de Cem Punhos** (tecla 4 / L1): 8 socos à frente em 1,6 s (7 × 10 + 20 = 90 de dano base, 3× a
    Palma; o último empurra). O Lutador fica **parado** durante a rajada (sem andar, atacar ou esquivar): risco em
    troca do dano. Feita para o boss.
- **Ultimate (regra geral):** gasta a **barra de ultimate** (0 a 100%), não stamina nem mana.
  - Enche **lutando**: causar 600 de dano enche a barra do zero; tomar 200 de dano também (ajuda a linha de
    frente). Vale para as duas coisas somadas. O dano da própria ultimate não enche a barra.
  - Referência no andar 1: ~1 ultimate por andar só batendo; ~2 durante o boss.
  - A barra **fica com o jogador ao morrer** e **zera ao entrar na torre** (carregar nos bonecos do lobby não vale).
  - HUD: ícone com a % de carga; dourado quando cheia.

## Morte e checkpoint

- Quem morre **não renasce sozinho**. Volta à vida só com:
  - um **item de renascimento** (dropável, bem raro); ou
  - o **checkpoint**: quando um sobrevivente passa pelo checkpoint do andar, todos os mortos do grupo renascem ali.
- O andar pode ser concluído com **apenas um jogador vivo**.
- Enquanto está morto, o jogador fica em **modo espectador**: a câmera segue um aliado vivo (com botão para trocar).
- **Todos morreram antes de concluir o andar (wipe):** gasta 1 vida do grupo e todos voltam ao **início do andar
  atual**. O labirinto **não muda** (mesmo layout); mobs e placas voltam ao estado inicial do andar.
  Sem vidas: game over (ver "Vidas").
  - *Validado no protótipo:* os mobs voltarem depois do wipe dá a sensação certa de desafio ("vou ter que me
    concentrar mais"). Sem isso, a segunda tentativa ficaria fácil e tediosa. **Manter.**
- **No checkpoint**, vida e mana voltam ao máximo antes do próximo andar.

## Lobby e loja

- O jogador **nasce no lobby**. A torre começa ao entrar no **portal**; quem entrar depois vai para o andar atual
  da run. Torre concluída ou game over: todos **voltam ao lobby**.
- **Loja** (balcão no lobby): o Gold é gasto aqui. Primeira versão:
  - **Poções** (consumíveis da conta, levadas para a run): **Vida** (recupera parte da vida máxima), **Stamina**
    (enche a stamina) e **Mana** (enche a mana). Usadas por **atalhos fixos** (teclas **E = Vida, R = Mana,
    T = Stamina**; botões na tela no celular), com recarga e limite de quantas guardar.
  - **Teclas (decisão do designer):** 1, 2, 3 = habilidades; 4 = ultimate; E, R, T = poções.
  - **Reset de atributos:** devolve todos os pontos para redistribuir; preço cresce com o nível.
- *Futuro:* escolha de torre e de personagem no lobby; mais itens de gameplay (lista em definição pelo designer).

## Equipamentos, fortalecimento e gemas (futuro, definido pelo designer)

- **Fortalecimento:** gastar **Gold para "upar" equipamentos**.
- **Gemas:** complementam atributos (ataque, defesa, vitalidade etc.). **Cada equipamento comporta 1 gema.**
  - Níveis **1 a 5**; cada nível acrescenta uma **porcentagem** no atributo da gema.
  - **Nível 1 a 3:** compradas na loja com Gold. **Nível 4:** só nas runs **Avançadas**. **Nível 5:** só na run
    **Pesadelo**.
- **A definir antes de construir:** quais slots de equipamento existem (arma, armadura, acessório...); como os
  equipamentos são obtidos; níveis e custo do fortalecimento (e se pode falhar); porcentagem de cada nível de gema;
  se a gema pode ser trocada/removida; se equipamento é do personagem ou da conta.

## Dificuldades (futuro)

- Modos **Normal**, **Avançado** e **Pesadelo** para cada torre.
- Quanto mais difícil: **muito mais Gold e drops melhores**; o **XP aumenta só um pouco** (nada discrepante, para a
  progressão continuar lenta e constante). O objetivo é ser difícil de verdade, não um atalho de XP.
- A definir: o que muda em cada modo (vida/dano dos mobs, nº de mobs, vidas do grupo, ataques extras do boss...),
  multiplicadores de recompensa e se os modos exigem nível mínimo ou concluir o modo anterior.

## Status do protótipo

- **Protótipo concluído e validado pelo designer** (M1 a M7, boss e vidas): o loop de subir andares, enfrentar mobs
  e o chefe no final, com vidas, Gold, XP, atributos e evolução linear lenta, é constante e **não frustrante**.
  Jogar solo é desafiador (bom). Nenhum bug de programação encontrado na run completa.
- Próximos passos (registrados ao longo deste resumo): lobby e escolha de torres, escolha manual de pontos de
  atributo, salvar o progresso (DataStore), dificuldades, mais classes/armas/árvore de skills, drops e itens,
  puzzle mais longo (30 a 90 s), vida comprada com limite.

## Regra técnica

- O servidor tem autoridade sobre tudo: dano, XP, Gold e drops.
