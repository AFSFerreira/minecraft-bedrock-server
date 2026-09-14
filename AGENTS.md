# AGENTS.md — contexto operacional deste servidor

Este arquivo existe para qualquer agente (ou humano) que for mexer neste projeto depois.
Contém as decisões, gotchas e procedimentos exatos usados até agora. Leia antes de rodar
qualquer `docker compose` ou `docker restart` aqui.

## O que é isto

Servidor Minecraft Bedrock Dedicated Server rodando em Docker (`itzg/minecraft-bedrock-server`),
exposto pra internet via um relay próprio (self-hosted): `frpc` (cliente, roda aqui em Docker)
conectando numa VPS gratuita da Oracle Cloud rodando `frps` (servidor do relay). Motivo: estamos
atrás de CGNAT (sem IP público de verdade), então não dá pra fazer port-forward direto no
roteador — ver seção "VPS relay" abaixo pra detalhes completos e o porquê de não termos usado
IPv6 direto (o ONT da operadora, Huawei HG8245Q2, não expõe firewall IPv6 configurável) nem um
serviço de túnel de terceiro tipo playit.gg (cota de banda limitada no free tier, e teve uma
instabilidade real do lado deles que derrubou o acesso externo por um bom tempo — foi o que nos
fez migrar pra esse setup).

Arquivos:
- `docker-compose.yml` — as duas services (`bedrock`, `frpc`)
- `.env` — contém `FRP_TOKEN` (não versionar, não compartilhar; **não existe** um `.env`
  de exemplo funcional, use `.env.example` como template)
- `frp/frpc.toml` — config do cliente do relay. **Esse arquivo É versionado** (ao contrário do
  `.env`) porque o token não fica hardcoded nele — usa template `{{ .Envs.FRP_TOKEN }}`,
  resolvido em runtime a partir da env var que o `docker-compose.yml` repassa pro container.
- `data/` — bind mount completo do `/data` do container. É o estado inteiro do servidor:
  mundo, packs, `server.properties`, allowlist etc. Copiável/portável (ver seção Backup).

## Sobre reiniciar o `bedrock`

Diferente do setup antigo (playit.gg, que usava `network_mode: "service:bedrock"` e por isso
precisava ser recriado toda vez que o `bedrock` reiniciava), o `frpc` **não tem essa
dependência** — ele está na rede padrão do Docker Compose e resolve o serviço `bedrock` pelo
nome via DNS interno do Docker a cada conexão. Reiniciar/recriar o `bedrock` **não** afeta o
`frpc`. Não precisa de nenhum passo extra depois de um `docker restart minecraft-bedrock`.

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
   pra confirmar que carregou sem erro. Não precisa mexer no `frpc` depois (ver seção acima).

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
| OptiFPS | ✅ | — | `e5d50e28-8413-43e9-9230-8f0c5ecccf4b` | RP de performance: sobrescreve fog vanilla, simplifica partículas, adiciona seção própria nas Configurações via JSON-UI |
| 3DSkinLayer | ✅ | — | `4293807a-e806-43f8-94af-268fc552b16b` | RP: faz a segunda camada da skin (overlay) parecer 3D. Sem sobreposição de arquivo com nenhum outro pack instalado |

Ordem completa e atualizada de cada `world_resource_packs.json` / `world_behavior_packs.json`
está nos próprios arquivos — essa tabela é só referência de UUID pra não precisar reabrir cada
`manifest.json` de novo.

## VPS relay (Oracle Cloud + frp)

Substituiu o playit.gg em 2026-09-14. Motivo: cota de banda do free tier + uma instabilidade
real do lado deles (dashboard retornando "API error: internal" em Bandwidth/Tunnel
Usage/Agent Usage, agente sem conseguir reconectar por 40+ minutos). Investigamos e
descartamos antes: port-forward IPv4 direto (estamos atrás de CGNAT, confirmado via
`tracepath` mostrando salto em `100.64.0.0/10`), e IPv6 direto (temos IPv6 público de
verdade, mas o ONT Huawei HG8245Q2 da operadora não expõe nenhuma tela de firewall/pinhole
IPv6 pro usuário final).

