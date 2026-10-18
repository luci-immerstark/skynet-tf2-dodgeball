#!/bin/bash
# Testes da imagem: rodam no GitHub a cada montagem e podem rodar em qualquer maquina com Docker.
#   uso: tests/teste.sh <imagem> [opcoes extras do docker run, ex.: --cpuset-cpus 3 --memory 2g]
# Confere: recusa de configuracoes inseguras, servidor no ar, plugins carregados, valores padrao seguros,
# troca por todos os mapas da rotacao, erros registrados, dados sensiveis na imagem e desligamento limpo.
set -uo pipefail
IMG="${1:?uso: tests/teste.sh <imagem> [opcoes do docker run]}"
shift
EXTRA=("$@")
AQUI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(dirname "$AQUI")"
# shellcheck source-path=SCRIPTDIR source=esperado.sh
. "$AQUI/esperado.sh"
mapfile -t MAPAS < <(grep -vE '^[[:space:]]*($|//)' "$RAIZ/config/cfg/mapcycle.txt")
NOME="skynet-teste-$$"
SENHA="T$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
FALHAS=0
TMP="$(mktemp -d)"

ok() { printf '  ok    %s\n' "$*"; }
erro() { printf '  ERRO  %s\n' "$*"; FALHAS=$((FALHAS + 1)); }
etapa() { printf '\n== %s\n' "$*"; }
limpar() { docker rm -f "$NOME" "$NOME-recusa" >/dev/null 2>&1; rm -rf "${TMP:?}"; }
trap limpar EXIT
r() { docker exec "$NOME" ./rcon -H 127.0.0.1 -p 27015 -P "$SENHA" "$@" 2>&1; }
valor() { r "$1" | grep -m1 -F "\"$1\" = "; }
# A Steam avisa o servidor quando sai atualizacao do TF2; ele entao se desliga na proxima troca de mapa para atualizar.
desatualizado() { docker logs "$NOME" 2>&1 | grep -q "MasterRequestRestart"; }
AVISO_BASE="o TF2 da imagem base esta desatualizado (saiu atualizacao do jogo): monte de novo quando a imagem do melkor.tf for atualizada"

etapa "0. valores padrao da imagem"
ambiente="$(docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$IMG")"
for var in RCON_PASSWORD SERVER_PASSWORD SERVER_TOKEN STV_PASSWORD DOWNLOAD_URL SM_ADMINS; do
    linha="$(grep -E "^$var=" <<<"$ambiente" || true)"
    if [ -z "$linha" ] || [ "$linha" = "$var=" ]; then ok "$var vem vazio"; else erro "$var vem preenchido na imagem"; fi
