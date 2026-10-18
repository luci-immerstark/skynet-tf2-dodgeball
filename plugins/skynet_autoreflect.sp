#include <sourcemod>
#include <sdktools>
#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name = "SKYNET Auto Reflect",
    author = "SKYNET GAMING",
    description = "Auto reflect para admins (root) e o modo TODOS CONTRA O BOT, aberto por votacao dos admins",
    version = "3.0",
    url = "https://github.com/luci-immerstark/skynet-sourcemod-plugins"
};

// O sopro do Pyro pega projeteis dentro de uma caixa na frente dele: o centro fica 128 unidades a frente
// do olho e a caixa vai 128 para os lados e 64 para cima e para baixo. So sopra com o foguete dentro da
// caixa e com o sopro pronto; quanto mais rapido o foguete, mais cedo dentro da caixa.
//
// Modo BOT: um admin abre a votacao (!votebot). Se a maioria dos votos for "Sim", entra um bot Pyro no
// time azul que fica parado onde nasce e rebate sozinho; todos os jogadores vao para o vermelho.
// Com o modo ligado, !votebot abre a votacao para tirar o bot; !botoff tira na hora.

#define NOME_BOT "SKYNET BOT"
#define TIME_VERMELHO 2
#define TIME_AZUL 3

// Funcoes do plugin de Dodgeball (opcionais: sem elas, decide so pela posicao do foguete)
native int TFDB_FindRocketByEntity(int iEntity);
native int TFDB_GetRocketTarget(int iIndex);

bool g_bAuto[MAXPLAYERS + 1];
bool g_bTFDB;
ConVar g_cvFrente;
ConVar g_cvLado;
ConVar g_cvAltura;
ConVar g_cvEmergencia;
ConVar g_cvPerto;

bool g_bModoBot;
int g_iBot;
bool g_bTemAncora;
float g_fAncora[3];
int g_iBalanceAntes = 1;
int g_iLimiteAntes = 1;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
    MarkNativeAsOptional("TFDB_FindRocketByEntity");
    MarkNativeAsOptional("TFDB_GetRocketTarget");
    return APLRes_Success;
}

public void OnPluginStart()
{
    g_cvFrente     = CreateConVar("skynet_autoreflect_frente", "128", "Distancia do olho ate o centro da area do sopro", _, true, 32.0, true, 256.0);
    g_cvLado       = CreateConVar("skynet_autoreflect_lado", "112", "Metade da largura da area do sopro usada (o jogo usa 128; menor = mais seguro)", _, true, 32.0, true, 160.0);
    g_cvAltura     = CreateConVar("skynet_autoreflect_altura", "56", "Metade da altura da area do sopro usada (o jogo usa 64; menor = mais seguro)", _, true, 16.0, true, 96.0);
    g_cvEmergencia = CreateConVar("skynet_autoreflect_emergencia", "110", "Rebate qualquer foguete inimigo mais perto que isto, mesmo mirando outro jogador", _, true, 0.0, true, 300.0);
    g_cvPerto      = CreateConVar("skynet_autoreflect_perto", "180", "Com o foguete lento, espera ele chegar a esta distancia para soprar", _, true, 60.0, true, 256.0);
    RegAdminCmd("sm_autoreflect", Cmd_Auto, ADMFLAG_ROOT, "Liga/desliga o auto reflect (sem nome = em voce)");
    RegAdminCmd("sm_votebot", Cmd_VoteBot, ADMFLAG_VOTE, "Abre a votacao do modo TODOS CONTRA O BOT (ou para tirar o bot)");
    RegAdminCmd("sm_botoff", Cmd_BotOff, ADMFLAG_VOTE, "Tira o bot na hora");
    AddCommandListener(Ouvir_Time, "jointeam");
    AddCommandListener(Ouvir_Time, "autoteam");
    HookEvent("player_spawn", Ev_Spawn);
}

