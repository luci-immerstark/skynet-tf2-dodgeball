"""Auditoria de seguranca dos mapas da imagem (roda no GitHub a cada montagem e pode rodar na sua maquina).

uso: python3 -I tools/auditar_mapas.py <pasta maps/> [<arquivo _dir.vpk do jogo> ...]

Para cada maps/*.bsp.bz2 listado no maps/SHA256SUMS:
  - o arquivo bate com o sha256 registrado (ninguem trocou o mapa);
  - e um mapa de Dodgeball (nome tfdb_ e pontos de saida dos foguetes dos dois times);
  - nenhuma entidade roda script (VScript) e os comandos de console embutidos sao so os ajustes de Dodgeball
    conhecidos (o servidor ainda bloqueia esses comandos com sv_allow_point_servercommand "official");
  - nenhum arquivo perigoso embutido (script, cfg, binario);
  - com os .vpk do jogo: todas as texturas existem (sem isso o mapa fica roxo).
Sai com erro se qualquer mapa reprovar.
"""
import bz2, hashlib, io, lzma, os, re, struct, sys, zipfile

PERIGOSAS = {"point_clientcommand", "point_broadcastclientcommand", "logic_script"}
COMANDOS_OK = re.compile(r"^(sm_dodgeball_\w+ -?[\w.]+|tf_arena_use_queue [01]|mp_bonusroundtime \d+)$")
EXT_PROIBIDA = {"nut", "nuc", "cfg", "vpk", "dll", "so", "smx", "lua", "exe", "sh", "py", "bat", "cmd", "js"}
PASTA_PROIBIDA = ("cfg/", "addons/", "bin/", "scripts/vscripts/", "custom/")
EXT_CONHECIDA = {"vmt", "vtf", "mdl", "vvd", "vtx", "phy", "ani", "wav", "mp3", "ogg", "pcf", "res", "ain", "nav",
                 "txt", "vcd", "vhv", "ttf", "png", "jpg", "tga", "lmp"}


