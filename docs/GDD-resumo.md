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
- Um **puzzle simples (30 a 90 s)** abre a escada para o próximo andar.
- **Todo puzzle precisa de versão solo.**

## Recompensas

- Mobs dão **XP e Gold**.
- **Loot individual** por jogador.

## Atributos

- Iguais para todas as classes: **Força, Agilidade, Inteligência, Vitalidade, Foco**.
- Cada classe tem **2 atributos com scaling extra**.
- **Fórmula de dano:** `Dano = Base × (1 + 0,02 × Atributo × M)`
  - `M = 1` para atributos comuns;
  - `M = 1,5` para os atributos de scaling da classe.
- **3 pontos de atributo por nível.**
- Botão **"distribuir recomendado"**: coloca os pontos nos atributos de scaling da classe.

## Habilidades

- O jogador equipa **3 habilidades + 1 ultimate**, escolhidas entre os "caminhos" da classe.

## Classes

### Monge (classe do protótipo)

- **Tema:** artes marciais e chi.
- **Papel:** linha de frente.
- **Scaling:** Força e Vitalidade.
- **Caminhos:** Punhos, Chi, Postura.

## Morte

- **Versão completa (NÃO implementada ainda):** perde a run e os itens da run; mantém nível e XP.
- **Protótipo:** morreu, renasce no início do andar.

## Regra técnica

- O servidor tem autoridade sobre tudo: dano, XP, Gold e drops.
