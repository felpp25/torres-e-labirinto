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
  tem classe, nível, XP, atributos, pontos livres e os 7 slots de equipamento. O **Gold** e o **baú de
  equipamentos** (50 espaços) são da **CONTA**, compartilhados por todos os personagens:
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
- **Sorte é GLOBAL:** afeta tudo que é chance de coisa boa (exceção: o fortalecimento de equipamentos, ver
  "Equipamentos").
  - **Crítico:** `5% + 0,5% × Sorte`, crítico causa **1,5×** de dano.
  - **Achados raros** (regra única, `Formulas.luckChance`): `chance base × (1 + Sorte / 50)` (a cada 50 pts as
    chances dobram). Hoje: **Coração** e **equipamentos** (Raro do item do chefe, drop dos mobs). Futuro: gemas,
    baús, salas secretas.
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
  - *Implementado:* ao subir de nível os pontos ficam LIVRES; janela **Personagem** (tecla C / botão X / botão
    "Personagem" na tela, sempre visível) > botão **Distribuir pontos** (janela própria) com +1 por atributo, prévia
    do efeito, ★ nos atributos de scaling e botão "Recomendado". Mostra o valor distribuído e, em verde, o que o
    equipamento soma. O servidor valida cada pedido. Para refazer os pontos: **reset na loja** (Gold).
  - O equipamento soma **por fora** dos pontos distribuídos: o reset só devolve os pontos distribuídos.

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
  - **Vender equipamento** (aba Vender): peças do baú (as equipadas não aparecem), Comum 10 e Raro 50 Gold, **mais
    1/3 das tentativas de fortalecimento** na peça fortalecida (ver "Fortalecimento"; ex.: Gibão Comum +7 = 4.243).
    Peça Rara ou fortalecida pede um segundo clique para confirmar. **Peça com gema não é vendida** (decisão do
    designer): extraia a gema antes. Gemas e Removedores sobrando também são vendidos aqui, **a 10% do preço** (ver
    "Gemas").
  - **Gemas** (aba Gemas): gema Nv1 de cada um dos 6 atributos (1.000 Gold) e o Removedor Nv1 (100 Gold).
- **Forja** (bigorna no lobby, atrás da loja): fortalecimento e gemas (ver "Equipamentos > Forja").
- *Futuro:* escolha de torre e de personagem no lobby; mais itens de gameplay (lista em definição pelo designer).

## Equipamentos, fortalecimento e gemas (decidido pelo designer; etapas 1 a 3 construídas)

*Implementado (etapa 1):* catálogo da Torre 1, baú da conta (50), 7 slots, equipar/trocar no lobby (painel
Personagem > Equipamento), atributos e Poder do equipamento no combate, item garantido do chefe, drop dos mobs, aviso
de item novo e venda na loja.
*Implementado (etapa 2):* Forja no lobby com o fortalecimento +1 a +10 (sem itens de bênção, adiados).
*Implementado (etapa 3):* gemas. Gema Nv1 e Removedor Nv1 na loja; incrustar, extrair e fundir na Forja. As gemas Nv2
a Nv5 só caem nas torres 5+ (ainda não existem); a fusão foi testada com o DevService.

### O que o equipamento dá
- **Pontos nos 7 atributos** (os mesmos do personagem), somados aos pontos distribuídos. As fórmulas não mudam e a
  especialização sai do ★ da classe: um atributo de scaling vale 1,5× também quando vem do equipamento.
  - Ex.: Colar Arcano (+4 INT, +1 SAB): o Mago (INT ★) ganha +12% de dano mágico; o Sacerdote (INT comum) ganha +8% e
    só +5 de mana. Serve aos dois, rende mais para quem foi feito.
- **Atributos FIXOS** por modelo e raridade (sem sorteio no drop): fácil comparar e passar entre personagens.
- **Sorte só nos acessórios** (Pulseira e Colar): a Sorte mexe na economia de drops.

### Slots (7) e linhas
- **Arma, Capacete, Armadura, Calças, Botas, Pulseira e Colar.** Cada peça leva **1 gema**.
- Armaduras e acessórios servem a **qualquer classe** (a escolha é pelos atributos). **Armas são presas à classe.**
- A Armadura é a peça grande (mais pontos); os acessórios são os menores.
- **Linhas** (o "scaling" de cada peça):

