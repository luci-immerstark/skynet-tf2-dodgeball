#include <sourcemod>
#pragma semicolon 1
#pragma newdecls required

#define MAX_MAPS 64
#define MAX_OPTS 5
#define NUNCA -100000

public Plugin myinfo =
{
    name = "SKYNET Map Vote",
    author = "SKYNET GAMING",
    description = "Votacao do proximo mapa: opcoes escolhidas por hype, tempo sem jogar e tempo fora da votacao",
    version = "1.2",
    url = "https://github.com/luci-immerstark/skynet-sourcemod-plugins"
};

ConVar g_cvVoteTime, g_cvCooldown, g_cvStarve, g_cvOptions;
ConVar g_cvHypeExp, g_cvRecentPenalty, g_cvVoteGrow, g_cvVoteCap, g_cvPlayGrow, g_cvPlayCap;

char g_Map[MAX_MAPS][PLATFORM_MAX_PATH];
int g_Hype[MAX_MAPS];
int g_LastPlayed[MAX_MAPS];
int g_LastVoted[MAX_MAPS];
int g_Count;
int g_MapCounter;
int g_VoteCounter;
bool g_VoteStarted;
int g_RoundsPlayed;
Handle g_VoteTimer = null;
ConVar g_cvVoteDelay, g_cvMaxRounds, g_cvBefore;
char g_ConfigFile[PLATFORM_MAX_PATH];
char g_StateFile[PLATFORM_MAX_PATH];
int g_Opt[MAX_OPTS];
int g_OptCount;

public void OnPluginStart()
{
    g_cvVoteTime      = CreateConVar("skynet_mapvote_time", "20", "Duracao da votacao, em segundos", _, true, 10.0, true, 60.0);
    g_cvCooldown      = CreateConVar("skynet_mapvote_cooldown", "3", "Mapas jogados nas ultimas N partidas ficam fora da votacao", _, true, 0.0);
    g_cvStarve        = CreateConVar("skynet_mapvote_starve", "12", "Mapa que nao aparece na votacao ha N votacoes ganha vaga garantida", _, true, 2.0);
    g_cvOptions       = CreateConVar("skynet_mapvote_options", "3", "Quantidade de mapas em cada votacao", _, true, 2.0, true, 5.0);
    g_cvHypeExp       = CreateConVar("skynet_mapvote_hype_exp", "2.5", "Forca do hype no sorteio (hype elevado a este numero)", _, true, 0.0);
    g_cvRecentPenalty = CreateConVar("skynet_mapvote_recent_penalty", "0.8", "Multiplicador para quem apareceu na ultima votacao", _, true, 0.0);
    g_cvVoteGrow      = CreateConVar("skynet_mapvote_vote_grow", "0.10", "Bonus por votacao sem aparecer", _, true, 0.0);
    g_cvVoteCap       = CreateConVar("skynet_mapvote_vote_cap", "1.8", "Bonus maximo por tempo fora da votacao", _, true, 1.0);
    g_cvPlayGrow      = CreateConVar("skynet_mapvote_play_grow", "0.10", "Bonus por partida sem ser jogado (depois do cooldown)", _, true, 0.0);
    g_cvPlayCap       = CreateConVar("skynet_mapvote_play_cap", "1.8", "Bonus maximo por tempo sem ser jogado", _, true, 1.0);
    g_cvVoteDelay     = CreateConVar("skynet_mapvote_delay", "180", "Segundos depois do inicio da ultima rodada para abrir a votacao", _, true, 30.0);
    g_cvMaxRounds     = FindConVar("mp_maxrounds");
    g_cvBefore        = CreateConVar("skynet_mapvote_before", "180", "Abre a votacao quando faltar este tempo (segundos) para o fim do mapa pelo mp_timelimit. 0 = usa o modo por rodadas", _, true, 0.0);
    AutoExecConfig(true, "skynet_mapvote");

    BuildPath(Path_SM, g_ConfigFile, sizeof(g_ConfigFile), "configs/skynet_mapvote.txt");
    BuildPath(Path_SM, g_StateFile, sizeof(g_StateFile), "configs/skynet_mapvote_state.txt");

    HookEventEx("teamplay_game_over", Ev_GameOver, EventHookMode_PostNoCopy);
    HookEventEx("tf_game_over", Ev_GameOver, EventHookMode_PostNoCopy);
    HookEventEx("teamplay_round_win", Ev_RoundWin, EventHookMode_PostNoCopy);
    HookEventEx("teamplay_round_start", Ev_RoundStart, EventHookMode_PostNoCopy);

    RegAdminCmd("sm_mapvote_status", Cmd_Status, ADMFLAG_CHANGEMAP, "Mostra o hype, o historico e o peso de cada mapa");
    RegAdminCmd("sm_mapvote_now", Cmd_Now, ADMFLAG_CHANGEMAP, "Inicia agora a votacao do proximo mapa");
}

