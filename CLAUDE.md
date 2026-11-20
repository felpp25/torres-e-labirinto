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
    Balance/        TODOS os números de balanceamento (combate, classes, habilidades, mobs, progressão, andares)
    Formulas.luau   fórmulas puras (dano, defesa, crítico, XP...): servidor decide, cliente só mostra
    Remotes.luau    RemoteEvents com nome tipado (servidor cria; cliente espera)
  server/Main.server.luau   bootstrap: init() de todos os serviços, depois start()
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
- Testes pelo MCP: `character_navigation` leva o personagem; `user_mouse_input`/`user_keyboard_input` simulam o
  jogador; `execute_luau` no datamodel `Server` confere o resultado (vida, posição, Attributes).

## Lições de física do Roblox (medidas em playtest)

- NPC com Humanoid sem pernas: `HipHeight` precisa ser > 0. Com 0, o Humanoid fica em Freefall e desliza sem
  parar até cair do mapa. E o NPC só sobe degraus com altura <= `HipHeight` (usamos 1,2 + "pernas" decorativas
  sem colisão; com 0,5 ele travava na plataforma de spawn, de 1 stud).
- `Humanoid.MoveDirection` de NPC fica (0,0,0) no servidor mesmo andando: para saber se um mob se move, compare
  posições ao longo do tempo.
- Testes de combate pelo MCP: um teste controlado (cliente dispara o Remote, servidor mede) é mais confiável que
  mouse simulado, porque o jogador pode morrer/renascer ou estar de costas no meio do teste.
- Empurrão/dash: mudar `AssemblyLinearVelocity` não funciona em Humanoid (ele freia na hora). Use `LinearVelocity`
  em modo Plano por um instante (distância ≈ velocidade × duração).

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