| Linha | Atributos | Feita para |
|---|---|---|
| Guardião | Defesa ++, Vitalidade + | tanks |
| Combatente | Força ++, Vitalidade + | corpo a corpo (Lutador) |
| Ágil | Força ++, Destreza + | golpes rápidos, muita stamina |
| Arcano | Inteligência ++, Sabedoria + | dano mágico |
| Sagrado | Sabedoria ++, Vitalidade + | cura e suporte |

- **Referência de força** (números finais em `Balance`, ajustados no playtest): um conjunto completo Comum ≈ metade
  dos pontos do nível 10 (~14); um conjunto Raro ≈ os 27 pontos do nível 10.
- **Raridades:** **Comum** (cinza) e **Raro** (azul, o DOBRO dos pontos e do Poder do Comum) na Torre 1 Normal.
  Épico e acima vêm com os modos Avançado/Pesadelo e a forja.
- **Pontos por slot** (Comum / Raro): Arma = Poder + 1 a 3 pts / dobro; Capacete 2 / 4; Armadura 3 / 6; Calças 2 / 4;
  Botas 2 / 4; Pulseira e Colar 2 / 4 (metade da linha, metade Sorte). Conjunto completo: ~14 / ~28.

### Armas
- A arma dá **Poder** (+% no dano do tipo dela: físico nas luvas, mágico num cajado) + atributos próprios.
  O Poder multiplica o dano final (como o bônus do Foco Interior):
  `Dano = Base × (1 + 0,02 × Atributo × M) × (1 + Poder)`.
- **Padrão: 3 armas por classe.**
  - **Inicial:** todo personagem da classe começa com ela.
  - **Intermediária:** evolução do mid-game.
  - **Avançada:** late-game, só para a **classe avançada**.

| Classe primária | Arma inicial | Arma intermediária | Classe avançada | Arma avançada |
|---|---|---|---|---|
| Mago | Orbe | Cajado | Arcanista | Grimório |
| Bruxo | Varinha Mágica | Lanterna Mágica | Necromante | Foice Mágica |
| Soldado | Submetralhadora | Rifle | Pistoleiro | Pistola Dupla (uma em cada mão) |
| Engenheiro | Espingarda de Cano Duplo | Mochila Drone | Ciborgue | Rifle de Energia |
| Arqueiro | Arco | Besta | Caçador | Tomahawks (um em cada mão) |
| Assassino | Espada Curta | Adagas | Ninja | Katana |
| Lutador | Luvas | Soco Inglês | Monge | Manoplas |
| Curandeiro | Talismã | Cetro | Sacerdote | Pergaminho |
| Guerreiro | Espada Média | Espada Longa (Greatsword) | Paladino | Espada e Escudo |
| — | — | — | Berserker | Machado Grande |

- **Berserker:** classe única **avançada**, obtida por outros meios (a definir pelo designer).
- **Lutador:** Luvas (Força + Destreza, sustentação) → Soco Inglês (mais Poder, dano) → Manoplas (Monge).
- *Futuro:* o tipo de arma define o conjunto de habilidades (ex.: Orbe, Cajado e Grimório do Mago, em
  [Ideias.md](Ideias.md)).

### Catálogo da Torre 1 (Lutador; valores Comum, o Raro é o dobro)

| Slot | Combatente (FOR ++, VIT +) | Guardião (DEF ++, VIT +) |
|---|---|---|
| Capacete | Faixa do Combatente: +2 FOR | Elmo do Guardião: +2 DEF |
| Armadura | Gibão do Combatente: +2 FOR, +1 VIT | Couraça do Guardião: +2 DEF, +1 VIT |
| Calças | Calças do Combatente: +1 FOR, +1 VIT | Perneiras do Guardião: +1 DEF, +1 VIT |
| Botas | Botas do Combatente: +1 FOR, +1 VIT | Botas do Guardião: +1 DEF, +1 VIT |
| Pulseira | Pulseira do Combatente: +1 FOR, +1 SOR | Pulseira do Guardião: +1 DEF, +1 SOR |
| Colar | Colar do Combatente: +1 VIT, +1 SOR | Colar do Guardião: +1 VIT, +1 SOR |
| **Conjunto** | **+7 FOR, +4 VIT, +2 SOR** | **+7 DEF, +4 VIT, +2 SOR** |

| Arma (Lutador) | Comum | Raro | Perfil |
|---|---|---|---|
| Luvas de Couro | Poder +5%, +1 FOR, +2 DES | Poder +10%, +2 FOR, +4 DES | sustentação (+10 de stamina) |
| Soco Inglês de Ferro | Poder +10%, +1 FOR | Poder +20%, +2 FOR | dano (~5% a mais) |