public void OnAllPluginsLoaded()
{
    g_bTFDB = GetFeatureStatus(FeatureType_Native, "TFDB_GetRocketTarget") == FeatureStatus_Available
           && GetFeatureStatus(FeatureType_Native, "TFDB_FindRocketByEntity") == FeatureStatus_Available;
}

public void OnPluginEnd()
{
    if (g_bModoBot)
        DesligarBot("");
}

public void OnMapEnd()
{
    if (g_bModoBot)
        DesligarBot("");
}

// ---------------------------------------------------------------- auto reflect em jogadores

public Action Cmd_Auto(int client, int args)
{
    int alvo = client;
    if (args >= 1)
    {
        char arg[64];
        GetCmdArg(1, arg, sizeof(arg));
        alvo = FindTarget(client, arg, true, false);
        if (alvo == -1)
            return Plugin_Handled;
    }
    if (alvo < 1 || !IsClientInGame(alvo))
    {
        ReplyToCommand(client, "[SKYNET] Use dentro do jogo ou informe um jogador.");
        return Plugin_Handled;
    }
    g_bAuto[alvo] = !g_bAuto[alvo];
    PrintToChatAll("\x04[SKYNET]\x01 Auto reflect %s para \x03%N\x01.", g_bAuto[alvo] ? "LIGADO" : "desligado", alvo);
    LogAction(client, alvo, "\"%L\" %s o auto reflect de \"%L\"", client, g_bAuto[alvo] ? "ligou" : "desligou", alvo);
    return Plugin_Handled;
}

// ---------------------------------------------------------------- modo TODOS CONTRA O BOT

public Action Cmd_VoteBot(int client, int args)
{
    if (IsVoteInProgress())
    {
        ReplyToCommand(client, "[SKYNET] Ja tem uma votacao em andamento.");
        return Plugin_Handled;
    }
    Menu menu = new Menu(H_Votacao, MENU_ACTIONS_ALL);
    menu.SetTitle(g_bModoBot ? "Tirar o SKYNET BOT e voltar ao normal?" : "Jogar TODOS CONTRA O BOT do auto reflect?");
    menu.AddItem("sim", "Sim");
    menu.AddItem("nao", "Nao");
    menu.ExitButton = false;
    menu.DisplayVoteToAll(20);
    PrintToChatAll("\x04[SKYNET]\x01 \x03%N\x01 abriu a votacao: %s Vote em 20 segundos.", client,
        g_bModoBot ? "tirar o SKYNET BOT?" : "todos contra o SKYNET BOT, que rebate tudo sozinho?");
    return Plugin_Handled;
}

public int H_Votacao(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_VoteCancel)
    {
        PrintToChatAll("\x04[SKYNET]\x01 Votacao encerrada sem votos.");
    }
    else if (action == MenuAction_VoteEnd)
    {
        int votos, total;
        GetMenuVoteInfo(param2, votos, total);
        char item[8];
        menu.GetItem(param1, item, sizeof(item));
        int sim = StrEqual(item, "sim") ? votos : total - votos;
        if (sim * 2 > total)
        {
            PrintToChatAll("\x04[SKYNET]\x01 Aprovado: %d de %d votos.", sim, total);
            if (g_bModoBot)
                DesligarBot("Votacao aprovada: o SKYNET BOT saiu.");
            else
                LigarBot();
        }
        else
        {
            PrintToChatAll("\x04[SKYNET]\x01 Nao aprovado: %d de %d votos no Sim (precisa de mais da metade).", sim, total);
        }
    }
    return 0;
}

public Action Cmd_BotOff(int client, int args)
{
    if (!g_bModoBot)
    {
        ReplyToCommand(client, "[SKYNET] O modo bot nao esta ligado.");
        return Plugin_Handled;
    }
    DesligarBot("Um admin tirou o SKYNET BOT.");
    return Plugin_Handled;
}

