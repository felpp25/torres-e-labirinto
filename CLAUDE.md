# Torres dos Labirintos

RPG cooperativo de runs com labirintos, feito no Roblox.
**Antes de qualquer decisão de gameplay, consulte [docs/GDD-resumo.md](docs/GDD-resumo.md)** (resumo do design).
Se o design não cobrir algo, pergunte em vez de inventar.

## Stack

| Ferramenta | Versão | Papel |
|---|---|---|
| Luau (`--!strict`) | – | Linguagem. Sem roblox-ts. |
| Rokit | 1.2.0 | Gerenciador de toolchain. Versões fixadas em `rokit.toml`. |
| Rojo | 7.7.1 | Sincroniza `src/` (disco) → Roblox Studio. |
| StyLua | 2.6.0 | Formatação (`stylua.toml`). |
| Selene | 0.32.0 | Lint (`selene.toml`, `std = "roblox"`). |
| luau-lsp | 1.70.1 | Tipos: extensão do VS Code (editor) + CLI no Rokit (`scripts/analyze.ps1`, projeto inteiro). |

Ambiente: **Windows nativo** (PowerShell). O Roblox Studio e o Claude Code rodam no mesmo SO, sem WSL.

## Comandos do dia a dia (na raiz do projeto)

```powershell
rokit install                     # instala as ferramentas do rokit.toml (clone novo / outra máquina)
rojo serve                        # sync ao vivo; no Studio: plugin Rojo > Connect
stylua src                        # formata
stylua --check src                # só verifica (CI / antes do commit)
selene src                        # lint
./scripts/analyze.ps1             # checagem de tipos do projeto inteiro (luau-lsp analyze); exit 0 = sem erros
rojo sourcemap default.project.json -o sourcemap.json   # sourcemap manual (o luau-lsp já gera sozinho)
rojo build -o build/place.rbxl    # gera um place offline (build/ fica fora do git)
```

## Estrutura

```
src/
  server/   -> ServerScriptService            (scripts do servidor)
  client/   -> StarterPlayer/StarterPlayerScripts (scripts do cliente)
  shared/   -> ReplicatedStorage/Shared        (módulos usados pelos dois lados)
    Types.luau      tipos compartilhados
    Balance/        TODOS os números de balanceamento (combate, classes, habilidades, mobs, progressão, andares,
                    equipamentos: Balance/Gear, forja/fortalecimento: Balance/Forge, gemas: Balance/Gems)
    Formulas.luau   fórmulas puras (dano, defesa, crítico, XP...): servidor decide, cliente só mostra
    Remotes.luau    RemoteEvents com nome tipado (servidor cria; cliente espera)
    GearInfo.luau / GearSnapshot.luau  textos das peças e gemas e o formato do Attribute GearData (peças, slots e
                    as pilhas de gemas e Removedores do baú)
  server/Main.server.luau   bootstrap: init() de todos os serviços, depois start()
  server/Services/          um serviço por sistema (combate, inimigos, boss, andares, puzzle, run, vida,
                            equipamento = GearService, gemas = GemService, forja = ForgeService...)
  server/Dungeon/           MazeGenerator (layout puro por seed) e RoomBuilder (peças)
  server/Enemies/           EnemyFactory (modelo greybox) e Telegraph (avisos de ataque e quem é atingido)
  client/Main.client.luau   bootstrap dos controllers (mesmo padrão)
default.project.json  mapeamento acima (Rojo)
```

Números de balanceamento ficam só em `src/shared/Balance/`, nunca espalhados pelo código.

Convenção de nomes do Rojo (o sufixo define a classe da instância):

| Arquivo | Instância no Studio |
|---|---|
| `Nome.server.luau` | `Script` (roda no servidor) |
| `Nome.client.luau` | `LocalScript` (roda no cliente) |
| `Nome.luau` | `ModuleScript` (só roda quando alguém dá `require`) |
| `pasta/init.luau` | a própria pasta vira um `ModuleScript` |

Requires: no servidor, `require(ReplicatedStorage.Shared.X)`. No cliente, use
`ReplicatedStorage:WaitForChild("Shared"):WaitForChild("X")`, porque a replicação pode ainda não ter terminado.

