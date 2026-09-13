# Minecraft Bedrock Server — "Pipoca and Nanah's Place"

Servidor pessoal de Minecraft Bedrock rodando em Docker, com acesso externo via túnel
(playit.gg), sem precisar abrir porta no roteador.

## O que tem aqui

- **Servidor Bedrock** (`itzg/minecraft-bedrock-server`), sempre reiniciando sozinho
  (`restart: unless-stopped`), com allowlist desativada, dificuldade normal, gamemode
  survival e uma seed fixa.
- **Túnel playit.gg** (`playit-agent`) rodando junto, expondo a porta do servidor pra
  internet via UDP — necessário porque Bedrock não roda em HTTP/TCP comum.
- **7 addons instalados** (resource packs e/ou behavior packs), listados abaixo.

## Como usar

Subir tudo:
```bash
cd ~/minecraft-bedrock
docker compose up -d
```

Ver status:
```bash
docker compose ps
docker logs minecraft-bedrock --tail 30
docker logs playit-agent --tail 10
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
- Endereço: `schmidt-diploma.tun.ply.gg`
- Porta: `64625`

(Esse endereço é gerado pelo painel do playit.gg e pode mudar se o túnel for recriado lá.)

## Estrutura de pastas

```
minecraft-bedrock/
├── docker-compose.yml     # define os dois containers (bedrock + playit)
├── .env                   # chave secreta do playit.gg (não compartilhar, fora do git)
├── .env.example           # modelo do .env
├── .gitignore             # ver seção Versionamento abaixo
├── mise.toml              # fixa a versão do `just` (via mise)
├── justfile               # atalhos: backup, stop, provision, cron-install/remove
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

O mundo foi resetado (recomeçado do zero) mantendo a mesma seed, dificuldade e todos os
addons/gamerules acima — ou seja, o terreno é idêntico ao anterior, só o progresso dos
jogadores (construções, inventário) que foi zerado.

## Versionamento

Este é um repositório git (privado). O `.gitignore` só deixa de fora `.env` (segredo do
playit.gg) e o conteúdo de `data/` que não é `data/worlds/` (binário do servidor, packs
padrão da engine, cópias já extraídas dos addons — tudo regenerável automaticamente ou a
partir de `addons/`). **O save do mundo (`data/worlds/`) é versionado de propósito**, como
mecanismo de backup — já que o repo é privado, não há problema de expor o conteúdo do
mundo em si.

`just backup` automatiza isso (para o servidor, commita, dá push, sobe de novo), e
`just cron-install` agenda esse comando pra rodar sozinho todo dia ao meio-dia.

## Detalhes técnicos e "pegadinhas"

Ver [`AGENTS.md`](./AGENTS.md) — tem a explicação de por que o `playit` precisa ser
recriado toda vez que o `bedrock` reinicia, como mandar comandos de console pro servidor,
e o processo exato usado pra instalar cada addon.
