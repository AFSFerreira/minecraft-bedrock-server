#!/usr/bin/env bash
# Extrai todos os addons de addons/ e instala em data/resource_packs/ e
# data/behavior_packs/, com os mesmos nomes de pasta usados desde a instalação
# original (ver tabela de UUIDs em AGENTS.md). Idempotente: pode rodar quantas
# vezes quiser, sempre substitui a pasta de destino pelo conteudo mais recente
# de addons/.
#
# NAO mexe em data/worlds/ (o save do mundo ja registra os pack_id certos nos
# world_resource_packs.json / world_behavior_packs.json, que vem do git).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADDONS="$ROOT/addons"
DATA="$ROOT/data"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

install_pack() {
  # install_pack <arquivo_zip> <pasta_interna_no_zip> <destino_resource_ou_behavior>
  local zip="$1" inner="$2" dest="$3"
  local work="$TMP/$(basename "$zip" | tr ' /' '__')"
  mkdir -p "$work"
  unzip -oq "$zip" -d "$work"
  rm -rf "$dest"
  mkdir -p "$dest"
  cp -r "$work/$inner"/. "$dest"/
}

echo "== Actions and Stuff (RP) =="
install_pack "$ADDONS/Actions-And-Stuff-2.0.mcpack" "Actions And Stuff 1.9" \
  "$DATA/resource_packs/ActionsAndStuff"

echo "== Refined Cats (RP) =="
work="$TMP/refinedcats"
mkdir -p "$work"
unzip -oq "$ADDONS/refined_cats-v3.0.4.mcpack" -d "$work"
rm -rf "$DATA/resource_packs/RefinedCats"
mkdir -p "$DATA/resource_packs/RefinedCats"
cp -r "$work"/. "$DATA/resource_packs/RefinedCats"/

echo "== Sanrioverse (RP + BP) =="
install_pack "$ADDONS/sanrioverse_by_emobunny.mcaddon" "sanrioverse RP" \
  "$DATA/resource_packs/Sanrioverse"
install_pack "$ADDONS/sanrioverse_by_emobunny.mcaddon" "sanrioverse BP" \
  "$DATA/behavior_packs/Sanrioverse"
# Fix conhecido: o manifest original declara um modulo de script cujo arquivo
# nao existe no zip (scripts/main.js). Sem isso o pack e rejeitado na validacao.
python3 -c "
import json
p = '$DATA/behavior_packs/Sanrioverse/manifest.json'
m = json.load(open(p))
m['modules'] = [mod for mod in m['modules'] if mod['type'] != 'script']
m['dependencies'] = [d for d in m['dependencies'] if 'uuid' in d]
json.dump(m, open(p, 'w'), indent=2)
"

echo "== Mail Pigeons (RP + BP) =="
install_pack "$ADDONS/Mail Pigeons.mcaddon" "pigeon_rpack" \
  "$DATA/resource_packs/MailPigeons"
install_pack "$ADDONS/Mail Pigeons.mcaddon" "pigeon_bpack" \
  "$DATA/behavior_packs/MailPigeons"

echo "== Chikawa Mob (RP + BP) =="
install_pack "$ADDONS/ChikawaMob_Beh+Res_v1_2.mcaddon" "pbmobres" \
  "$DATA/resource_packs/ChikawaMob"
install_pack "$ADDONS/ChikawaMob_Beh+Res_v1_2.mcaddon" "pbmobbeh" \
  "$DATA/behavior_packs/ChikawaMob"

echo "== Dynamic Light (RP + BP) =="
install_pack "$ADDONS/DynamicLight v1.4.mcaddon" "DynamicLight RP" \
  "$DATA/resource_packs/DynamicLight"
install_pack "$ADDONS/DynamicLight v1.4.mcaddon" "DynamicLight BP" \
  "$DATA/behavior_packs/DynamicLight"

echo "== DarkAge Bizarre Remake (RP + BP, vem em dois .mcpack separados) =="
install_pack "$ADDONS/DarkAge Bizarre Remake v0.7.76 RP.mcpack" \
  "DarkAge Bizarre Remake v0.7.76 RP" "$DATA/resource_packs/DarkAgeBizarre"
install_pack "$ADDONS/DarkAge Bizarre Remake v0.7.76 BP.mcpack" \
  "DarkAge Bizarre Remake v0.7.76 BP" "$DATA/behavior_packs/DarkAgeBizarre"

echo "== OptiFPS (RP) =="
install_pack "$ADDONS/OptiFps v3 (fixed).mcpack" "OptiFps v3" \
  "$DATA/resource_packs/OptiFPS"

echo "Addons instalados com sucesso."