def lump(b, n):
    ofs, tam = struct.unpack_from("<ii", b, 8 + 16 * n)
    d = b[ofs:ofs + tam]
    if d[:4] == b"LZMA":
        real, ctam = struct.unpack_from("<II", d, 4)
        p = d[12:17]
        filt = [{"id": lzma.FILTER_LZMA1, "dict_size": struct.unpack_from("<I", p, 1)[0],
                 "lc": p[0] % 9, "lp": (p[0] // 9) % 5, "pb": p[0] // 45}]
        d = lzma.LZMADecompressor(format=lzma.FORMAT_RAW, filters=filt).decompress(d[17:17 + ctam], max_length=real)
    return d


def materiais_do_jogo(arquivo):
    d = open(arquivo, "rb").read()
    _sig, ver, _arv = struct.unpack_from("<III", d, 0)
    i = 12 if ver == 1 else 28
    achados = set()

    def texto():
        nonlocal i
        j = d.index(b"\0", i)
        r = d[i:j].decode("latin-1")
        i = j + 1
        return r
    while True:
        ext = texto()
        if not ext:
            break
        while True:
            pasta = texto()
            if not pasta:
                break
            while True:
                nome = texto()
                if not nome:
                    break
                pre = struct.unpack_from("<H", d, i + 4)[0]
                i += 18 + pre
                if ext == "vmt":
                    achados.add(((nome if pasta == " " else pasta + "/" + nome) + ".vmt").lower())
    return achados


def auditar(nome, b, jogo):
    falhas, avisos = [], []
    if b[:4] != b"VBSP":
        return ["nao e um arquivo de mapa (VBSP)"], avisos
    ent = lump(b, 0).decode("latin-1")
    pakb = lump(b, 40)
    pak = [n.replace("\\", "/") for n in zipfile.ZipFile(io.BytesIO(pakb)).namelist()] if pakb else []
    blocos = [re.findall(r'"([^"]*)"\s+"([^"]*)"', m.group(1)) for m in re.finditer(r"\{(.*?)\}", ent, re.S)]
    if not (nome.startswith("tfdb_") and "rocket_spawn_red" in ent and "rocket_spawn_blue" in ent):
        falhas.append("nao e mapa de Dodgeball (falta tfdb_ ou rocket_spawn_red/blue)")
    for pares in blocos:
        classe = dict(pares).get("classname", "")
        if classe in PERIGOSAS:
            falhas.append("entidade proibida: %s" % classe)
        for k, v in pares:
            if k.lower() in ("vscripts", "thinkfunction"):
                falhas.append("entidade com script: %s=%s" % (k, v[:60]))
            partes = re.split(r"[,\x1b]", v)
            if len(partes) >= 3 and partes[1] in ("RunScriptCode", "RunScriptFile", "CallScriptFunction"):
                falhas.append("saida que roda script: %s" % v.replace("\x1b", ",")[:80])
            elif len(partes) >= 3 and partes[1] == "Command" and not COMANDOS_OK.match(partes[2].strip()):
                falhas.append("comando de console fora da lista permitida: %s" % partes[2][:80])
    for n in pak:
        if n.endswith("/"):
            continue
        ext = n.rsplit(".", 1)[-1].lower() if "." in n.rsplit("/", 1)[-1] else ""
        if ext in EXT_PROIBIDA or n.lower().startswith(PASTA_PROIBIDA):
            falhas.append("arquivo embutido proibido: %s" % n)
        elif ext not in EXT_CONHECIDA:
            avisos.append("arquivo embutido de tipo pouco comum: %s" % n)
    if jogo:
        dados, tabela = lump(b, 43), lump(b, 44)
        no_mapa = set(n.lower() for n in pak)
        faltam = []
        for k in range(len(tabela) // 4):
            o = struct.unpack_from("<i", tabela, 4 * k)[0]
            m = dados[o:dados.index(b"\0", o)].decode("latin-1").lower().replace("\\", "/")
            if "materials/%s.vmt" % m not in jogo and "materials/%s.vmt" % m not in no_mapa:
                faltam.append(m)
        if faltam:
            falhas.append("texturas faltando (mapa ficaria roxo): %s" % ", ".join(sorted(set(faltam))[:5]))
    return falhas, avisos


def main():
    pasta, vpks = sys.argv[1], sys.argv[2:]
    somas = {}
    for linha in open(os.path.join(pasta, "SHA256SUMS")):
        if linha.strip():
            h, arq = linha.split()
            somas[arq.lstrip("*")] = h
    presentes = sorted(f for f in os.listdir(pasta) if f.endswith(".bsp.bz2"))
    erros = 0
    extras = sorted(set(presentes) - set(somas))
    if extras:
        print("ERRO: mapas sem sha256 registrado: %s" % ", ".join(extras))
        erros += 1
    jogo = set()
    for v in vpks:
        jogo |= materiais_do_jogo(v)
    print("texturas: %s" % ("conferidas contra %d materiais do jogo" % len(jogo) if jogo else "nao conferidas (sem .vpk)"))
    for arq in sorted(somas):
        caminho = os.path.join(pasta, arq)
        if not os.path.exists(caminho):
            print("ERRO  %-28s nao encontrado" % arq)
            erros += 1
            continue
        zb = open(caminho, "rb").read()
        if hashlib.sha256(zb).hexdigest() != somas[arq]:
            print("ERRO  %-28s sha256 diferente do registrado" % arq)
            erros += 1
            continue
        nome = arq[:-len(".bsp.bz2")]
        falhas, avisos = auditar(nome, bz2.decompress(zb), jogo)
        print("%s  %s" % ("ERRO" if falhas else "ok  ", nome))
        for f in falhas:
            print("        - %s" % f)
        for a in sorted(set(avisos))[:5]:
            print("        aviso: %s" % a)
        erros += bool(falhas)
    print("resultado: %s" % ("REPROVADO (%d)" % erros if erros else "todos os mapas aprovados"))
    sys.exit(1 if erros else 0)


if __name__ == "__main__":
    main()
