#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo =
{
    name = "SKYNET Pyro Only",
    author = "SKYNET GAMING",
    description = "Dodgeball: todo mundo entra como Pyro, sem menu de classes e sem troca de classe",
    version = "1.0",
    url = "https://github.com/luci-immerstark/skynet-sourcemod-plugins"
};

public void OnPluginStart()
{
    AddCommandListener(Cmd_JoinClass, "joinclass");
    AddCommandListener(Cmd_JoinClass, "join_class");
    HookEvent("player_team", Ev_PlayerTeam, EventHookMode_Post);
    UserMsg vgui = GetUserMessageId("VGUIMenu");
    if (vgui != INVALID_MESSAGE_ID)
        HookUserMessage(vgui, Msg_VGUIMenu, true);
}

// Impede o servidor de abrir o menu de classes
public Action Msg_VGUIMenu(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
    char panel[32];
    msg.ReadString(panel, sizeof(panel));
    if (StrEqual(panel, "class_red") || StrEqual(panel, "class_blue"))
        return Plugin_Handled;
    return Plugin_Continue;
}

// Entrou num time: escolhe Pyro sozinho
public void Ev_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
    if (event.GetInt("team") < 2)
        return;
    CreateTimer(0.2, Timer_ForcePyro, event.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_ForcePyro(Handle timer, any userid)
{
    int client = GetClientOfUserId(userid);
    if (client < 1 || !IsClientInGame(client) || IsFakeClient(client) || GetClientTeam(client) < 2)
        return Plugin_Stop;
    if (TF2_GetPlayerClass(client) != TFClass_Pyro)
        FakeClientCommandEx(client, "joinclass pyro");
    return Plugin_Stop;
}

// Qualquer escolha de classe diferente de Pyro e recusada
public Action Cmd_JoinClass(int client, const char[] command, int argc)
{
    if (client < 1 || client > MaxClients || !IsClientInGame(client))
        return Plugin_Continue;
    char arg[32];
    GetCmdArg(1, arg, sizeof(arg));
    if (StrEqual(arg, "pyro", false))
        return Plugin_Continue;
    if (TF2_GetPlayerClass(client) == TFClass_Pyro)
        PrintToChat(client, "\x07FFD700[SKYNET GAMING]\x01 Este servidor é só de \x0700E5FFPyro\x01.");
    else
        FakeClientCommandEx(client, "joinclass pyro");
    return Plugin_Handled;
}
