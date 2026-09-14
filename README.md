# Minecraft Bedrock Server — "Pipoca and Nanah's Place"

Servidor pessoal de Minecraft Bedrock rodando em Docker, com acesso externo via um relay
próprio (self-hosted, via [frp](https://github.com/fatedier/frp)) rodando numa VPS gratuita
da Oracle Cloud — sem precisar abrir porta no roteador (estamos atrás de CGNAT) e sem
depender da cota de banda de nenhum serviço de terceiro.

## O que tem aqui

- **Servidor Bedrock** (`itzg/minecraft-bedrock-server`), sempre reiniciando sozinho
  (`restart: unless-stopped`), com allowlist desativada, dificuldade normal, gamemode
  survival e uma seed fixa.
- **Cliente do relay** (`frpc`) rodando junto, conectando de saída numa VPS própria
  (Oracle Cloud, Always Free) que expõe a porta do servidor pra internet via UDP —
  necessário porque estamos atrás de CGNAT (sem IP público de verdade) e Bedrock não roda
  em HTTP/TCP comum.
- **7 addons instalados** (resource packs e/ou behavior packs), listados abaixo.

## Como usar

Primeira vez (só é necessário uma vez, ou numa máquina nova): copiar o `.env.example` pra
`.env` e preencher o token do frp — sem isso o relay não autentica com a VPS.
```bash
cd ~/minecraft-bedrock
cp .env.example .env
# editar .env e preencher FRP_TOKEN (o mesmo token configurado em /etc/frp/frps.toml na VPS)
```

Subir tudo:
```bash
docker compose up -d
```

Ver status:
```bash
docker compose ps
docker logs minecraft-bedrock --tail 30
docker logs frpc --tail 10
```

Parar tudo:
```bash
docker compose down
```

Ou, usando os atalhos do `just` (requer `mise install` uma vez, pra instalar o `just`):
```bash
just stop        # para os containers
just backup      # backup rápido: para, versiona o mundo no git, sobe de volta
just provision   # sobe o servidor do zero numa máquina nova (addons + config + mundo)
just cron-install  # agenda o backup automático todo dia ao meio-dia
just cron-remove   # remove esse agendamento
```

**Endereço pra conectar no jogo** (Bedrock → Jogar → Servidores → Adicionar Servidor):
- Endereço: `140.238.187.168`
- Porta: `19132`

Esse é o IP público fixo da nossa VPS na Oracle Cloud (região Brazil East/São Paulo) — não
muda sozinho, diferente de um túnel de terceiro.

## Arquitetura do relay (VPS própria)

```
Jogador → 140.238.187.168:19132 (VPS Oracle) → frps → túnel → frpc (aqui) → bedrock:19132
```

- **VPS**: Oracle Cloud "Always Free", shape `VM.Standard.E2.1.Micro` (1 OCPU/1GB, AMD),
  região Brazil East (São Paulo). Só roda o `frps` (servidor do relay) — leve o bastante
  pra sobrar de longe nesse tier grátis.
- **`frps`** roda na VPS como serviço systemd (não em Docker lá), escutando porta TCP 7000
  (controle) e UDP 19132 (dados do jogo).
- **`frpc`** roda aqui como container Docker (`docker-compose.yml`), conecta de saída na
  VPS e aponta pro serviço `bedrock:19132` via rede interna do Docker Compose (resolve o
  nome do serviço automaticamente — **não precisa** do truque de
  `network_mode: service:bedrock` que o setup antigo (playit.gg) exigia, então `frpc`
  **não precisa ser recriado** quando `bedrock` reinicia).
- Acesso SSH à VPS: chave em `~/.ssh/oracle-minecraft-relay.key` (fora do repo, não
  versionada). Detalhes completos em [`AGENTS.md`](./AGENTS.md).

## Estrutura de pastas

```
minecraft-bedrock/
├── docker-compose.yml     # define os dois containers (bedrock + frpc)
├── .env                   # token do frp (não compartilhar, fora do git)
├── .env.example           # modelo do .env
├── .gitignore             # ver seção Versionamento abaixo
├── mise.toml              # fixa a versão do `just` (via mise)
├── justfile               # atalhos: backup, stop, provision, cron-install/remove
├── frp/
│   └── frpc.toml          # config do cliente do relay (token via env var, seguro pro git)
├── scripts/
│   └── install-addons.sh  # reinstala os addons de addons/ em data/ (usado por `just provision`)
├── AGENTS.md              # contexto técnico detalhado (pra quem for mexer na configuração)
├── README.md              # este arquivo
├── addons/                # arquivos .mcpack/.mcaddon ORIGINAIS baixados (fonte, não instalados)
└── data/                  # TODO o estado do servidor (mundo, packs, configs)
    ├── worlds/Bedrock level/   # o mundo salvo
    ├── resource_packs/         # addons visuais JÁ EXTRAÍDOS e instalados
    ├── behavior_packs/         # addons de gameplay JÁ EXTRAÍDOS e instalados
    └── server.properties       # config gerada a partir das env vars do compose
```

A pasta `addons/` guarda os arquivos `.mcpack`/`.mcaddon` como foram baixados — é a "fonte",
útil pra reinstalar do zero ou mandar pra outra pessoa. O que roda de fato no servidor é a
cópia já extraída dentro de `data/resource_packs/` e `data/behavior_packs/` — as duas coisas
não se atualizam automaticamente uma a partir da outra.

`data/` é uma pasta normal (bind mount), não algo "trancado" dentro do Docker — dá pra
copiar/fazer backup dela diretamente (ver seção Backup no `AGENTS.md`).

## Configurações aplicadas

| Config | Valor | Onde fica |
|---|---|---|
| Nome do servidor | Pipoca and Nanah's Place | `docker-compose.yml` |
| Gamemode | Survival | `docker-compose.yml` |
| Dificuldade | Normal | `docker-compose.yml` |
| Seed do mundo | `5480987504042101543` | `docker-compose.yml` |
| Allowlist | Desativada (qualquer um entra) | `docker-compose.yml` |
| Keep Inventory | Ativado (não perde itens ao morrer) | gamerule, salva no mundo |
| Mostrar coordenadas | Ativado | gamerule, salva no mundo |

## Addons instalados

| Addon | Tipo | O que faz |
|---|---|---|
| **Actions and Stuff** | Resource Pack (visual, "Full Experience") | Pack visual/PBR geral |
| **Refined Cats** | Resource Pack | Retextura de gatos e ocelotes |
| **Sanrioverse** | Resource + Behavior | Personagens Sanrio (Kuromi, My Melody, Cinnamoroll) — itens, blocos, plushies |
| **Mail Pigeons** | Resource + Behavior | Pombos-correio pra mandar itens entre jogadores |
| **Chikawa Mob** | Resource + Behavior | Mobs fofos temáticos (Chiikawa) com um pequeno chatbot de respostas fixas |
| **Dynamic Light** | Resource + Behavior | Luz dinâmica ao segurar tochas/lanternas/etc |
| **DarkAge Bizarre Remake** | Resource + Behavior | Addon temático JoJo's Bizarre Adventure (Stands, habilidades) |
| **OptiFPS** | Resource Pack | Melhora performance/FPS — reduz neblina, simplifica partículas (bom pra celular) |
| **3D Skin Layer** | Resource Pack | Faz a segunda camada da skin (chapéu, jaqueta, etc.) parecer 3D em vez de plana |

O mundo foi resetado (recomeçado do zero) mantendo a mesma seed, dificuldade e todos os
addons/gamerules acima — ou seja, o terreno é idêntico ao anterior, só o progresso dos
jogadores (construções, inventário) que foi zerado.

## Versionamento

Este é um repositório git (privado). O `.gitignore` só deixa de fora `.env` (token do frp)
e o conteúdo de `data/` que não é `data/worlds/` (binário do servidor, packs
padrão da engine, cópias já extraídas dos addons — tudo regenerável automaticamente ou a
partir de `addons/`). **O save do mundo (`data/worlds/`) é versionado de propósito**, como
mecanismo de backup — já que o repo é privado, não há problema de expor o conteúdo do
mundo em si.

`just backup` automatiza isso (para o servidor, commita, dá push, sobe de novo), e
`just cron-install` agenda esse comando pra rodar sozinho todo dia ao meio-dia.

## Detalhes técnicos e "pegadinhas"

Ver [`AGENTS.md`](./AGENTS.md) — tem os detalhes da VPS/relay (IP, SSH, systemd do `frps`),
como mandar comandos de console pro servidor, e o processo exato usado pra instalar cada
addon.
