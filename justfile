# Atualização rápida de backup: para o servidor (evita corromper o save do
# LevelDB), commita e sobe o mundo pro git, e sobe o servidor de volta.
# Prefixo "-" numa linha = ignora erro daquela linha e continua (sintaxe do
# just/Make, não do shell) — importante aqui pra garantir que o servidor
# sempre volte ao ar, mesmo se não houver nada novo pra commitar ou o
# `git push` falhar (rede, auth, etc).
backup:
    docker compose stop bedrock
    -git add data/worlds
    -git commit -m "Backup do mundo: $(date '+%Y-%m-%d %H:%M')"
    -git push
    docker compose up -d
    docker compose up -d --force-recreate playit

# Para o servidor (bedrock + playit), sem remover os containers.
stop:
    docker compose stop

# Provisiona o servidor inteiro numa máquina nova: instala os addons a partir
# de addons/ (o mundo em si já vem do git em data/worlds/, com os packs já
# registrados nos world_*_packs.json) e sobe os containers. Idempotente.
provision:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -f .env ]; then
        echo "Falta o arquivo .env (com PLAYIT_SECRET_KEY)."
        echo "Copie .env.example para .env e preencha a chave antes de continuar."
        exit 1
    fi
    mise install
    bash scripts/install-addons.sh
    docker compose up -d
    docker compose up -d --force-recreate playit
    echo "Servidor provisionado e no ar."

# Instala um cron que roda "just backup" todo dia ao meio-dia. Idempotente:
# pode rodar de novo sem duplicar a entrada (substitui a anterior).
cron-install:
    #!/usr/bin/env bash
    set -uo pipefail
    MISE_BIN="$(command -v mise)"
    DIR="{{justfile_directory()}}"
    MARKER="minecraft-bedrock-backup"
    LINE="0 12 * * * cd $DIR && $MISE_BIN exec -- just backup >> $DIR/backup.log 2>&1 # $MARKER"
    { crontab -l 2>/dev/null | grep -v "$MARKER"; echo "$LINE"; } | crontab -
    echo "Cron instalado: roda 'just backup' todo dia às 12:00."

# Remove o cron do backup diário, se existir. Idempotente: seguro rodar mesmo
# se o cron nunca tiver sido instalado.
cron-remove:
    #!/usr/bin/env bash
    set -uo pipefail
    MARKER="minecraft-bedrock-backup"
    { crontab -l 2>/dev/null | grep -v "$MARKER" || true; } | crontab -
    echo "Cron removido (se existia)."