done
if [ -f "$RAIZ/tools/auditar_mapas.py" ] && [ -d "$RAIZ/maps" ]; then
    cid="$(docker create "$IMG")"
    for vpk in tf/tf2_misc_dir.vpk tf/tf2_textures_dir.vpk hl2/hl2_misc_dir.vpk hl2/hl2_textures_dir.vpk; do
        docker cp "$cid:/home/tf2/server/$vpk" "$TMP/" >/dev/null 2>&1 || true
    done
    docker rm "$cid" >/dev/null
    if python3 -I "$RAIZ/tools/auditar_mapas.py" "$RAIZ/maps" "$TMP"/*.vpk >"$TMP/auditoria.txt" 2>&1; then
        ok "auditoria dos mapas com as texturas do jogo: $(tail -n 1 "$TMP/auditoria.txt")"
    else
        erro "auditoria dos mapas reprovou:"; cat "$TMP/auditoria.txt"
    fi
    grep -F "aviso:" "$TMP/auditoria.txt" | sort -u | head -n 10
fi

etapa "1. recusa configuracoes inseguras (o servidor nem pode ligar)"
recusa() {
    local desc="$1" saida cod
    shift
    saida="$(timeout 120 docker run --rm --name "$NOME-recusa" "${EXTRA[@]}" "$@" "$IMG" 2>&1)"
    cod=$?
    docker rm -f "$NOME-recusa" >/dev/null 2>&1
    if [ "$cod" -ne 0 ] && grep -q '\[skynet\] ERRO' <<<"$saida"; then
        ok "recusou: $desc"
    else
        erro "NAO recusou: $desc (codigo $cod)"; printf '%s\n' "$saida" | tail -n 5
    fi
}
RUIM_123="123456"; RUIM_CURTA="Ab1Cd2Ef3"; RUIM_FRACA="Password12345678"
RUIM_SIMBOLO='Abcdefghij12";quit'; RUIM_ESPACO='Abcdefgh 12345678'; RUIM_GLOB='Abcdefgh*12345678'
NOME_RUIM='Servidor"; rcon_password "INJETADO'; ADMIN_RUIM='STEAM_0:1:1234567,"x" "z"'; TOKEN_RUIM='abc;quit'; PORTA_RUIM='27015;id'
recusa "sem senha de RCON"
recusa "senha 123456 (o padrao da imagem base)" -e RCON_PASSWORD="$RUIM_123"
recusa "senha curta" -e RCON_PASSWORD="$RUIM_CURTA"
recusa "senha fraca" -e RCON_PASSWORD="$RUIM_FRACA"
recusa "senha com aspas e ponto e virgula" -e RCON_PASSWORD="$RUIM_SIMBOLO"
recusa "senha com espaco" -e RCON_PASSWORD="$RUIM_ESPACO"
recusa "senha com asterisco" -e RCON_PASSWORD="$RUIM_GLOB"
recusa "nome do servidor tentando injetar comando" -e RCON_PASSWORD="$SENHA" -e SERVER_HOSTNAME="$NOME_RUIM"
recusa "admin com SteamID invalido" -e RCON_PASSWORD="$SENHA" -e SM_ADMINS="$ADMIN_RUIM"
recusa "token GSLT invalido" -e RCON_PASSWORD="$SENHA" -e SERVER_TOKEN="$TOKEN_RUIM"
recusa "porta invalida" -e RCON_PASSWORD="$SENHA" -e PORT="$PORTA_RUIM"

etapa "2. liga com configuracao valida"
if ! docker run -d --name "$NOME" "${EXTRA[@]}" -e RCON_PASSWORD="$SENHA" \
        -e SM_ADMINS="STEAM_0:1:1234567,[U:1:7654321]" "$IMG" >/dev/null; then
    erro "o container nao foi criado"; exit 1
fi
inicio=$SECONDS
pronto=0
while [ $((SECONDS - inicio)) -lt 1500 ]; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$NOME" 2>/dev/null)" != "true" ]; then
        erro "o container parou sozinho"; docker logs --tail 40 "$NOME"; exit 1
    fi
    if r status | grep -q '^map'; then pronto=1; break; fi
    sleep 10
done
if [ "$pronto" = 1 ]; then ok "servidor no ar em $((SECONDS - inicio))s"; else
    erro "o servidor nao respondeu em 25 minutos"; docker logs --tail 60 "$NOME"; exit 1
fi

etapa "3. plugins e configuracao"
lista="$(r "sm plugins list")"
for p in "${PLUGINS[@]}"; do
    if grep -qF "\"$p\"" <<<"$lista"; then ok "plugin carregado: $p"; else erro "plugin NAO carregado: $p"; fi
done
if grep -qiE '<Failed>|<Error>|Errors:' <<<"$lista"; then erro "algum plugin falhou:"; grep -iE -A3 '<Failed>|<Error>|Errors:' <<<"$lista"; else ok "nenhum plugin com falha"; fi
exts="$(r "sm exts list")"
if grep -qiE 'FAILED|<Error>' <<<"$exts"; then erro "extensao com falha:"; grep -iE 'FAILED|<Error>' <<<"$exts"; else ok "extensoes sem falha"; fi
for par in "${COMANDOS[@]}"; do
    plugin="${par%%:*}"; cmd="${par#*:}"
    if r "sm cmds $plugin" | grep -qw -- "$cmd"; then ok "comando $cmd ($plugin)"; else erro "comando $cmd nao existe ($plugin)"; fi
done
v="$(valor sv_allow_point_servercommand)"
if grep -qF '= "official"' <<<"$v"; then ok "mapas da comunidade nao mandam comandos ao servidor"; else erro "sv_allow_point_servercommand: ${v:-sem resposta}"; fi
v="$(valor sv_downloadurl)"
if grep -qF '= ""' <<<"$v"; then ok "FastDL vazio por padrao"; else erro "sv_downloadurl: ${v:-sem resposta}"; fi
v="$(valor hostname)"
if grep -qF "= \"$NOME_PADRAO\"" <<<"$v"; then ok "nome padrao: $NOME_PADRAO"; else erro "hostname: ${v:-sem resposta}"; fi
adm="$(docker exec "$NOME" cat tf/addons/sourcemod/configs/admins_simple.ini 2>&1)"
if grep -qF '"STEAM_0:1:1234567" "99:z"' <<<"$adm" && grep -qF '"[U:1:7654321]" "99:z"' <<<"$adm"; then
    ok "admins de SM_ADMINS gravados"; else erro "admins_simple.ini nao tem os admins de SM_ADMINS"; fi

etapa "4. troca por todos os mapas da rotacao (${#MAPAS[@]})"
for m in "${MAPAS[@]}"; do
    if desatualizado; then erro "$AVISO_BASE"; break; fi
    if ! docker exec "$NOME" test -f "tf/maps/$m.bsp"; then erro "$m nao esta na imagem"; continue; fi
    r "changelevel $m" >/dev/null
    t0=$SECONDS
    carregou=0
    while [ $((SECONDS - t0)) -lt 180 ]; do
        sleep 5
        if r status | grep -qE "^map +: $m( |$)"; then carregou=1; break; fi
        [ "$(docker inspect -f '{{.State.Running}}' "$NOME" 2>/dev/null)" = "true" ] || break
    done
    if [ "$carregou" = 1 ]; then
        if r "sm plugins list" | grep -qiE '<Failed>|<Error>'; then erro "$m: algum plugin falhou neste mapa"; else ok "$m ($((SECONDS - t0))s)"; fi
    elif [ "$(docker inspect -f '{{.State.Running}}' "$NOME" 2>/dev/null)" != "true" ] && desatualizado; then
        erro "o servidor se desligou ao trocar para $m para atualizar: $AVISO_BASE"
        break
    elif [ "$(docker inspect -f '{{.State.Running}}' "$NOME" 2>/dev/null)" != "true" ]; then
        erro "o servidor CAIU ao trocar para $m ($(docker inspect -f 'codigo {{.State.ExitCode}}, falta de memoria: {{.State.OOMKilled}}' "$NOME"))"
        echo "  ---- ultimas linhas do console antes de cair:"
        docker logs --tail 60 "$NOME" 2>&1 | sed 's/^/  | /'
        break
    else
        erro "$m nao carregou em 3 minutos"
    fi
done

etapa "5. erros registrados"
logs="$(docker exec "$NOME" sh -c 'cat tf/addons/sourcemod/logs/errors_*.log 2>/dev/null')"
if [ -z "$logs" ]; then ok "nenhum erro registrado pelo SourceMod"; else erro "o SourceMod registrou erros:"; printf '%s\n' "$logs" | tail -n 25; fi
graves="$(docker logs "$NOME" 2>&1 | grep -iE 'segmentation fault|Host_Error|fatal error' | head -n 10)"
if [ -z "$graves" ]; then ok "nenhum erro grave no console"; else erro "erro grave no console:"; printf '%s\n' "$graves"; fi

etapa "6. dados sensiveis nos arquivos que a imagem adiciona"
achado="$(docker run --rm --entrypoint /bin/sh "$IMG" -c '
    cd /home/tf2/server || exit 1
    grep -rnIE "\b([0-9]{1,3}\.){3}[0-9]{1,3}\b|STEAM_[0-5]:[01]:[0-9]|\[U:1:[0-9]|logaddress_add|webhooks|rcon_password[[:space:]]+\"?[^\"\$[:space:]]" \
        skynet-entrypoint.sh tf/cfg/server.cfg.template tf/cfg/mapcycle.txt tf/cfg/sourcemod/skynet_*.cfg \
        tf/addons/sourcemod/configs/dodgeball tf/addons/sourcemod/configs/skynet_mapvote.txt 2>/dev/null \
        | grep -vE "0\.0\.0\.0|127\.0\.0\.1|STEAM_0:1:123|\[U:1:(123|7654321)\]"')"
if [ -z "$achado" ]; then ok "nenhum IP, SteamID, senha, webhook ou log externo"; else erro "dado sensivel na imagem:"; printf '%s\n' "$achado"; fi

etapa "7. desligamento"
if [ "$(docker inspect -f '{{.State.Running}}' "$NOME" 2>/dev/null)" != "true" ]; then
    erro "o servidor ja estava desligado (veja a etapa 4)"
    printf '\nRESULTADO: %s falha(s)\n' "$FALHAS"; exit 1
fi
t0=$SECONDS
docker stop -t 30 "$NOME" >/dev/null
cod="$(docker inspect -f '{{.State.ExitCode}}' "$NOME")"
if [ "$cod" = 0 ]; then ok "desligou limpo em $((SECONDS - t0))s"; else erro "codigo de saida $cod ao desligar"; fi

printf '\n'
if [ "$FALHAS" -gt 0 ]; then echo "RESULTADO: $FALHAS falha(s)"; exit 1; fi
echo "RESULTADO: todos os testes passaram"
