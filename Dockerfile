# syntax=docker/dockerfile:1.10
# SKYNET TF2 Dodgeball: servidor de TF2 Dodgeball pronto, em cima da imagem tf2-sourcemod do melkor.tf.
# Nada aqui tem senha, token ou IP: tudo isso entra pelas variaveis de ambiente quando o container liga.

# Imagem base. A montagem automatica (GitHub) troca "latest" pelo digest exato que foi testado.
ARG BASE=ghcr.io/melkortf/tf2-sourcemod/amd64:latest

# TF2 Dodgeball (Silorak, GPLv3) numa versao fixa: o commit abaixo e o mesmo que roda nos servidores da SKYNET.
ARG TFDB_GIT=https://github.com/Silorak/TF2-Dodgeball.git#65eb8c1fda3c126728884b01e8f7a174b2234908

# ---------- 1. compila os plugins a partir do codigo-fonte, com o compilador do proprio SourceMod da base ----------
FROM ${BASE} AS plugins
ARG TFDB_GIT
USER root
WORKDIR /compilar
ADD ${TFDB_GIT} tfdb
COPY plugins/ skynet/
RUN set -eu; \
    SC="$SERVER_DIR/tf/addons/sourcemod/scripting"; \
    INC="tfdb/TF2Dodgeball/addons/sourcemod/scripting/include"; \
    mkdir -p smx; \
    for fonte in \
        tfdb/TF2Dodgeball/addons/sourcemod/scripting/dodgeball.sp \
        tfdb/Subplugins/Menu/scripting/tfdb_menu.sp \
        tfdb/Subplugins/Print/scripting/tfdb_print.sp \
        tfdb/Subplugins/Speedometer/scripting/tfdb_speedhud.sp \
        skynet/*.sp; do \
        "$SC/spcomp64" -i"$SC/include" -i"$INC" -o"smx/$(basename "$fonte" .sp).smx" "$fonte"; \
    done; \
    ls -l smx

# ---------- 2. mapas: confere o sha256 de cada um e descompacta ----------
FROM busybox:1.37.0 AS mapas
COPY maps/ /mapas/
RUN set -eu; cd /mapas; sha256sum -c SHA256SUMS; for z in *.bsp.bz2; do bunzip2 "$z"; done; ls -l *.bsp

# ---------- 3. imagem final ----------
FROM ${BASE}
ARG SM=/home/tf2/server/tf/addons/sourcemod

LABEL org.opencontainers.image.title="SKYNET TF2 Dodgeball" \
      org.opencontainers.image.description="Servidor de TF2 Dodgeball pronto (TF2 Dodgeball + plugins SKYNET), sem senhas embutidas" \
      org.opencontainers.image.source="https://github.com/luci-immerstark/skynet-tf2-dodgeball" \
      org.opencontainers.image.licenses="GPL-3.0-only"

COPY --from=plugins --chown=tf2:tf2 /compilar/smx/ ${SM}/plugins/
COPY --from=plugins --chown=tf2:tf2 /compilar/tfdb/TF2Dodgeball/addons/sourcemod/configs/dodgeball/ ${SM}/configs/dodgeball/
COPY --from=plugins --chown=tf2:tf2 /compilar/tfdb/TF2Dodgeball/cfg/sourcemod/ /home/tf2/server/tf/cfg/sourcemod/
COPY --from=plugins --chown=tf2:tf2 /compilar/tfdb/TF2Dodgeball/addons/sourcemod/translations/ ${SM}/translations/
COPY --from=plugins --chown=tf2:tf2 /compilar/tfdb/LICENSE /home/tf2/server/LICENSES/TF2-Dodgeball-GPL-3.0.txt
COPY --from=mapas --chown=tf2:tf2 /mapas/*.bsp /home/tf2/server/tf/maps/

COPY --chown=tf2:tf2 config/sourcemod/ ${SM}/configs/
COPY --chown=tf2:tf2 config/cfg/ /home/tf2/server/tf/cfg/
COPY --chown=tf2:tf2 LICENSE /home/tf2/server/LICENSES/skynet-tf2-dodgeball-GPL-3.0.txt
COPY --chown=tf2:tf2 --chmod=755 skynet-entrypoint.sh /home/tf2/server/skynet-entrypoint.sh

# Sem valores perigosos de fabrica: a base vem com a senha de RCON 123456 e FastDL de terceiros; aqui ficam vazios
# e o servidor so liga com uma senha forte (veja skynet-entrypoint.sh).
ENV RCON_PASSWORD="" \
    SERVER_HOSTNAME="TF2 Dodgeball Server" \
    SERVER_PASSWORD="" \
    SERVER_TAGS="dodgeball,tfdb" \
    SERVER_REGION="255" \
    DOWNLOAD_URL="" \
    SM_ADMINS=""

USER tf2
ENTRYPOINT ["/home/tf2/server/skynet-entrypoint.sh"]
CMD ["+sv_pure", "1", "+map", "tfdb_amazon_b1", "+maxplayers", "16"]