## REGRAS PERMANENTES

a) **Os arquivos em `src/` são a fonte da verdade.** NUNCA editar scripts direto no Studio, nem pelo MCP:
   o Rojo sobrescreve. Código se escreve nos arquivos.

b) **O MCP do Roblox Studio (`Roblox_Studio`) serve para:** rodar playtests, ler o console, inspecionar a árvore
   do jogo, executar Luau de diagnóstico e montar o mundo (peças, modelos, assets). **Nunca** para criar ou
   alterar scripts.

c) **O servidor tem autoridade.** Dano, XP, drops, Gold e inventário são decididos só no servidor. O cliente só
   envia intenções e mostra resultados. Todo `RemoteEvent`/`RemoteFunction` é validado no servidor (tipo,
   faixa de valores, distância, cooldown, se o jogador pode fazer aquilo).

d) **Todo arquivo `.luau` começa com `--!strict`**, com tipos explícitos em funções públicas.

e) **Depois de mudar código:** `stylua src` → `selene src` → `./scripts/analyze.ps1` (zero erros nos três) →
   playtest pelo MCP → checar o console.

f) **Commits pequenos**, no padrão Conventional Commits (`feat:`, `fix:`, `chore:`, `refactor:`, `docs:`, `test:`).

g) **Anote o tipo dos serviços:** `local Players: Players = game:GetService("Players")`. Sem a anotação, o
   luau-lsp infere `any` e deixa passar erros como `Players.LocalPlayer.Nome` (validado no setup).

## Fluxo com o MCP do Studio

- Antes de usar o MCP: `rojo serve` rodando **e** plugin Rojo > Connect no Studio. Sem o Connect, o Studio não
  tem os scripts (`ServerScriptService`/`ReplicatedStorage` vazios) mesmo com o servidor no ar.
- Toda ferramenta pede `studio_id`: obtenha com `list_roblox_studios`.
- Playtest: `start_stop_play(true)` → `get_console_output` → `start_stop_play(false)`.
- Conferir a sincronização sem playtest: `script_read` no caminho da instância (ex.: `game.ReplicatedStorage.Shared.Config`).
- `save_place` só funciona depois que o place foi salvo uma vez manualmente (Arquivo > Salvar no Roblox / em arquivo).
  Cada `save_place` cria uma versão no histórico do place: use só quando fizer sentido, não a cada edição.
- O place está na nuvem: **"Torres e Labirinto"**, placeId `91794479071367`, universeId `10776412975`
  (o `save_place` reporta `location: TeamCreate`).
- O `studio_id` muda quando o place é salvo/reaberto: sempre chame `list_roblox_studios` de novo em vez de reutilizar um id antigo.
- Ruído conhecido no console (não é do nosso código): `ContentId: rbxassetid://203785492 failed ... Asset type does
  not match` (modelo Baseplate) e mensagens `[Assistant] ...` (plugin do Assistente do Studio).
- O `rojo serve` 7.7.1 pode travar no Windows ao substituir um arquivo inteiro (`Rojo crashed! ... NotFound ...
  change_processor.rs`). Sintoma: arquivos novos não aparecem no Studio. Solução: reiniciar o `rojo serve` e clicar
  de novo em Rojo > Connect no Studio (o plugin não reconecta sozinho).
- **SEMPRE, no início de todo teste, confira o modo com `list_roblox_studios`.** Se o Studio estiver em Play, pode
  ser o USUÁRIO jogando: não rode nada nessa sessão (um teste já matou o personagem dele e apagou o progresso).
  Peça para ele parar o Play. Além disso, `start_stop_play(true)` com o Studio já em Play não reinicia: o teste
  rodaria o código ANTIGO.
- Antes de dar Play depois de mudar arquivos (inclusive depois do `stylua src`, que reescreve arquivos), confira
  que o Rojo já sincronizou: `execute_luau` no datamodel `Edit` procurando um trecho novo no `.Source` do script.
  Um Play iniciado antes da sincronização roda a versão antiga (aconteceu no M4: HUD "sumido").