- **IP público da VPS**: `140.238.187.168` (fixo, não muda)
- **Provedor**: Oracle Cloud, tier "Always Free"
- **Shape**: `VM.Standard.E2.1.Micro` (1 OCPU / 1GB RAM, **AMD x86_64**, não ARM) — escolhido
  porque o shape ARM gratuito (`VM.Standard.A1.Flex`) deu erro de "Out of capacity" na região
  Brazil East (São Paulo), um problema comum/conhecido de disponibilidade do tier grátis da
  Oracle. E2.1.Micro é mais que suficiente já que a VPS só roda o relay, não o jogo.
- **Região**: Brazil East (São Paulo)
- **Hostname da instância**: `minecraft-relay`
- **Usuário SSH**: `ubuntu` (imagem Ubuntu)
- **Chave SSH**: `~/.ssh/oracle-minecraft-relay.key` (privada, fora do repo) — conectar com:
  ```bash
  ssh -i ~/.ssh/oracle-minecraft-relay.key ubuntu@140.238.187.168
  ```

### Como o relay funciona

```
Jogador → 140.238.187.168:19132 (UDP) → frps (VPS, systemd) → túnel autenticado (TCP 7000)
       → frpc (aqui, container Docker) → bedrock:19132 (rede interna do Compose)
```

- **`frps`** (servidor) roda **na VPS**, fora do Docker, como serviço systemd nativo (não
  containerizado lá — mais simples pra uma única VM pequena que só faz isso):
  - Binário: `/usr/local/bin/frps` (baixado do GitHub releases, v0.71.0, `linux_amd64`)
  - Config: `/etc/frp/frps.toml` — `bindPort = 7000`, `auth.token` (mesmo valor do
    `FRP_TOKEN` local)
  - Serviço: `sudo systemctl status frps` / `sudo journalctl -u frps -f`
- **`frpc`** (cliente) roda **aqui**, como container Docker (`docker-compose.yml`), configurado
  por `frp/frpc.toml`. Conecta de saída na VPS (porta TCP 7000) e expõe
  `bedrock:19132/udp` → `140.238.187.168:19132`.
- **Token de autenticação**: gerado com `openssl rand -hex 24`, vive em dois lugares que
  precisam bater: `.env` (`FRP_TOKEN`, local) e `/etc/frp/frps.toml` (`auth.token`, na VPS).
  Se um dia precisar trocar, atualize os dois e reinicie `frpc` (aqui) + `frps`
  (`sudo systemctl restart frps`, na VPS).

### Firewall (duas camadas, as duas precisam liberar as portas)

1. **iptables da própria VPS** (SO): por padrão só libera SSH (porta 22). Regras adicionadas
   pra TCP 7000 e UDP 19132, persistidas via `netfilter-persistent` (pacote
   `iptables-persistent`). Conferir com `sudo iptables -L INPUT -n --line-numbers` na VPS.
2. **Security List da VCN na Oracle** (firewall de nuvem, painel web): regras de ingress
   criadas manualmente no console (Networking → Virtual Cloud Networks →
   `minecraft-bedrock` → Security Lists → Default Security List) liberando TCP 7000 e UDP
   19132 de `0.0.0.0/0`, "stateful" (não marcar "Stateless").

Faltando qualquer uma das duas camadas, a conexão trava em timeout (não "recusada") — foi
assim que diagnosticamos que faltava a Security List na primeira tentativa.

### Testar sem abrir o jogo

Dá pra verificar se o relay está respondendo de ponta a ponta com um ping RakNet (protocolo
do Bedrock) direto, sem precisar abrir o Minecraft:
```python
import socket, struct, time
MAGIC = bytes.fromhex("00ffff00fefefefefdfdfdfd12345678")
sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
sock.settimeout(6)
sock.sendto(b'\x01' + struct.pack('>Q', int(time.time()*1000)) + MAGIC + struct.pack('>Q', 12345),
            ("140.238.187.168", 19132))
data, addr = sock.recvfrom(2048)
print(data[35:35+struct.unpack('>H', data[33:35])[0]].decode())  # MOTD do servidor
```
Se responder com a MOTD (`MCPE;Pipoca and Nanah's Place;...`), está tudo funcionando.