- Pelo padrão de 3 armas, as **Luvas são a arma inicial** (todo Lutador começa com Luvas de Couro Comuns) e o
  **Soco Inglês é a intermediária** (mid-game). *Protótipo:* enquanto a Torre 1 for a única torre, o Soco Inglês
  também cai nela (decisão do designer), para testar uma segunda arma.

- Efeito num Lutador nível 10 (14 FOR, 13 VIT, 230 de vida sem nada): Combatente Comum + Soco Comum = **+29% de
  dano**, 270 de vida; Combatente Raro + Soco Raro = **+61% de dano**, 310 de vida; Guardião Raro + Luvas Raras =
  +15% de dano, 310 de vida e **−26% de dano recebido**.
- Ágil, Arcano e Sagrado entram com as classes que usam essas linhas.

### Obtenção
- **Boss:** **1 item garantido por jogador** (loot individual). **35% de ser Raro** (com a regra de achados da Sorte:
  maior Sorte do grupo por perto); senão Comum.
  - **Quem tem direito (decisão do designer):** quem entrou na run **antes do andar do chefe**. Quem entra (ou volta
    pelo portal) já no andar 5 não ganha o item, **nem o XP e o Gold do chefe**, e a Sorte dele não conta no sorteio
    do Raro (fecha a brecha de sair, vestir peças de Sorte no lobby e voltar só para o chefe). Quem está parado no
    lobby também não ganha nada do chefe.
- **Mobs:** **0,5% por mob** (com a Sorte), sempre Comum. Cada participante perto do mob tem o seu sorteio (loot
  individual). A torre atual tem mais mobs que a estimativa (andar 1 com ~16-18, andar 5 com 30; ~110 por run):
  ~0,55 item de mob por run jogando solo.
- O slot e a linha são sorteados; **armas só da classe do personagem**. Nível mínimo dos itens da Torre 1: 1.
- Ritmo esperado: ~1,3 item por run; 1º Raro por volta da 3ª run; conjunto Comum completo de uma linha ~33 runs;
  conjunto Raro completo ~100 runs (~30 h). Misturar linhas e raridades é o normal no caminho.
- **Baús** (futuro, com as salas secretas da Sorte).
- **Fabricação na Forja** (futuro): receitas e fragmentos que caem em torres específicas nos modos **Avançado e
  Pesadelo**.

### Dono: conta + personagem
- Os itens ficam no **baú da CONTA** (como o Gold), com **50 espaços** (equipados não contam). Cada personagem tem os
  seus 7 slots e equipa a partir do baú.
- Um item equipado fica **em uso** por um personagem; equipar em outro tira do primeiro (exceto a arma, que não pode
  deixar o outro personagem sem arma).
- **Slot de arma nunca fica vazio (decisão do designer):** a arma só é trocada por outra, nunca tirada. A arma inicial
  só pode ser vendida depois de trocada.
- **Baú cheio (50/50):** não dá para tirar uma peça (ela não teria onde ficar); trocar continua permitido.
- **Nível mínimo** em cada item (o da torre em que cai): um personagem novo não herda o equipamento do fim de jogo.
- **Trocar equipamento só no lobby.** Na run, o item que cai vai para o baú (evita trocar para peças de Sorte na hora
  do drop).
- **Item sobrando:** vende na loja (Comum 10 Gold, Raro 50 Gold) ou **destrói arrastando para fora da mochila**
  (decisão do designer). Destruir pede confirmação, vale também dentro da torre (para abrir espaço antes do chefe) e
  aceita a peça fortalecida (o aviso diz quanto ela vale na loja); a peça com gema não (extraia antes). Uma pilha de gemas ou
  Removedores some inteira (é o que libera o espaço do baú). *Implementado:* "fora" = fora da janela Personagem
  inteira (soltar em cima do personagem não destrói nada); no celular, segurar a célula um instante antes de arrastar
  (arrastar logo de cara rola a mochila).
  - Descartados: destruir a peça com gema junto com a gema; destruir uma unidade da pilha por vez.
- **Baú cheio:** o drop vira Gold (preço de venda), com aviso que explica como liberar espaço (vender ou destruir). O
  aviso também aparece **ao entrar na torre e ao chegar no andar do chefe** com o baú cheio, antes de o drop se perder.