int IntMax(int a, int b) { return a > b ? a : b; }

int FindMapIndex(const char[] map)
{
    for (int i = 0; i < g_Count; i++)
        if (StrEqual(g_Map[i], map, false))
            return i;
    return -1;
}

void MV_LoadMaps()
{
    g_Count = 0;
    KeyValues kv = new KeyValues("SkynetMapVote");
    if (!kv.ImportFromFile(g_ConfigFile))
    {
        LogError("Arquivo de hype nao encontrado: %s", g_ConfigFile);
        delete kv;
        return;
    }
    if (kv.GotoFirstSubKey(false))
    {
        do
        {
            if (g_Count >= MAX_MAPS)
                break;
            char map[PLATFORM_MAX_PATH];
            kv.GetSectionName(map, sizeof(map));
            int hype = kv.GetNum(NULL_STRING, 3);
            if (!IsMapValid(map))
            {
                LogError("Mapa %s nao esta instalado e foi ignorado", map);
                continue;
            }
            strcopy(g_Map[g_Count], sizeof(g_Map[]), map);
            g_Hype[g_Count] = hype < 0 ? 0 : (hype > 5 ? 5 : hype);
            g_LastPlayed[g_Count] = NUNCA;
            g_LastVoted[g_Count] = NUNCA;
            g_Count++;
        } while (kv.GotoNextKey(false));
    }
    delete kv;
}

void MV_LoadState()
{
    g_MapCounter = 0;
    g_VoteCounter = 0;
    KeyValues kv = new KeyValues("SkynetMapVoteState");
    if (kv.ImportFromFile(g_StateFile))
    {
        g_MapCounter = kv.GetNum("map_counter", 0);
        g_VoteCounter = kv.GetNum("vote_counter", 0);
        if (kv.JumpToKey("maps"))
        {
            for (int i = 0; i < g_Count; i++)
            {
                if (kv.JumpToKey(g_Map[i]))
                {
                    g_LastPlayed[i] = kv.GetNum("played", NUNCA);
                    g_LastVoted[i] = kv.GetNum("voted", NUNCA);
                    kv.GoBack();
                }
            }
        }
    }
    delete kv;
}

void MV_SaveState()
{
    KeyValues kv = new KeyValues("SkynetMapVoteState");
    kv.SetNum("map_counter", g_MapCounter);
    kv.SetNum("vote_counter", g_VoteCounter);
    kv.JumpToKey("maps", true);
    for (int i = 0; i < g_Count; i++)
    {
        kv.JumpToKey(g_Map[i], true);
        kv.SetNum("played", g_LastPlayed[i]);
        kv.SetNum("voted", g_LastVoted[i]);
        kv.GoBack();
    }
    kv.Rewind();
    kv.ExportToFile(g_StateFile);
    delete kv;
}