void LigarBot()
{
    ConVar balance = FindConVar("mp_autoteambalance");
    ConVar limite = FindConVar("mp_teams_unbalance_limit");
    g_iBalanceAntes = balance.IntValue;
    g_iLimiteAntes = limite.IntValue;
    balance.SetInt(0);
    limite.SetInt(0);
    ServerCommand("tf_bot_quota_mode normal");
    ServerCommand("tf_bot_quota 0");
    ServerCommand("tf_bot_auto_vacate 0");
    ServerCommand("tf_bot_keep_class_after_death 1");
    ServerCommand("tf_bot_taunt_victim_chance 0");

    // Todos os jogadores no vermelho antes do bot entrar no azul
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == TIME_AZUL)
            ChangeClientTeam(i, TIME_VERMELHO);
    }
    g_bModoBot = true;
    g_iBot = 0;
    g_bTemAncora = false;
    ServerCommand("tf_bot_add 1 pyro blue expert \"%s\"", NOME_BOT);
    PrintToChatAll("\x04[SKYNET]\x01 Modo \x03TODOS CONTRA O BOT\x01 ligado: todo mundo no time vermelho. O bot entra no azul.");
}

void DesligarBot(const char[] aviso)
{
    g_bModoBot = false;
    g_bTemAncora = false;
    if (g_iBot > 0 && IsClientInGame(g_iBot))
        KickClient(g_iBot, "Modo bot desligado");
    g_iBot = 0;
    ServerCommand("tf_bot_kick all");
    FindConVar("mp_autoteambalance").SetInt(g_iBalanceAntes);
    FindConVar("mp_teams_unbalance_limit").SetInt(g_iLimiteAntes);
    if (aviso[0])
        PrintToChatAll("\x04[SKYNET]\x01 %s Os times voltam ao normal.", aviso);
}

public void OnClientPutInServer(int client)
{
    if (!g_bModoBot || !IsFakeClient(client))
        return;
    char nome[MAX_NAME_LENGTH];
    GetClientName(client, nome, sizeof(nome));
    if (StrContains(nome, NOME_BOT) != -1)
    {
        g_iBot = client;
        g_bTemAncora = false;
    }
}

public void OnClientDisconnect(int client)
{
    g_bAuto[client] = false;
    if (!g_bModoBot)
        return;
    if (client == g_iBot)
    {
        g_iBot = 0;
        DesligarBot("O SKYNET BOT saiu do servidor.");
        return;
    }
    if (IsFakeClient(client))
        return;
    int humanos = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (i != client && IsClientInGame(i) && !IsFakeClient(i))
            humanos++;
    }
    if (humanos == 0)
        DesligarBot("");
}