- **Interface (layout provisório, inspirado na mochila do DDTank; arte depois):** janela "Personagem" na tecla C com o
  personagem em 3D ao meio, o corpo à esquerda (Capacete, Armadura, Calças, Botas), arma e acessórios à direita
  (Arma, Pulseira, Colar), os atributos embaixo e a **mochila** (baú da conta) em grade ao lado. Clicar numa peça
  mostra os detalhes e a ação (Equipar/Trocar/Tirar). **Distribuir pontos** fica numa janela separada.

### Fortalecimento (+1 a +10)
- Cada nível dá **+10% dos atributos base da peça** (e do Poder, na arma): +10 = o dobro.
  - **Pontos quebrados ficam com decimais** (decisão do designer): Calças do Combatente (+1 FOR, +1 VIT) no +5 =
    +1,5 FOR, +1,5 VIT; Luvas Comuns no +1 = Poder +5,5%. Todo + aparece na tela (uma casa decimal).
  - Descartado: arredondar por peça (peças de 1 ponto não ganhariam nada de +1 a +4; o conjunto Combatente Comum
    no +3 daria FOR 9 / VIT 4 em vez de 9,1 / 5,2) e arredondar o total (alguns + não mudariam nada visível).
- **Custo em Gold:** `base da torre do item × 2^(nível − 1)`. Item da Torre 1: base 100 (+1 = 100, +2 = 200, +5 = 1.600,
  +10 = 51.200). Cada torre nova define a sua base, proporcional ao Gold que ela rende: o fortalecimento custa o
  mesmo esforço na torre de origem do item e acompanha a economia sozinho.
  - Descartado: ×5 por nível. A renda cresce por torre, o preço crescia 5× por nível: mesmo com 100× o Gold de hoje,
    um +10 pediria ~24 mil runs (+8 a +10 inalcançáveis na prática).
- **Chance de sucesso:** +1 a +3 = 100%; +4 = 90%; +5 = 80%; +6 = 70%; +7 = 60%; +8 = 50%; +9 = 40%; +10 = 30%.
- **Falha:** até +7 só perde o Gold. Falhar a tentativa de **+8, +9 ou +10 tira 1 nível** (ex.: +7 tentando +8 → +6;
  +9 tentando +10 → +8).
- **Itens de bênção** somam % à chance de sucesso. **Adiados (decisão do designer):** o fortalecimento saiu sem
  bênção; quanto ela soma e de onde vem se decide quando existirem as torres 2+ e a renda delas. Na Torre 1 o
  realista é chegar até +7, onde a bênção quase não muda nada (42 → 40 runs por peça).
  - Contas da análise (por peça, solo, ~450 Gold e 18 min por run; sem bênção: +8 = 122 runs, +10 = 1.379):

| Opção analisada | +8 | +10 | Bênçãos gastas até o +10 |
|---|---|---|---|
| Sem bênção | 122 runs | 1.379 runs (~414 h) | — |
| Drop do chefão, +10%, 1 por tentativa | 105 | 832 (−40%) | ~13 (qualquer chance > ~2% por chefão já sobra) |
| Drop do chefão, +10%, até 3 por tentativa | 83 | 438 (−68%) | ~19 |
| Loja, +10%, 1 por tentativa, 1.000 Gold | 108 | 861 | ~18 |

  - Ponto de atenção da loja: preço fixo vira troco nas torres que rendem mais Gold (aí todo mundo usa sempre).
- **Pedra de fortalecimento: adiada junto com a bênção** (decisão do designer). Os três papéis possíveis foram
  analisados (por peça, solo, mesmas hipóteses da bênção); nenhum muda o tempo até o +7, onde a Torre 1 chega:

| Papel analisado | +5 | +7 | +8 | +10 |
|---|---|---|---|---|
| Hoje (só Gold) | 8 runs | 42 | 122 | 1.379 |
| Obrigatória: 1 pedra + Gold por tentativa, 1 pedra por run | 8 | 42 | 122 | 1.379 |
| Obrigatória e rara (1 pedra a cada 4 runs) | 21 | 42 | 122 | 1.379 |
| Proteção: falhar do +8 ao +10 não tira nível (~8 pedras até o +10) | 8 | 42 | 99 | 620 |
| Chance: +10% por pedra, 1 por tentativa (= a bênção; ~21 pedras até o +10) | 7 | 36 | 97 | 819 |

  - **Obrigatória:** o Gold continua sendo o limite (uma peça até o +7 gasta ~8,5 tentativas; o conjunto, ~59). Só
    muda o tempo se for rara, e aí atrasa o começo. O ganho seria outro: um drop útil em toda run e não dar para
    fortalecer só com Gold (importa se o Gold um dia puder ser comprado ou trocado).
  - **Proteção e chance:** só fazem diferença do +8 em diante; decidir com a renda das torres 2+.