public void OnMapStart()
{
    MV_LoadMaps();
    MV_LoadState();
    g_MapCounter++;
    char cur[PLATFORM_MAX_PATH];
    GetCurrentMap(cur, sizeof(cur));
    int i = FindMapIndex(cur);
    if (i != -1)
        g_LastPlayed[i] = g_MapCounter;
    MV_SaveState();
    g_VoteStarted = false;
    g_RoundsPlayed = 0;
    g_VoteTimer = null;
    CreateTimer(5.0, Timer_CheckTimeLeft, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

// Modo por tempo (mapas com mp_timelimit, como os de Dodgeball): abre a votacao quando falta pouco para o fim do mapa
public Action Timer_CheckTimeLeft(Handle timer)
{
    int before = g_cvBefore.IntValue;
    if (g_VoteStarted || before <= 0)
        return Plugin_Continue;
    int timeleft;
    if (GetMapTimeLeft(timeleft) && timeleft > 0 && timeleft <= before)
        StartMapVote();
    return Plugin_Continue;
}

public void OnConfigsExecuted()
{
    CreateTimer(5.0, Timer_ProvisionalNext, _, TIMER_FLAG_NO_MAPCHANGE);
}

// Proximo mapa provisorio, para o caso de a votacao nao acontecer (ex.: a partida nao chega ao fim)
public Action Timer_ProvisionalNext(Handle timer)
{
    int pick[MAX_OPTS];
    if (BuildOptions(pick, 1, false) > 0)
        SetNextMap(g_Map[pick[0]]);
    return Plugin_Stop;
}

float Weight(int i, int nextVote)
{
    int cooldown = g_cvCooldown.IntValue;
    int sinceP = g_MapCounter - g_LastPlayed[i];
    int sinceV = nextVote - g_LastVoted[i];
    float w = Pow(float(g_Hype[i]), g_cvHypeExp.FloatValue);
    float fp = 1.0 + g_cvPlayGrow.FloatValue * float(IntMax(sinceP - cooldown, 0));
    if (fp > g_cvPlayCap.FloatValue)
        fp = g_cvPlayCap.FloatValue;
    float fv;
    if (sinceV == 1)
        fv = g_cvRecentPenalty.FloatValue;
    else
    {
        fv = 1.0 + g_cvVoteGrow.FloatValue * float(IntMax(sinceV - 1, 0));
        if (fv > g_cvVoteCap.FloatValue)
            fv = g_cvVoteCap.FloatValue;
    }
    return w * fp * fv;
}

int BuildOptions(int[] out, int wanted, bool registerVote)
{
    int nextVote = g_VoteCounter + 1;
    int cooldown = g_cvCooldown.IntValue;
    char cur[PLATFORM_MAX_PATH];
    GetCurrentMap(cur, sizeof(cur));

    int pool[MAX_MAPS];
    int poolCount = 0;
    for (int i = 0; i < g_Count; i++)
    {
        if (g_Hype[i] <= 0 || StrEqual(g_Map[i], cur, false))
            continue;
        if (g_MapCounter - g_LastPlayed[i] <= cooldown)
            continue;
        pool[poolCount++] = i;
    }
    // Poucos mapas fora do cooldown: completa com os que estao no cooldown
    if (poolCount < wanted)
    {
        for (int i = 0; i < g_Count; i++)
        {
            if (g_Hype[i] <= 0 || StrEqual(g_Map[i], cur, false))
                continue;
            bool already = false;
            for (int k = 0; k < poolCount; k++)
                if (pool[k] == i) { already = true; break; }
            if (!already)
                pool[poolCount++] = i;
        }
    }

    int n = 0;
    // Vaga garantida para o mapa ha mais tempo fora da votacao
    int starve = g_cvStarve.IntValue;
    int best = -1, bestSince = -1;
    for (int k = 0; k < poolCount; k++)
    {
        int s = nextVote - g_LastVoted[pool[k]];
        if (s >= starve && s > bestSince)
        {
            best = k;
            bestSince = s;
        }
    }
    if (best != -1 && n < wanted)
    {
        out[n++] = pool[best];
        pool[best] = pool[--poolCount];
    }
    // Sorteio ponderado, sem repetir mapa
    while (n < wanted && poolCount > 0)
    {
        float total = 0.0;
        for (int k = 0; k < poolCount; k++)
            total += Weight(pool[k], nextVote);
        float r = GetURandomFloat() * total;
        int chosen = poolCount - 1;
        float acc = 0.0;
        for (int k = 0; k < poolCount; k++)
        {
            acc += Weight(pool[k], nextVote);
            if (acc >= r) { chosen = k; break; }
        }
        out[n++] = pool[chosen];
        pool[chosen] = pool[--poolCount];
    }

    if (registerVote && n > 0)
    {
        g_VoteCounter = nextVote;
        for (int k = 0; k < n; k++)
            g_LastVoted[out[k]] = nextVote;
        MV_SaveState();
    }
    return n;
}

int CountHumans()
{
    int c = 0;
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i) && !IsFakeClient(i) && !IsClientSourceTV(i))
            c++;
    return c;
}

public void Ev_RoundWin(Event event, const char[] name, bool dontBroadcast)
{
    g_RoundsPlayed++;
}

