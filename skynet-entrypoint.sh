#!/bin/bash
# SKYNET GAMING: confere a configuracao antes de ligar o servidor e depois chama o inicio normal da imagem base
# (melkortf). Se algo estiver inseguro ou invalido, o servidor NAO liga e a mensagem diz o que corrigir.
set -euo pipefail

falhar() {
    printf '[skynet] ERRO: %s\n' "$*" >&2
    exit 64
}

# 1. Senha do RCON: obrigatoria e forte. Os scripts da imagem base usam a senha sem aspas, entao ela so pode ter
#    caracteres seguros (espaco, aspas ou simbolos do shell quebrariam o servidor ou abririam brecha).
senha="${RCON_PASSWORD:-}"
[ -n "$senha" ] || falhar "defina RCON_PASSWORD com uma senha forte (minimo 12 caracteres: letras, numeros e . _ - @ % + =)."
[ "${#senha}" -ge 12 ] || falhar "RCON_PASSWORD precisa ter pelo menos 12 caracteres."
[[ "$senha" =~ ^[A-Za-z0-9._@%+=-]+$ ]] || falhar "RCON_PASSWORD so pode ter letras, numeros e . _ - @ % + ="
case "${senha,,}" in
    *123456* | *password* | *changeme* | *senha* | *qwerty* | *admin* | *troque*)
        falhar "RCON_PASSWORD fraca demais. Use uma senha aleatoria (ex.: openssl rand -hex 16)." ;;
esac

# 2. Valores que entram no server.cfg: sem aspas, ponto e virgula ou quebra de linha (evita injetar comandos).
for nome in SERVER_HOSTNAME SERVER_PASSWORD SERVER_TAGS DOWNLOAD_URL STV_NAME STV_TITLE STV_PASSWORD; do
    valor="${!nome:-}"
    if [[ "$valor" == *'"'* || "$valor" == *';'* || "$valor" == *$'\n'* || "$valor" == *$'\r'* ]]; then
        falhar "$nome nao pode ter aspas, ponto e virgula ou quebra de linha."
    fi
done
[[ "${SERVER_REGION:-255}" =~ ^([0-7]|255)$ ]] || falhar "SERVER_REGION tem que ser 0 a 7 ou 255."
[ -z "${DOWNLOAD_URL:-}" ] || [[ "$DOWNLOAD_URL" =~ ^https?://[A-Za-z0-9._~:/%+=-]+$ ]] || falhar "DOWNLOAD_URL tem que ser um link http(s) simples."

# 3. Valores que a imagem base usa sem aspas na linha de comando do servidor.
[ -z "${SERVER_TOKEN:-}" ] || [[ "$SERVER_TOKEN" =~ ^[A-Fa-f0-9]{32}$ ]] || falhar "SERVER_TOKEN (GSLT) tem que ter 32 caracteres hexadecimais."
for nome in PORT CLIENT_PORT STEAM_PORT STV_PORT; do
    valor="${!nome:-}"
    [[ "$valor" =~ ^[0-9]{1,5}$ ]] && [ "$valor" -ge 1 ] && [ "$valor" -le 65535 ] || falhar "$nome tem que ser uma porta (1 a 65535)."
done
[[ "${IP:-}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || falhar "IP tem que ser um endereco IPv4 (padrao 0.0.0.0)."

# 4. Admins (opcional): SM_ADMINS="STEAM_0:1:1234567,[U:1:7654321]" vira o admins_simple.ini com acesso total (z).
#    Sem SM_ADMINS o arquivo nao e mexido (da para montar o seu proprio admins_simple.ini como volume).
if [ -n "${SM_ADMINS:-}" ]; then
    arq="$SERVER_DIR/tf/addons/sourcemod/configs/admins_simple.ini"
    linhas="// Gerado a partir de SM_ADMINS a cada inicio. Para mudar, altere a variavel."$'\n'
    IFS=',' read -ra lista <<< "$SM_ADMINS"
    for id in "${lista[@]}"; do
        id="${id//[[:space:]]/}"
        [ -n "$id" ] || continue
        [[ "$id" =~ ^(STEAM_[0-5]:[01]:[0-9]{1,10}|\[U:1:[0-9]{1,10}\])$ ]] || falhar "SM_ADMINS: '$id' nao e um SteamID valido (use STEAM_0:1:123 ou [U:1:123])."
        linhas+="\"$id\" \"99:z\""$'\n'
    done
    printf '%s' "$linhas" > "$arq"
    echo "[skynet] admins carregados de SM_ADMINS: $(($(printf '%s' "$linhas" | wc -l) - 1))"
fi

echo "[skynet] configuracao conferida, ligando o servidor"
exec "$SERVER_DIR/entrypoint.sh" "$@"