- No datamodel `Edit`, `require` fica em CACHE: depois de mudar um módulo já carregado num teste anterior, o
  `require` devolve a versão VELHA. Para testar a nova: `local c = mod:Clone(); c.Parent = mod.Parent;
  local M = require(c); c:Destroy()`.
- **Fluxo do jogo:** o jogador nasce no LOBBY (perto da origem; loja à esquerda com a forja atrás dela, portal da
  torre à direita). Para
  testar a torre pelo MCP: levar o personagem até `workspace.Lobby.TowerPortal` (a run começa) ou usar
  `Players:GetPlayers()[1]:GetAttribute("InRun")` para saber onde ele está. Game over / torre concluída = lobby.
- **Salvamento (DataService):** no Studio usa o DataStore `PlayerData_Studio` (separado do jogo publicado,
  `PlayerData`). Precisa de "Enable Studio Access to API Services" ligado (Configurações da Experiência >
  Segurança; já ligado). Sem acesso, o jogo roda "sem salvar" (aviso no HUD) e nunca grava. O personagem de teste
  do Studio agora PERSISTE entre Plays (nível, Gold, atributos). Formato e validação: `server/Data/PlayerSchema`.
  - Formato **v4**: peças de equipamento da conta (`gear`) + 7 slots por personagem (`equipped`); a migração deu a
    arma inicial equipada (Lutador: Luvas de Couro). **Não rode commits anteriores ao v4** (antes de `ea69b36`)
    contra o `PlayerData_Studio`: o código antigo apagaria o equipamento ao carregar.
  - Formato **v5**: fortalecimento de cada peça (`enhance`, 0 a 10). Um servidor v4 que encontra dados v5 recusa
    carregar (joga "sem salvar") e não apaga nada.
  - Formato **v6**: gema encaixada na peça (`gem`) e as pilhas do baú (`gems` com chave `"Strength:1"`, `removers`
    com chave `"1"`: texto de propósito, chave numérica viraria lista no JSON). Cada pilha ocupa 1 espaço do baú.
  - **Todo campo novo salvo aumenta `PlayerSchema.VERSION`** (mesmo opcional), e também todo valor novo num campo
    validado (ex.: raridade "Epic"). O servidor que acha dados de versão maior recusa carregar (joga "sem salvar")
    em vez de apagar o que não conhece.
  - **Ao publicar um VERSION novo: fechar os servidores antigos** ("Shut Down All Servers" ou "Migrate to Latest
    Update" no Creator Hub). Servidores v3 não têm a proteção e apagariam o equipamento de quem entrasse neles.
- **Ferramentas de teste (DevService, só no Studio):** no datamodel `Server`,
  `game.ServerStorage.DevTools.Invoke:Invoke("SetAttributes", player, { Defense = 100 })` e
  `...:Invoke("DamagePlayer", player, 13.8)` (devolve o dano aplicado) usam os sistemas REAIS do jogo.
  `"GiveGold"(player, n)` para testar a loja; `"SetResource"(player, "Stamina"|"Mana", n)` e
  `"SetUltimate"(player, 0-100)` para testar habilidades.
  Salvamento: `"SaveNow"(player)`, `"ReadStored"("User_<id>")` (JSON cru); testes de trava só em chaves
  `Test_...`: `"WriteStored"`, `"LoadKey"`, `"SaveKey"`, `"SessionId"`.
  Atributos e dano: `"GetStats"(player)` (distribuídos, equipamento, efetivos, Poder, máximos) e
  `"DamagePreview"(player, 100)` (dano real de um golpe base 100, sem crítico e sem a Defesa do alvo).
  Equipamento: `"ListGear"`, `"GiveGear"(player, defId, "Rare")`, `"FillChest"(player, n, defId?, raridade?)`,
  `"Equip"(player, id)`, `"Unequip"(player, slot)`. Drops: `"SampleDrops"`, `"SampleLoot"`, `"RollBossLoot"`,
  `"ForceMobDrop"`, `"GoToFloor"(n)` (numa run ativa), `"RejoinRun"`, `"BossEligible"`.
  Forja: `"Enhance"(player, id, forçar?)` (tentativa real, cobra Gold; `true`/`false` fixa o sorteio) e
  `"SetEnhance"(player, id, nível)` (direto, sem custo). `"TransferEnhance"(player, deId, paraId)` (troca real dos
  níveis, cobra Gold).
  Gemas (regras reais, sem distância): `"BuyGem"(player, "Strength")`, `"BuyRemover"(player, nível)`,
  `"SocketGem"(player, id, atributo, nível)`, `"ExtractGem"(player, id)`, `"FuseGems"(player, atributo, nível)`; sem
  custo: `"GiveGems"(player, atributo, nível, n)` (qualquer nível: as Nv2+ ainda não caem) e
  `"GiveRemovers"(player, nível, n)`. Sobras: `"SellGem"(player, atributo, nível)`, `"SellRemover"(player, nível)`.
  Destruir (o que o arrastar para fora da mochila pede): `"DestroyGear"(player, id)`, `"DestroyGems"(player,
  atributo, nível)` e `"DestroyRemovers"(player, nível)` (pilha inteira).
  **Testes que mexem no personagem: `"SnapshotProfile"(player)` no início e `"RestoreProfile"(player)` +
  `"SaveNow"` no fim** (devolve Gold, itens, equipamento e atributos; o personagem de teste é o save do usuário).
  O snapshot vive só na sessão de Play em que foi feito: teste que PARA e reinicia o Play (ex.: conferir o que foi
  salvo) faz antes um backup com `"ReadStored"` e no fim `"RestoreFromJson"(player, json)` + `"SaveNow"`. Gravar o
  DataStore direto pelo datamodel `Edit` não funciona (ler sim; gravar dá "Access forbidden").
  Fora do Studio o serviço não faz nada. Novos comandos de teste entram em `COMMANDS` no DevService.
- `execute_luau` NÃO compartilha os módulos do jogo: `require` de um serviço ali devolve uma cópia nova (estado
  vazio). Para testar, provoque o efeito pelo próprio jogo (ex.: `Humanoid.Health = 0` num mob dispara a
  recompensa real) e leia o resultado por Attributes/instâncias.
- Teste com 2+ jogadores: o usuário escolhe "Server & Clients" no menu ao lado do Play (barra de cima, à esquerda),
  2 clientes, Play/F7; "End Session" em qualquer janela fecha tudo (depois voltar o menu para "Test").
  Pelo MCP cada janela é um `studio_id` (sem nome); `get_studio_state` diz qual tem o foco em `Server` (servidor) e
  quais em `Client` (jogadores). Rode as chamadas UMA POR VEZ (em paralelo elas se atropelam) e, para testes de
  regras, limpe os mobs do andar no início (`Mobs:ClearAllChildren()`): personagens parados morrem entre chamadas.
- Testes pelo MCP: `character_navigation` leva o personagem; `user_mouse_input`/`user_keyboard_input` simulam o
  jogador; `execute_luau` no datamodel `Server` confere o resultado (vida, posição, Attributes).
- Interface: a janela de chat do Roblox (CoreGui) fica no canto inferior esquerdo e ENGOLE cliques da nossa UI ali
  (medido: botão sem `Activated`). Janelas grandes escondem o chat enquanto abertas (`client/ChatBlocker`). Crie
  ScreenGuis com `ZIndexBehavior = Sibling` (com Global, o fundo de uma janela de ZIndex maior cobre os próprios filhos).
- Balcões do lobby (loja, forja): cada janela fecha a `alcance + 6` studs do seu balcão. Balcão novo precisa ficar
  longe o bastante para duas janelas não abrirem juntas (medido: loja e forja a 22 studs abriam juntas; hoje 36).
- Botão com "Confirmar?" (janela de 3 s): no teste pelo MCP, os dois cliques vão na MESMA chamada do
  `user_mouse_input`; uma captura de tela entre eles passa dos 3 s e o segundo clique só pede confirmação de novo.
- Cliques do `user_mouse_input`: prefira `instance_path` (ex.: `LocalPlayer.PlayerGui.ShopGui.Panel.SellTab`). As
  coordenadas x/y não batem com as da `screen_capture` (medido: o clique caiu ~46 px abaixo, na linha seguinte).
  Item fora da área visível de um ScrollingFrame: role antes (`scrollDown` com o mouse sobre a lista).
- Arrastar (destruir da mochila): no `user_mouse_input`, `moveTo` com `instance_path` da célula + `mouseButtonDown`,
  dois `moveTo` com x/y (um perto, um bem fora da janela) e `mouseButtonUp`, na mesma chamada. Janelas se sobrepõem
  pela `DisplayOrder` (loja e forja 6 > Personagem 5 > HUD 0): feche a loja antes, senão a confirmação fica escondida
  atrás dela (os avisos do HUD também ficam atrás das janelas abertas).
- Texto cortado na interface: `execute_luau` no datamodel `Client` lendo `TextLabel.TextFits` acha o problema sem
  depender da captura de tela (achou o detalhe da peça com gema estourando a caixa no painel Personagem).
- Luau (verificador de tipos): local SEM anotação alarga união de literais para `string` (ex.: `local slot =
  def.slot` perde o `EquipSlot`; idem laço `for _, slot in Gear.slots`). Anote: `local slot: Types.EquipSlot = ...`,
  `for _, slot: Types.EquipSlot in ...`. Módulo que devolve tabela com campos desse tipo: declare o tipo do módulo.

## Lições de física do Roblox (medidas em playtest)

- NPC com Humanoid sem pernas: `HipHeight` precisa ser > 0. Com 0, o Humanoid fica em Freefall e desliza sem
  parar até cair do mapa. E o NPC só sobe degraus com altura <= `HipHeight` (usamos 1,2 + "pernas" decorativas
  sem colisão; com 0,5 ele travava na plataforma de spawn, de 1 stud).
- `Humanoid.MoveDirection` de NPC fica (0,0,0) no servidor mesmo andando: para saber se um mob se move, compare
  posições ao longo do tempo.
- Testes de combate pelo MCP: um teste controlado (cliente dispara o Remote, servidor mede) é mais confiável que
  mouse simulado, porque o jogador pode morrer/renascer ou estar de costas no meio do teste.
- Empurrão/dash: mudar `AssemblyLinearVelocity` não funciona em Humanoid (ele freia na hora). Use sempre
  `src/shared/Motion.luau` (`Motion.push`): `LinearVelocity` em modo Plano por um instante, com Spherecast para
  parar antes de paredes e força LIMITADA. Com `MaxForce = math.huge`, esquivar contra a parede arremessava o
  jogador (medido: 112 studs/s, 38 studs para trás).

## Notas de setup

- O `rokit add` pede confirmação interativa de "confiança". Em terminal não interativo, rode antes
  `rokit trust <owner/repo>`.
- Line endings: LF em tudo (`.gitattributes` + `line_endings = "Unix"` no StyLua). Sem isso, o git no Windows
  pode converter para CRLF e o `stylua --check` falha.
- `sourcemap.json` é gerado (luau-lsp/Rojo) e fica fora do git.
- Configuração do luau-lsp: a chave atual é `luau-lsp.studioPlugin.enabled` (`luau-lsp.plugin.enabled` está depreciada).
- O luau-lsp só mostra diagnósticos de arquivos **abertos** no editor.
- PATH: o Rokit instala em `%USERPROFILE%\.rokit\bin`. Terminais/VS Code abertos antes da instalação não enxergam
  `rojo`/`stylua`/`selene`: reinicie o VS Code.
- MCP do Studio (Windows nativo): o `%LOCALAPPDATA%\Roblox\mcp.bat` só é criado depois de ativar
  "Ativar o Studio como servidor MCP" (Assistente > Servidores MCP). Ele procura o `StudioMCP.exe` pelo registro,
  então sobrevive a atualizações do Studio. Registro (escopo de usuário):
  `claude mcp add --transport stdio --scope user Roblox_Studio -- "cmd.exe" "/c" "cd /d %LOCALAPPDATA%\Roblox && .\mcp.bat"`
- O CLI `claude` não fica no PATH quando se usa só a extensão do VS Code; o binário fica em
  `%USERPROFILE%\.vscode\extensions\anthropic.claude-code-<versão>-win32-x64\resources\native-binary\claude.exe`.
