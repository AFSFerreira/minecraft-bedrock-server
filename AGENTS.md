# AGENTS.md — contexto operacional deste servidor

Este arquivo existe para qualquer agente (ou humano) que for mexer neste projeto depois.
Contém as decisões, gotchas e procedimentos exatos usados até agora. Leia antes de rodar
qualquer `docker compose` ou `docker restart` aqui.

## O que é isto

Servidor Minecraft Bedrock Dedicated Server rodando em Docker (`itzg/minecraft-bedrock-server`),
exposto pra internet via túnel UDP do playit.gg (`ghcr.io/playit-cloud/playit-agent`), sem
necessidade de abrir porta no roteador.

Arquivos:
- `docker-compose.yml` — as duas services (`bedrock`, `playit`)
- `.env` — contém `PLAYIT_SECRET_KEY` (não versionar, não compartilhar; **não existe** um `.env`
  de exemplo funcional, use `.env.example` como template)
- `data/` — bind mount completo do `/data` do container. É o estado inteiro do servidor:
  mundo, packs, `server.properties`, allowlist etc. Copiável/portável (ver seção Backup).

## REGRA DE OURO: ordem de restart entre `bedrock` e `playit`

O `playit` usa `network_mode: "service:bedrock"` (compartilha a network namespace do
`bedrock` em vez de ter a própria). Isso significa:

**Toda vez que o container `bedrock` for reiniciado ou recriado, por QUALQUER motivo
(mudança de env var, restart pra carregar um addon novo, reset de mundo, etc.), o
`playit` fica órfão e para de funcionar** — os logs mostram `NetworkUnreachable` e
`failed to lookup address information` em loop.

**Correção**: sempre rodar, como ÚLTIMO passo depois de qualquer restart/recreate do
`bedrock`:
```bash
docker compose up -d --force-recreate playit
```
Nunca na ordem inversa. Se dois restarts do `bedrock` acontecerem em sequência, só recrie
o `playit` depois do último.

Como verificar que voltou:
```bash
docker logs playit-agent --tail 10
# procurar: "playit connected; tunnels loaded" com tunnel_count=1 e account_status="verified"
```
Erros de `NetworkUnreachable`/reconnect nos primeiros ~5s são normais (handshake inicial via
IPv6 falha e cai pra IPv4); só é problema se continuar em loop depois de 10s.

## Enviar comandos de console pro servidor (gamerule, difficulty, etc.)

O script `send-command` que vem na imagem **não funciona neste ambiente**: ele tenta ler
`/proc/<pid>/exe` de outros processos pra achar o `bedrock_server`, e isso dá "Permission
denied" mesmo como root (o sandbox onde isso roda bloqueia esse tipo de introspecção via
/proc, possivelmente por falta de `CAP_SYS_PTRACE`).

**Workaround que funciona**: usar `docker attach` através de um pty falso (via `script`),
porque anexar direto (`docker attach` puro com stdin de pipe) falha com
"cannot attach stdin to a TTY-enabled container because stdin is not a terminal":

```bash
printf 'gamerule keepinventory true\n' | timeout 5 script -qc "docker attach minecraft-bedrock" /dev/null
```

Pode mandar múltiplos comandos de uma vez (um por linha no `printf`). Confirme no log:
```bash
docker logs minecraft-bedrock --tail 5
```
(Nem toda gamerule imprime confirmação no log — `difficulty` e `keepinventory` imprimem,
`showcoordinates` não imprimeu na prática, mas o valor fica gravado no `level.dat` mesmo assim;
confira lendo o NBT bruto se precisar ter certeza: `strings "data/worlds/Bedrock level/level.dat" | grep nome_da_rule`.)

## Como instalar um addon (.mcpack / .mcaddon)

Não existe variável de ambiente pra gamerules nem um "instalador" mágico — o processo manual é:

1. **Copiar o arquivo original pra `addons/`** (na raiz do projeto, não em `data/`) antes de
   mexer em qualquer coisa — é o histórico/fonte, versionado no git, útil pra reinstalar do
   zero ou mandar pra outra pessoa sem precisar zipar a pasta extraída de novo.
   ```bash
   cp "/caminho/do/arquivo/baixado.mcaddon" addons/
   ```
2. Extrair o arquivo (`.mcpack`/`.mcaddon` são só `.zip` renomeados):
   `unzip -o arquivo.mcpack -d pasta_destino`
3. Ler o(s) `manifest.json` pra pegar `header.uuid` e `header.version` de cada módulo
   (resource pack e/ou behavior pack costumam vir juntos em `.mcaddon`, separados em pastas).
4. **Antes de instalar, checar sanidade**: procurar por `type: "script"` nos `modules` do
   manifest — se tiver, confirme que o arquivo apontado em `entry` realmente existe no zip
   (já aconteceu de um addon (`sanrioverse_by_emobunny.mcaddon`) declarar um módulo de script
   sem incluir o arquivo — nesse caso, **removi o módulo `script` e as dependências
   `@minecraft/server*` do manifesto da cópia instalada** pra evitar rejeição de validação).
   Também vale dar uma lida nos `.js` procurando `fetch|http|eval|Function(|XMLHttpRequest|
   WebSocket|require(` antes de instalar — nenhum addon instalado até agora tinha nada disso.
5. Copiar a pasta extraída pra `data/resource_packs/<Nome>` e/ou `data/behavior_packs/<Nome>`.
6. Registrar no mundo atual, adicionando uma entrada em
   `data/worlds/Bedrock level/world_resource_packs.json` e/ou `world_behavior_packs.json`:
   ```json
   { "pack_id": "<header.uuid>", "version": [x, y, z] }
   ```
   (esses arquivos não existem por padrão — criar se for o primeiro pack daquele tipo.)
   Pra forçar uma **subpack** específica (variantes de resolução/qualidade que normalmente o
   jogador escolhe na UI), adicionar `"subpack": "<folder_name>"` na mesma entrada — os nomes
   de subpack ficam no array `subpacks` do `manifest.json` do resource pack.
7. `docker restart minecraft-bedrock`, conferir `docker logs minecraft-bedrock | grep "Pack Stack"`
   pra confirmar que carregou sem erro.
8. **Recriar o `playit` por último** (regra de ouro acima).

Pra resetar/regenerar o mundo mantendo os packs: faça backup dos dois JSONs acima antes de
apagar `data/worlds/Bedrock level`, e restaure-os depois que o mundo novo for criado (mais um
restart do `bedrock` é necessário pra ele reler os JSONs restaurados).

## Estado atual do mundo

- **Nome do nível**: `Bedrock level` (LEVEL_NAME padrão, não sobrescrito)
- **Seed**: `5480987504042101543` (fixada via `LEVEL_SEED` no compose — resetar o mundo com
  `rm -rf "data/worlds/Bedrock level"` + restart gera o mesmo terreno de novo, já que a seed
  vem do env var, não do save)
- **Gamerules setadas manualmente** (não vêm de env var, **se perdem se o mundo for apagado**,
  precisam ser reaplicadas depois de qualquer reset):
  - `keepinventory true`
  - `showcoordinates true`
- **Dificuldade / gamemode**: vêm do `docker-compose.yml` (`DIFFICULTY`, `GAMEMODE`), aplicados
  a cada boot independente do estado do save — não precisam ser reaplicados manualmente.

## Packs instalados (nomes de pasta em `data/resource_packs/` e `data/behavior_packs/`)