- **A Sorte NÃO afeta o fortalecimento** (exceção à regra da Sorte global): com itens da conta, todo mundo
  fortaleceria no personagem mais sortudo.
- **Ritmo de referência** (média com falhas, sem bênção, na torre de origem): +5 ≈ 8 runs, +7 ≈ 42 runs,
  +10 ≈ 1.400 runs, **por peça** (o conjunto de 7 peças no +7 ≈ 290 runs). O +10 é meta de longo prazo; os 3
  últimos níveis são ~97% do custo.
- **Venda da peça fortalecida** (decisões do designer; antes ela não era vendida): a loja paga o preço base (Comum
  10, Raro 50) **+ 1/3 da soma dos preços das tentativas** até o nível dela, na base da torre da peça. É o que gastou
  quem nunca falhou: a venda **nunca devolve mais do que o jogador gastou**, então fortalecer para vender sempre dá
  prejuízo. Sem item, direto na loja, com confirmação. O valor acompanha a base de cada torre sozinho.

| Nível | Soma na venda (Torre 1) | Runs | % do gasto médio |
|---|---|---|---|
| +1 | 33 | 0,1 | 33% |
| +3 | 233 | 0,5 | 33% |
| +5 | 1.033 | 2,3 | 29% |
| +7 | 4.233 | 9,4 | 22% |
| +8 | 8.500 | 19 | 15% |
| +10 | 34.100 | 76 | 5% |

  - Transferir continua melhor quando há outra peça para receber o nível (o +7 custa 6.400 e mantém tudo; vender
    devolve 4.233). A venda é para a peça que sobrou.
  - O preço da peça +0 (drops) continua Comum 10 / Raro 50: vendendo tudo, ~30 Gold por run (7% da renda).
  - Descartados: **item de recuperar** (drop que destrói a peça e devolve 1/3; a loja comprar direto faz o mesmo sem
    mais um item); **10 runs fixos** (uma peça +1 de 100 Gold devolveria ~4.500: o item viraria um drop de Gold);
    **1/3 do gasto médio** (+7 = 6.276, mas no +9/+10 14% a 20% dos jogadores receberiam mais do que gastaram);
    **1/2 das tentativas** (+7 = 6.350, quase o custo de transferir); **subir o +0** para 25/100 ou 50/200 (14% ou 29%
    da renda; fortalecer ficaria até ~20% mais rápido para todos).
  - *Implementado:* aba Vender da loja (a peça fortalecida aparece com o "+N" e o preço) e aviso de destruir.
- **Transferir o fortalecimento** (na Forja; decisões do designer):
  - As duas peças **trocam os níveis**: o Gibão Comum +7 com um Gibão Raro +0 vira Comum +0 e Raro +7. Nada se perde
    e serve também entre duas peças já fortalecidas. A gema de cada uma fica onde está.
  - **Custo: 1 tentativa do maior nível trocado**, na base da torre da peça que tem esse nível (Torre 1: +5 = 1.600
    Gold, 3,6 runs; +7 = 6.400, 14 runs, 34% de refazer; +10 = 51.200, 114 runs, 8% de refazer). Protege o investimento
    grande sem ser de graça.
  - **Só entre peças do mesmo tipo** (Arma com Arma, Armadura com Armadura...), mudando linha e raridade à vontade.
  - **Só para peça da mesma torre ou de uma mais baixa** (descer serve para passar a um personagem novo). Subir seria um
    atalho: um +7 feito numa peça da Torre 1 pago com o Gold da Torre 5 sai por 2,6 a 8 runs, contra 42 runs direto na
    peça da Torre 5 (Torre 10: 38× a 512× mais barato, nas hipóteses de renda ×1,5 e ×2 por torre).
  - Descartados: mover e zerar a origem (destino +0); perder 1 nível (recuperar custa 24 runs no +7 e ~990 no +10);
    20% do custo de refazer; grátis; qualquer tipo de peça; qualquer torre.
  - *Implementado:* aba **Transferir** da Forja: a peça escolhida à esquerda, à direita as peças compatíveis, como as
    duas ficam depois da troca e o custo; sempre pede um segundo clique.