## Comandos `just` disponíveis

Ferramentas geridas via `mise` (`mise.toml` fixa `just` numa versão exata, não "latest",
pra reprodutibilidade — rodar `mise install` antes de usar `just` pela primeira vez numa
máquina nova).

- `just backup` — para o `bedrock`, commita `data/worlds` no git (com `-` nas linhas de
  git pra nunca travar o retorno do servidor por falta de mudança ou falha de push) e sobe
  tudo de novo (não precisa mexer no `frpc`, ver seção "Sobre reiniciar o bedrock").
- `just stop` — só para os containers (`docker compose stop`), sem remover nada.
- `just provision` — provisiona o servidor do zero numa máquina nova: confere que `.env`
  existe (aborta com aviso se não), roda `scripts/install-addons.sh` (reextrai todos os
  addons de `addons/` pras pastas certas em `data/`) e sobe os containers. O mundo em si
  já vem pronto do `git clone` (está em `data/worlds/`, versionado).
- `just cron-install` / `just cron-remove` — instalam/removem uma entrada de crontab que
  roda `just backup` todo dia às 12:00, usando um comentário-marcador
  (`# minecraft-bedrock-backup`) pra ficar idempotente (rodar de novo substitui em vez de
  duplicar; remover quando não existe não dá erro). Testado manualmente nesta máquina.

`scripts/install-addons.sh` tem, hardcoded, o mapeamento exato de cada addon em `addons/`
pra sua pasta de destino em `data/resource_packs/`/`data/behavior_packs/` (mesmos nomes da
tabela abaixo), incluindo o fix do manifesto do Sanrioverse. Se um addon novo for
adicionado ao projeto, esse script precisa ganhar mais um bloco pra ele — não é genérico.

## Versionamento (git)

Repositório privado — decisão consciente de versionar o mundo salvo (`data/worlds/`) junto,
como forma de backup, já que não há problema de privacidade num repo privado.

`.gitignore` mantém de fora:
- `.env` (token do frp — isso vale independente do repo ser privado ou não, é uma
  credencial viva, não um dado pessoal)
- todo o resto de `data/` (conteúdo padrão da engine tipo `vanilla_*`/`chemistry_*`/
  `experimental_*`, mais as cópias já extraídas dos addons em `resource_packs/`/
  `behavior_packs/` — redundantes, já que `addons/` guarda os arquivos originais)

O que fica versionado: `docker-compose.yml`, `.env.example`, `AGENTS.md`, `README.md`,
`addons/` (fontes originais dos addons) e `data/worlds/` (o save do mundo).

**Cuidado ao commitar o mundo**: o save usa LevelDB (ver explicação em conversas anteriores,
não repetida aqui) — commitar com o servidor rodando pode pegar um estado inconsistente entre
o WAL e as SSTables. Prefira `docker compose stop bedrock` antes de um `git add data/worlds/`
+ commit, e subir de novo depois (`docker compose up -d`).

## Backup / migração

`data/` é um bind mount comum, não named volume — é portável. Pra mover pra outra máquina:
```bash
docker compose down          # importante: parar antes de copiar (LevelDB não gosta de cópia "quente")
tar -czf backup.tar.gz -C ~/minecraft-bedrock data docker-compose.yml .env
```
Extrair no destino, `docker compose up -d` (com Docker instalado). O `frpc` não está preso
à máquina de onde roda o `bedrock` — só precisa do mesmo `.env` (`FRP_TOKEN`) e de rede até a
VPS. A VPS (`frps`) é um recurso separado, independente (ver seção "VPS relay"); não faz parte
desse backup/migração do `data/`.
