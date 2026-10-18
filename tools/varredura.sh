#!/bin/bash
# Procura dados sensiveis (IPs, SteamIDs, senhas, tokens, e-mails, chaves, webhooks) nos arquivos de texto do
# repositorio. Roda no GitHub a cada montagem e pode rodar na sua maquina. Sai com erro se achar algo.
#   uso: tools/varredura.sh [pasta]
set -uo pipefail
cd "${1:-.}" || exit 2
achados=0

procurar() {   # descricao, regex, [regex dos trechos permitidos: exemplos ficticios da documentacao e dos testes]
    local r
    r=$(grep -rnoIE --exclude-dir=.git --exclude=varredura.sh -- "$2" . | grep -vE -- ":(${3:-$^})$")
    if [ -n "$r" ]; then
        printf 'ENCONTRADO: %s\n%s\n\n' "$1" "$r"
        achados=$((achados + 1))
    fi
}

procurar "endereco IP" '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' '0\.0\.0\.0|127\.0\.0\.1'
procurar "SteamID" 'STEAM_[0-5]:[01]:[0-9]+|\[U:1:[0-9]+\]' 'STEAM_0:1:123|STEAM_0:1:1234567|\[U:1:123\]|\[U:1:7654321\]'
procurar "senha escrita em cfg" '(rcon_password|sv_password|tv_password)[[:space:]]+"?[^"$[:space:]]+' 'rcon_password "INJETADO.*'
procurar "senha ou token escrito em variavel" '(RCON_PASSWORD|SERVER_PASSWORD|STV_PASSWORD|SERVER_TOKEN)[[:space:]]*(=|:[[:space:]])[[:space:]]*"?[^"$[:space:]<{]'
procurar "token GSLT" '\b[A-F0-9]{32}\b'
procurar "token de servico" 'ghp_[A-Za-z0-9]{20,}|github_pat_|gho_[A-Za-z0-9]{20,}|xox[abprs]-|AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}'
procurar "webhook do Discord" 'discord(app)?\.com/api/webhooks'
procurar "chave privada" 'BEGIN [A-Z ]*PRIVATE KEY'
procurar "e-mail" '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z.]{2,}' '[A-Za-z0-9._%+-]+@users\.noreply\.github\.com'
procurar "log ou FastDL apontando para servidor" 'logaddress_add[[:space:]]+"?[^"$[:space:]]|sv_downloadurl[[:space:]]+"https?://'
procurar "caminho ou dominio da infraestrutura SKYNET" '/srv/zmbr|/home/luci|skynet-tf2\.com\.br'

if [ "$achados" -gt 0 ]; then
    echo "varredura: $achados tipo(s) de dado sensivel encontrado(s). Nada deve ser publicado assim."
    exit 1
fi
echo "varredura: nenhum dado sensivel encontrado"
