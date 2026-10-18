# shellcheck shell=bash
# O que os testes esperam desta imagem (lido por tests/teste.sh).
# shellcheck disable=SC2034
NOME_PADRAO="TF2 Dodgeball Server"
PLUGINS=(
    "[TF2] Dodgeball"
    "[TFDB] Admin menu"
    "[TFDB] Print & replace client indexes"
    "[TF2] Dodgeball Speed HUD"
    "SKYNET Auto Reflect"
    "SKYNET Map Vote"
    "SKYNET Pyro Only"
    "Admin File Reader"
    "Basic Commands"
)
COMANDOS=(
    "skynet_autoreflect:sm_autoreflect"
    "skynet_autoreflect:sm_votebot"
    "skynet_autoreflect:sm_botoff"
    "skynet_mapvote:sm_mapvote_now"
)