- **Item de subir de torre** (decisões do designer; **entra com a Torre 2**): item raro ou de evento, gasto na
  transferência, que libera passar o fortalecimento para uma peça de **torre mais alta**. Responde ao "o que fazer
  com o Gold investido quando o jogador muda de torre".
  - A peça que recebe fica **no máximo +7**. Se a origem passa disso (ex.: +9), o destino fica +7, a origem fica com o
    nível que o destino tinha e o resto se perde (a tela avisa antes; a alternativa é vender a peça). O +7 é o teto
    realista de cada torre; os +8 a +10 (97% do custo do +10) ficam na torre em que foram feitos.
  - **Gold igual ao da transferência de hoje:** 1 tentativa do maior nível, na base da torre de origem (+7 da Torre 1 =
    6.400: 7 a 9,5 runs da Torre 2, 1 a 3 runs da Torre 5). Quem limita é o item raro. Cada uso vale ~42 runs da torre
    nova (o +7 feito do zero lá).
  - Brecha aceita: levar um +7 da Torre 1 para a Torre 5 e vender lá rende ~6 runs da Torre 5 (renda ×2 por torre),
    bem menos que usar o item de verdade (42).
  - Descartados: só aceitar origem até +7; cobrar 1 tentativa na base da torre nova (~14 runs dela em qualquer salto);
    só o item, sem Gold; custo de fortalecer igual em todas as torres (na Torre 5 o +7 sairia por 3 a 8 runs e o
    fortalecimento deixaria de segurar o Gold).
- *Implementado:* janela da **Forja** (bigorna no lobby, tecla F / toque): à esquerda todas as peças da conta (as
  equipadas primeiro, marcadas com "E"); à direita a peça escolhida com o que dá agora e no próximo nível, a chance, o
  custo e o que acontece se falhar. As tentativas de +8 a +10 (as que podem tirar um nível) pedem um segundo clique.
  O "+N" aparece no canto da peça na Forja e no painel Personagem. O servidor sorteia e cobra; o Gold gasto e o novo
  nível são salvos poucos segundos depois da última tentativa.

### Gemas
- **1 gema por peça.** Níveis **1 a 5** = **1 a 5 pontos** no atributo da gema (gema nível 1 = 1 ponto).
- **Nível 1: só na loja**, **1.000 Gold** (todos os tipos custam o mesmo). Ajuda nas runs iniciais; nas torres
  intermediárias e avançadas (mais difíceis) quase não faz diferença, de propósito.
- **Nível 2 a 5: só drop do chefão** (a loja não vende), com **atributo sorteado** entre **6 tipos** (não existe gema
  de Sorte, combinando com "Sorte só nos acessórios").
- **Um sorteio de gema por chefão vencido**, por jogador (loot individual), além do item garantido. Cai **no máximo
  1 gema**; run perdida não sorteia. Avançado e Pesadelo existem nas **torres 6 a 10**.

| Torre | Normal | Avançado | Pesadelo (sempre cai gema) |
|---|---|---|---|
| 1 a 4 | — | — | — |
| 5 | Nv2 25% | — | — |
| 6 | Nv2 25% | Nv2 80% · Nv4 2% | Nv5 1% · Nv4 2% · Nv2 97% |
| 7 | Nv3 25% · Nv2 15% | Nv3 80% · Nv4 4% | Nv5 2% · Nv4 4% · Nv3 94% |
| 8 | Nv3 25% · Nv2 15% | Nv3 80% · Nv4 6% | Nv5 3% · Nv4 6% · Nv3 91% |
| 9 | Nv3 35% · Nv2 15% | Nv3 80% · Nv4 8% | Nv5 4% · Nv4 8% · Nv3 88% |
| 10 | Nv3 35% · Nv2 15% | Nv3 80% · Nv4 10% | Nv5 5% · Nv4 10% · Nv3 85% |

  - **Gema da torre:** Nv2 nas torres 5 e 6; Nv3 nas torres 7 a 10. O Normal das torres 7 a 10 também dá Nv2 (15%,
    no mesmo sorteio), que serve para a fusão 2→3 e para os outros personagens da conta.
  - **Avançado:** a gema da torre cai 80% das vezes, mais a chance de Nv4. **Pesadelo:** sempre cai gema; o Nv4 é o
    mesmo do Avançado, mais o Nv5, que vêm no lugar da gema da torre.
  - **Nv4 e Nv5 crescem com a torre:** Nv4 = 2% × (torre − 5); Nv5 = 1% × (torre − 5). Os 10% (Nv4) e 5% (Nv5) do
    designer valem na torre 10. Com chance fixa, a torre 6 (a mais fácil) seria o melhor lugar para caçar Nv5 (um
    grupo forte ganharia 2,25× mais Nv5 lá); com a rampa, as torres 6 e 7 nunca superam a 10, a 8 só com 67% de
    vitórias e a 9 com 50%.
  - **A Sorte do grupo multiplica as chances de gema** (regra dos achados raros: maior Sorte do grupo por perto),
    nunca passando de 100%.