| Pasta | RP | BP | UUID header (RP / BP) | Observação |
|---|---|---|---|---|
| ActionsAndStuff | ✅ | — | `2cf066eb-1254-4b7d-affb-80fe3216b18c` | subpack forçada: `2_e` (Full Experience) |
| RefinedCats | ✅ | — | `4b95ba23-32cc-4282-bcbd-3c8b68e396ef` | |
| Sanrioverse | ✅ | ✅ | RP `925769a3-2262-4ca4-8df5-5e547e79f56b` / BP `0c3b0e34-19d3-4a64-ba45-7a362d403678` | manifest do BP corrigido (script module removido, arquivo não existia no zip original) |
| MailPigeons | ✅ | ✅ | RP `edc335f1-047d-42ea-ae2b-092e2f94c898` / BP `3d387c8d-1b8c-4350-b028-4e10348c74dd` | usa Script API (mecânica de pombo-correio) |
| ChikawaMob | ✅ | ✅ | RP `0c7ae96a-863e-4c61-a410-57c6b1682b4a` / BP `62e47932-8e5c-45e7-8c2c-4df7287a8ebb` | usa Script API (chatbot com respostas fixas, sem rede) |
| DynamicLight | ✅ | ✅ | RP `fa2c32a5-7d57-4a2c-8f18-14abf087a6f0` / BP `4d9a3cb8-4ef2-4629-bfc7-f79b021687c2` | só `.mcfunction`, sem Script API |
| DarkAgeBizarre | ✅ | ✅ | RP `efbd5d95-351b-4dac-8691-18ac435b72b3` / BP `74e7080a-e27a-4f57-819c-1858c3338b57` | addon grande (JoJo's Bizarre Adventure), usa Script API |

Ordem completa e atualizada de cada `world_resource_packs.json` / `world_behavior_packs.json`
está nos próprios arquivos — essa tabela é só referência de UUID pra não precisar reabrir cada
`manifest.json` de novo.

## Túnel (playit.gg)

- Endereço público atual: `schmidt-diploma.tun.ply.gg:64625` (IP cru equivalente:
  `147.185.221.213:64625`) — pode mudar se o túnel for recriado no dashboard.
- Tipo de túnel: Minecraft Bedrock (UDP), criado manualmente no dashboard do playit.gg
  (conta pessoal do usuário — eu não tenho acesso a esse painel).
- `PLAYIT_SECRET_KEY` fica só em `.env`, nunca commitar.

## Versionamento (git)

Repositório privado — decisão consciente de versionar o mundo salvo (`data/worlds/`) junto,
como forma de backup, já que não há problema de privacidade num repo privado.

`.gitignore` mantém de fora:
- `.env` (segredo do playit.gg — isso vale independente do repo ser privado ou não, é uma
  credencial viva, não um dado pessoal)
- todo o resto de `data/` (conteúdo padrão da engine tipo `vanilla_*`/`chemistry_*`/
  `experimental_*`, mais as cópias já extraídas dos addons em `resource_packs/`/
  `behavior_packs/` — redundantes, já que `addons/` guarda os arquivos originais)

O que fica versionado: `docker-compose.yml`, `.env.example`, `AGENTS.md`, `README.md`,
`addons/` (fontes originais dos addons) e `data/worlds/` (o save do mundo).

**Cuidado ao commitar o mundo**: o save usa LevelDB (ver explicação em conversas anteriores,
não repetida aqui) — commitar com o servidor rodando pode pegar um estado inconsistente entre
o WAL e as SSTables. Prefira `docker compose stop bedrock` antes de um `git add data/worlds/`
+ commit, e subir de novo depois (`docker compose up -d`, seguido de recriar o `playit` por
último, regra de ouro no topo deste arquivo).

## Backup / migração

`data/` é um bind mount comum, não named volume — é portável. Pra mover pra outra máquina:
```bash
docker compose down          # importante: parar antes de copiar (LevelDB não gosta de cópia "quente")
tar -czf backup.tar.gz -C ~/minecraft-bedrock data docker-compose.yml .env
```
Extrair no destino, `docker compose up -d` (com Docker instalado). O playit-agent não está preso
à máquina, só precisa do mesmo `.env`.