// A votacao abre durante a ultima rodada, com o pessoal jogando (no placar final o menu fica escondido)
public void Ev_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    if (g_VoteStarted || g_cvBefore.IntValue > 0)
        return;
    int maxrounds = g_cvMaxRounds != null ? g_cvMaxRounds.IntValue : 1;
    if (maxrounds < 1)
        maxrounds = 1;
    if (g_RoundsPlayed < maxrounds - 1)
        return;
    delete g_VoteTimer;
    g_VoteTimer = CreateTimer(g_cvVoteDelay.FloatValue, Timer_StartVote, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_StartVote(Handle timer)
{
    g_VoteTimer = null;
    StartMapVote();
    return Plugin_Stop;
}

// Se a rodada acabou antes da votacao abrir, fica o proximo mapa ja sorteado pelo mesmo sistema
public void Ev_GameOver(Event event, const char[] name, bool dontBroadcast)
{
    if (g_VoteStarted)
        return;
    g_VoteStarted = true;
    delete g_VoteTimer;
    char next[PLATFORM_MAX_PATH];
    if (GetNextMap(next, sizeof(next)))
        PrintToChatAll("\x07FFD700[SKYNET GAMING]\x01 Próximo mapa: \x0700E5FF%s\x01.", next);
}

void StartMapVote()
{
    if (g_VoteStarted)
        return;
    g_VoteStarted = true;

    int wanted = g_cvOptions.IntValue;
    if (wanted > MAX_OPTS)
        wanted = MAX_OPTS;
    g_OptCount = BuildOptions(g_Opt, wanted, true);
    if (g_OptCount == 0)
        return;
    if (g_OptCount == 1 || CountHumans() == 0 || IsVoteInProgress())
    {
        SetNextMap(g_Map[g_Opt[0]]);
        return;
    }

    Menu menu = new Menu(Handler_Vote, MENU_ACTIONS_ALL);
    menu.SetTitle("Vote no proximo mapa:");
    for (int k = 0; k < g_OptCount; k++)
        menu.AddItem(g_Map[g_Opt[k]], g_Map[g_Opt[k]]);
    menu.ExitButton = false;
    menu.DisplayVoteToAll(g_cvVoteTime.IntValue);
    PrintToChatAll("\x07FFD700[SKYNET GAMING]\x01 Vote no próximo mapa! Use as teclas \x0700E5FF1\x01, \x0700E5FF2\x01 ou \x0700E5FF3\x01.");
}

public int Handler_Vote(Menu menu, MenuAction action, int param1, int param2)
{
    if (action == MenuAction_End)
    {
        delete menu;
    }
    else if (action == MenuAction_VoteEnd)
    {
        char map[PLATFORM_MAX_PATH];
        menu.GetItem(param1, map, sizeof(map));
        int votes, total;
        GetMenuVoteInfo(param2, votes, total);
        SetNextMap(map);
        PrintToChatAll("\x07FFD700[SKYNET GAMING]\x01 Próximo mapa: \x0700E5FF%s\x01 (%d de %d votos). Ele começa quando este mapa terminar.", map, votes, total);
    }
    else if (action == MenuAction_VoteCancel && g_OptCount > 0)
    {
        SetNextMap(g_Map[g_Opt[0]]);
        PrintToChatAll("\x07FFD700[SKYNET GAMING]\x01 Ninguém votou. Próximo mapa: \x0700E5FF%s\x01. Ele começa quando este mapa terminar.", g_Map[g_Opt[0]]);
    }
    return 0;
}

public Action Cmd_Status(int client, int args)
{
    int nextVote = g_VoteCounter + 1;
    int cooldown = g_cvCooldown.IntValue;
    ReplyToCommand(client, "[SKYNET] mapa | hype | partidas sem jogar | votacoes sem aparecer | peso");
    for (int i = 0; i < g_Count; i++)
    {
        int sinceP = g_MapCounter - g_LastPlayed[i];
        int sinceV = nextVote - g_LastVoted[i];
        char sp[16], sv[16];
        if (sinceP > 50000) strcopy(sp, sizeof(sp), "nunca"); else IntToString(sinceP, sp, sizeof(sp));
        if (sinceV > 50000) strcopy(sv, sizeof(sv), "nunca"); else IntToString(sinceV - 1, sv, sizeof(sv));
        bool cd = sinceP <= cooldown;
        ReplyToCommand(client, "%s | %d | %s | %s | %.1f%s", g_Map[i], g_Hype[i], sp, sv,
            (cd || g_Hype[i] <= 0) ? 0.0 : Weight(i, nextVote), cd ? " (recente, fora)" : "");
    }
    return Plugin_Handled;
}

public Action Cmd_Now(int client, int args)
{
    g_VoteStarted = false;
    StartMapVote();
    return Plugin_Handled;
}