- **Ritmo de referência** (solo; runs de 18 min; vitória em 90% no Normal, 70% no Avançado e 40% no Pesadelo;
  "atributo certo" = um dos 2 atributos que o personagem quer):

| Marco | Tempo (solo) | Com Sorte 50 no grupo |
|---|---|---|
| 1ª Nv2 | 1,3 h | 0,7 h |
| 7 Nv2 do atributo certo | 28 h (Normal), 11 h (Avançado) | 14 h (Normal) |
| 7 Nv3 do atributo certo | 25 h (torre 7 Normal), 19 h (torre 9 Normal), 11 h (Avançado) | — |
| 1ª Nv4 do atributo certo | 13 h (torre 10 Avançado) | — |
| 1ª Nv5 de qualquer atributo | 14 h (torre 10 Pesadelo) | — |
| 1ª Nv5 do atributo certo | 36 h | 18 h |
| 7 Nv5 do atributo certo | ~200 h | ~100 h |

  - Descartado: 10% no Normal (1ª Nv2 em 3,3 h, metade dos jogadores sem nenhuma após 7 runs, 7 Nv2 certas em 70 h).
- **Incrustar** (na Forja): ~**500 Gold** por gema.
- **Fundir** (na Forja): **3 gemas iguais** (mesmo nível e mesmo atributo) viram **1 do nível seguinte**, com o mesmo
  atributo. Uma gema encaixada precisa ser extraída antes.
  - Fusões que existem: **2→3** (200 Gold) e **4→5** (2.000 Gold). A 4→5 é o caminho lento para o Nv5 (~53 h para
    a 1ª do atributo certo só com o Avançado da torre 10).
  - **A gema da loja (Nv1) não funde** e **não existe a fusão 3→4.** Assim o Gold compra só o Nv1, o Nv4 só vem do
    chefão (Avançado/Pesadelo) e o Nv5 do Pesadelo ou de 3 Nv4 iguais.
  - Descartado: fundir tudo, inclusive gemas da loja. O Gold compraria qualquer nível: uma Nv5 sairia de 81 gemas da
    loja por ~89 mil Gold (~5 runs Normal da torre 10, na hipótese de renda mais baixa), contra ~36 h de Pesadelo
    pelo drop; exigir 5 gemas por fusão também não resolvia. Com a 3→4, o Normal da torre 10 faria Nv4 mais rápido
    (~11 h) que o drop do Avançado (~13 h).
- **Extração** (na Forja): gasta um **Removedor do mesmo nível da gema**, vendido **só na loja**:

| Removedor | Nv 1 | Nv 2 | Nv 3 | Nv 4 | Nv 5 |
|---|---|---|---|---|---|
| Gold | 100 | 200 | 400 | 800 | 2.000 |

- A gema extraída sai **inteira** e pode ir para qualquer equipamento do personagem ou da conta. **Intenção:** o
  jogador pensa a build antes de encaixar (errar custa Gold), mas tem liberdade total para colocar a gema onde achar
  melhor.
- **Onde ficam (decisão do designer): no baú de 50.** Gemas soltas e Removedores empilham por tipo (atributo + nível;
  Removedor por nível) e **cada pilha ocupa 1 espaço** do baú (máximo de 99 por pilha, trava técnica). Com o baú
  cheio, a loja não vende um tipo novo, a extração e a fusão que criariam uma pilha nova são recusadas; somar a uma
  pilha que já existe continua permitido. Aparecem na mochila do painel Personagem.
  - Descartados: bolsa à parte (sem limite de espaços) e bolsa com espaços próprios.
- **Peça com gema não é vendida** (decisão do designer), como a fortalecida: extraia antes (com Removedor).
  - Descartados: a gema voltar de graça na venda (todo mundo venderia a peça velha para tirar a gema sem Removedor,
    100 Gold no Nv1 e 2.000 no Nv5) e a gema sumir junto (perder uma gema cara num clique).