// Com o modo bot ligado, jogador nao entra no azul: vai para o vermelho
public Action Ouvir_Time(int client, const char[] command, int argc)
{
    if (!g_bModoBot || client < 1 || !IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Continue;
    char arg[16];
    if (argc >= 1)
        GetCmdArg(1, arg, sizeof(arg));
    if (StrEqual(command, "jointeam", false) && (StrEqual(arg, "red", false) || StrContains(arg, "spec", false) == 0))
        return Plugin_Continue;
    FakeClientCommandEx(client, "jointeam red");
    return Plugin_Handled;
}

public void Ev_Spawn(Event event, const char[] name, bool dontBroadcast)
{
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (g_bModoBot && client > 0 && client == g_iBot)
    {
        g_bTemAncora = false;
        CreateTimer(0.2, T_Ancorar, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action T_Ancorar(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client > 0 && client == g_iBot && IsPlayerAlive(client))
    {
        GetClientAbsOrigin(client, g_fAncora);
        g_bTemAncora = true;
    }
    return Plugin_Stop;
}

// ---------------------------------------------------------------- rebater

// O ponto p esta dentro da area do sopro de quem olha de "olho" na direcao "dir"?
bool NaCaixa(const float olho[3], const float dir[3], const float p[3])
{
    float frente = g_cvFrente.FloatValue;
    float lado = g_cvLado.FloatValue;
    float altura = g_cvAltura.FloatValue;
    float c0 = olho[0] + dir[0] * frente;
    float c1 = olho[1] + dir[1] * frente;
    float c2 = olho[2] + dir[2] * frente;
    return FloatAbs(p[0] - c0) <= lado && FloatAbs(p[1] - c1) <= lado && FloatAbs(p[2] - c2) <= altura;
}

bool SoproPronto(int client)
{
    int arma = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (arma <= MaxClients || !IsValidEntity(arma) || !HasEntProp(arma, Prop_Send, "m_flNextSecondaryAttack"))
        return false;
    return GetEntPropFloat(arma, Prop_Send, "m_flNextSecondaryAttack") <= GetGameTime();
}

// Se tem foguete para rebater agora, aponta a mira para ele e devolve true
bool Refletir(int client, float angles[3])
{
    if (!SoproPronto(client))
        return false;
    float olho[3];
    GetClientEyePosition(client, olho);
    int equipe = GetClientTeam(client);
    float dt = GetTickInterval();
    float emergencia = g_cvEmergencia.FloatValue;

    int melhor = -1;
    float menor = 999999.0;
    float mira[3];
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "tf_projectile_rocket")) != -1)
    {
        float p[3], v[3], p1[3], meio[3], dir[3], ate[3];
        GetEntPropVector(ent, Prop_Data, "m_vecAbsOrigin", p);
        GetEntPropVector(ent, Prop_Data, "m_vecAbsVelocity", v);
        float d = GetVectorDistance(olho, p);

        int alvo = -1;
        if (g_bTFDB)
        {
            int idx = TFDB_FindRocketByEntity(ent);
            if (idx != -1)
                alvo = TFDB_GetRocketTarget(idx);
        }
        bool meu;
        if (alvo > 0)
            meu = (alvo == client) || (d <= emergencia && GetEntProp(ent, Prop_Send, "m_iTeamNum") != equipe);
        else
        {
            MakeVectorFromPoints(p, olho, ate);
            meu = GetEntProp(ent, Prop_Send, "m_iTeamNum") != equipe && GetVectorDotProduct(v, ate) > 0.0;
        }
        if (!meu)
            continue;

        for (int k = 0; k < 3; k++)
        {
            p1[k] = p[k] + v[k] * dt;
            meio[k] = (p[k] + p1[k]) * 0.5;
        }
        MakeVectorFromPoints(olho, meio, dir);
        NormalizeVector(dir, dir);
        if (!NaCaixa(olho, dir, p))
            continue;
        float passo = GetVectorLength(v) * dt;
        if (d > g_cvPerto.FloatValue && d - 2.0 * passo > 60.0)
            continue;
        if (d < menor)
        {
            menor = d;
            melhor = ent;
            mira = dir;
        }
    }
    if (melhor == -1)
        return false;

    float ang[3];
    GetVectorAngles(mira, ang);
    if (ang[0] > 180.0)
        ang[0] -= 360.0;
    angles[0] = ang[0];
    angles[1] = ang[1];
    angles[2] = 0.0;
    TeleportEntity(client, NULL_VECTOR, angles, NULL_VECTOR);
    return true;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    // O bot: fica parado onde nasceu e so sopra (nada de andar ou soltar fogo)
    if (g_bModoBot && client == g_iBot)
    {
        vel[0] = 0.0;
        vel[1] = 0.0;
        vel[2] = 0.0;
        buttons = 0;
        impulse = 0;
        weapon = 0;
        if (IsPlayerAlive(client))
        {
            if (g_bTemAncora)
            {
                float agora[3], parado[3];
                GetClientAbsOrigin(client, agora);
                if (GetVectorDistance(agora, g_fAncora) > 16.0)
                    TeleportEntity(client, g_fAncora, NULL_VECTOR, parado);
            }
            if (Refletir(client, angles))
                buttons |= IN_ATTACK2;
        }
        return Plugin_Changed;
    }

    if (!g_bAuto[client] || !IsPlayerAlive(client))
        return Plugin_Continue;
    if (!Refletir(client, angles))
        return Plugin_Continue;
    buttons |= IN_ATTACK2;
    return Plugin_Changed;
}
