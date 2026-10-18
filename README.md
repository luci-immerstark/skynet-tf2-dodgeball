# SKYNET TF2 Dodgeball (Docker)

Servidor de **TF2 Dodgeball** pronto para usar: TF2 Dodgeball, os plugins da SKYNET GAMING e 12 mapas testados, em cima da imagem [`tf2-sourcemod`](https://github.com/melkortf/tf2-servers) do melkor.tf.

```
ghcr.io/luci-immerstark/skynet-tf2-dodgeball:latest
```

[English below](#english)

## Começo rápido

1. Crie um arquivo `dodgeball.env` (só você deve conseguir ler: `chmod 600 dodgeball.env`):

   ```
   RCON_PASSWORD=<gere com: openssl rand -hex 16>
   SERVER_HOSTNAME=Meu Servidor de Dodgeball
   SERVER_TOKEN=<seu token GSLT>
   SM_ADMINS=<seu SteamID, ex.: STEAM_0:1:1234567>
   ```

2. Ligue o servidor:

   ```bash
   docker run -d --name tf2-dodgeball --restart unless-stopped \
     --env-file dodgeball.env \
     -p 27015:27015/udp \
     ghcr.io/luci-immerstark/skynet-tf2-dodgeball:latest
   ```

   Na primeira vez ele confere atualizações do TF2 e pode levar alguns minutos para aparecer.

3. Entre pelo console do jogo: `connect SEU_IP:27015`.

Com `docker compose`:

```yaml
services:
  dodgeball:
    image: ghcr.io/luci-immerstark/skynet-tf2-dodgeball:latest
    restart: unless-stopped
    env_file: dodgeball.env
    ports:
      - "27015:27015/udp"
```

## Variáveis

| Variável | Padrão | Para que serve |
|---|---|---|
| `RCON_PASSWORD` | (vazia) | **Obrigatória.** Senha do RCON: no mínimo 12 caracteres, só letras, números e `. _ - @ % + =`. Sem ela, ou com senha fraca, o servidor não liga. |
| `SERVER_HOSTNAME` | `TF2 Dodgeball Server` | Nome do servidor na lista. |
| `SERVER_PASSWORD` | (vazia) | Senha para entrar no servidor (vazia = aberto). |
| `SERVER_TOKEN` | (vazio) | Token GSLT, para o servidor aparecer na lista da Steam. Crie em <https://steamcommunity.com/dev/managegameservers> (App ID 440). |
| `SM_ADMINS` | (vazio) | SteamIDs dos admins, separados por vírgula (`STEAM_0:1:123` ou `[U:1:123]`). Recebem acesso total (`z`). |
| `SERVER_TAGS` | `dodgeball,tfdb` | Tags do servidor. |
| `SERVER_REGION` | `255` | Região (`0` a `7`, `255` = mundo; `2` = América do Sul). |
| `DOWNLOAD_URL` | (vazio) | Seu FastDL. Vazio = os jogadores baixam os mapas direto do servidor (funciona, só é mais lento). |
| `PORT` | `27015` | Porta do jogo (publique a mesma no `-p`). |
| `TICKRATE` | (vazio = 66,7) | `100`, `133` ou `200`, da imagem base. |

Nomes, senhas e links não podem ter aspas, ponto e vírgula ou quebra de linha (é assim que se injetaria comando no `server.cfg`); a imagem recusa.

## O que vem dentro

- **TF2 Dodgeball** (Silorak, continuação do plugin de Damizean e x07x08), compilado do código-fonte no commit [`65eb8c1`](https://github.com/Silorak/TF2-Dodgeball/tree/65eb8c1fda3c126728884b01e8f7a174b2234908): núcleo, menu de admin, print e velocímetro.
- **Plugins SKYNET** ([código e documentação](https://github.com/luci-immerstark/skynet-sourcemod-plugins)), também compilados do código-fonte:
  - **Auto Reflect**: `sm_autoreflect` (admin root) liga o rebate automático num jogador; `sm_votebot` (admin com votação) abre a votação do modo TODOS CONTRA O BOT; `sm_botoff` tira o bot.
  - **Map Vote**: votação do próximo mapa 3 minutos antes do fim, com histórico para não repetir mapas.
  - **Pyro Only**: o servidor é só de Pyro.
- **Foguetes ajustados** (`configs/dodgeball/general.cfg`): o foguete comum mata com um acerto; a NUKE usa o foguete normal do Soldier, sem crítico.
- **12 mapas** (lista e créditos abaixo), na rotação e na votação.
- SourceMod e Metamod da imagem base, com os plugins padrão.

As mensagens dos plugins SKYNET no chat são em português.

### Mudar a rotação ou colocar seus mapas

Monte seus arquivos por cima dos da imagem, por exemplo:

```bash
  -v ./mapcycle.txt:/home/tf2/server/tf/cfg/mapcycle.txt:ro \
  -v ./skynet_mapvote.txt:/home/tf2/server/tf/addons/sourcemod/configs/skynet_mapvote.txt \
  -v ./meus-mapas/tfdb_novo.bsp:/home/tf2/server/tf/maps/tfdb_novo.bsp:ro
```

## Segurança

O que a imagem faz:

- **Nenhuma senha, token, IP ou admin embutido.** Tudo entra pelas variáveis quando o container liga.
- **Recusa senha de RCON fraca.** A imagem base vem com a senha `123456`; aqui o padrão é vazio e o servidor não liga sem uma senha forte.
- **Recusa valores que injetariam comandos** no `server.cfg` ou na linha de comando do servidor.
- **Mapas da comunidade não mandam comandos para o console do servidor** (`sv_allow_point_servercommand "official"`).
- **Mapas auditados** a cada montagem ([`tools/auditar_mapas.py`](tools/auditar_mapas.py)): sha256 conferido, nenhum script (VScript), nenhum arquivo perigoso embutido, comandos de console só os ajustes de Dodgeball conhecidos, todas as texturas presentes.
- **Plugins compilados do código-fonte** durante a montagem, com o compilador do próprio SourceMod da imagem.
- **Testes automáticos** antes de cada publicação ([`tests/teste.sh`](tests/teste.sh)): recusa de configurações inseguras, todos os plugins carregados, troca por todos os mapas, nenhum erro registrado, nenhum dado sensível nos arquivos da imagem e desligamento limpo.
- **Varredura de dados sensíveis** no repositório a cada montagem ([`tools/varredura.sh`](tools/varredura.sh)).
- Roda como usuário comum (`tf2`), não como root.

O que recomendamos:

- **Publique só a porta UDP** (`-p 27015:27015/udp`). O RCON usa TCP na mesma porta: sem publicar o TCP, ninguém de fora tenta adivinhar a senha. Para administrar, use `SM_ADMINS` (comandos no jogo) ou `docker exec tf2-dodgeball ./rcon -H 127.0.0.1 -p 27015 -P "$RCON_PASSWORD" status`.
- Se usar `--network host`, bloqueie o TCP da porta do jogo no firewall.
- Atualize de vez em quando: `docker pull ghcr.io/luci-immerstark/skynet-tf2-dodgeball:latest` e recrie o container.

Achou um problema de segurança? Não abra issue pública: use **Report a vulnerability**, na aba **Security** deste repositório, que só os mantenedores veem.

## Mapas e créditos

Os mapas são de seus autores; estão aqui com crédito para facilitar a vida de quem quer montar um servidor. Se você é autor de algum e prefere que ele não esteja na imagem, abra uma issue que tiramos.

| Mapa | Autor | Onde conseguimos |
|---|---|---|
| tfdb_amazon_b1 | não identificado | não identificado |
| tfdb_backyard | não identificado | não identificado |
| tfdb_blockland_v4_1 | não identificado | não identificado |
| tfdb_hellspawn_b2 | não identificado | não identificado |
| tfdb_indoor_tennis_b1a | não identificado | não identificado |
| tfdb_pacmen_a4 | não identificado | não identificado |
| tfdb_risky_heights_v2 | não identificado | não identificado |
| tfdb_rocketbucks_v2 | não identificado | não identificado |
| tfdb_toolsheds_b4 | não identificado | não identificado |
| tfdb_cwg_gym_v1 | não identificado | Fórum da comunidade Blackwonder |
| tfdb_greybox | não identificado | Fórum da comunidade Blackwonder |
| tfdb_orangebox_b2 | não identificado | Fórum da comunidade Blackwonder |

Também agradecemos:

- [melkor.tf](https://github.com/melkortf/tf2-servers) pela imagem base (MIT);
- Silorak, x07x08 e Damizean pelo [TF2 Dodgeball](https://github.com/Silorak/TF2-Dodgeball) (GPLv3);
- [AlliedModders](https://www.sourcemod.net/) pelo SourceMod e Metamod:Source.

## Licença

GPLv3, a mesma do TF2 Dodgeball e dos plugins SKYNET (veja [LICENSE](LICENSE)). Dentro da imagem, as licenças ficam em `/home/tf2/server/LICENSES`.

---

## English

A ready-to-run **TF2 Dodgeball** server image: TF2 Dodgeball, the SKYNET GAMING plugins and 12 tested maps, built on melkor.tf's [`tf2-sourcemod`](https://github.com/melkortf/tf2-servers) image.

```bash
docker run -d --name tf2-dodgeball --restart unless-stopped \
  --env-file dodgeball.env -p 27015:27015/udp \
  ghcr.io/luci-immerstark/skynet-tf2-dodgeball:latest
```

- `RCON_PASSWORD` is **required** (at least 12 characters: letters, digits and `. _ - @ % + =`). The server refuses to start without it or with a weak one (the base image defaults to `123456`).
- Other variables: `SERVER_HOSTNAME`, `SERVER_PASSWORD`, `SERVER_TOKEN` (GSLT), `SM_ADMINS` (comma-separated SteamIDs, full access), `SERVER_TAGS`, `SERVER_REGION`, `DOWNLOAD_URL`, `PORT`, `TICKRATE`.
- No passwords, tokens, IPs or admins are baked in. Community maps cannot run server commands, maps are audited on every build, plugins are compiled from source and every release passes automated tests.
- Publish only the UDP port; RCON uses TCP on the same port, so leaving TCP closed keeps it off the internet.
- In-game messages from the SKYNET plugins are in Portuguese.
- Licensed under GPLv3. Map authors: see the table above; if you made one of these maps and want it removed, open an issue.