- **Removedores na loja hoje: só o Nv1** (decisão do designer). Os Nv2 a Nv5 entram junto com as gemas Nv2+ (torres
  5+); antes disso o jogador gastaria Gold num item sem uso.
- **Sobras (decisão do designer):** gemas e Removedores são vendidos na loja **a 10%**: gema = **100 Gold por nível**
  (Nv1 = 100, Nv5 = 500), Removedor = 10% do preço (Nv1 = 10, Nv5 = 200). Um por clique; gema Nv2+ pede confirmação
  (vale mais do que a venda paga). Vender rende sempre bem menos que comprar: não vira fonte de Gold. Também dá para
  destruir a pilha inteira (arrastar para fora da mochila).
  - Descartados: 5% (Nv1 = 50) e 10 Gold fixo (uma Nv5 valeria o mesmo que uma Nv1).
- **Gema do chefão com o baú cheio** (torres 5+; decisão do designer): **vira Gold** pelo preço de venda, com o aviso
  de baú cheio, igual à peça de equipamento.
  - Descartados: ficar guardada esperando espaço (mais um lugar para as coisas se acumularem) e se perder (uma Nv5
    perdida são ~36 h de Pesadelo).
- *Implementado:* incrustar custa **500 Gold** (qualquer nível); para trocar a gema de uma peça, extraia antes. O
  fortalecimento **não** multiplica a gema (cada + dá 10% dos atributos **base** da peça). Como o equipamento, a gema
  soma por fora dos pontos distribuídos e vale 1,5× num atributo de scaling da classe.

### Forja (no lobby)
- **Funções do início:** **incrustar gemas** (~500 Gold), **fundir gemas**, **fortalecimento** e **extração de
  gemas** (com Removedor).
- *Implementado:* bigorna atrás da loja (mesmo lado), com as abas **Fortalecer**, **Transferir** (trocar o
  fortalecimento de duas peças), **Gemas** (incrustar uma gema do baú na peça escolhida, ou extrair a que está nela) e
  **Fundir** (as gemas do baú; 3 iguais viram 1 do nível seguinte). A gema encaixada aparece como um quadradinho da cor do atributo, com o nível, no canto da peça. Fica
  longe o bastante da loja para as duas janelas não abrirem juntas.
- *Futuro:* fabricação (receitas e fragmentos) e **encantamento** (boost de atributo no equipamento).

### A definir
- Como se obtém o Berserker; em que torres caem as armas intermediárias e avançadas (fora o Soco Inglês do
  protótipo).
- Itens de bênção e pedra de fortalecimento: se entram, quanto somam e como se obtêm (adiados; análise em
  "Fortalecimento").
- Item de subir de torre (com a renda da Torre 2): nome, de onde vem (drop raro, evento; compra com Robux foi
  cogitada) e a chance de drop. Um conjunto de 7 peças pede 7 itens por troca de torre.
- Gemas, para quando as torres 5 a 10 forem construídas:
  - um **teto para a Sorte** nos achados (hoje um único personagem com muita Sorte multiplica os drops do grupo
    inteiro; ex.: Sorte 300 = chances ×7);
  - nível mínimo para usar cada gema;
  - quem entra no meio da run sorteia gema do chefão? (o item garantido já segue a regra: só quem entrou antes do
    andar do chefe);
  - a renda de Gold das torres 2 a 10 e os multiplicadores dos modos (as contas usaram hipóteses).
- O custo de incrustar é o mesmo (500 Gold) em todo nível de gema; rever quando existirem as gemas Nv2+ e a renda das
  torres 5+.

### Ordem de construção
1. ~~Baú da conta, 7 slots, equipar e drop do boss (atributos somando).~~ **Feito** (mais o drop dos mobs, a venda
   na loja e o painel Personagem).
2. ~~Forja no lobby + fortalecimento.~~ **Feito** (sem itens de bênção, adiados).
3. ~~Gemas: nível 1 e removedores na loja; incrustar, fundir e extrair na Forja.~~ **Feito** (a fusão só tem gemas
   para fundir quando existirem as torres 5+; até lá, testar com o DevService: "GiveGems").
4. Com a Torre 2: o item de subir de torre (ver "Fortalecimento").
5. Depois: fabricação (depende dos modos Avançado e Pesadelo) e encantamento.

## Dificuldades (futuro)

- Modos **Normal**, **Avançado** e **Pesadelo**. Avançado e Pesadelo existem só nas **últimas 5 torres: 6 a 10**
  (decisão do designer). O que cada modo dá em gemas: "Equipamentos > Gemas".
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
