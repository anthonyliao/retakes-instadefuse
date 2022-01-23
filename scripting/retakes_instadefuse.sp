#include <sourcemod>
#include <sdktools>
#include <cstrike>

#pragma semicolon 1
#pragma newdecls required

#define MESSAGE_PREFIX "[\x04InstantDefuse\x01]"

Handle hEndIfTooLate = null;
Handle hDefuseIfTime = null;
Handle hInfernoDuration = null;
Handle hTimer_MolotovThreatEnd = null;

Handle fw_OnInstantDefusePre = null;
Handle fw_OnInstantDefusePost = null;

float g_c4PlantTime = 0.0;
bool g_bAlreadyComplete = false;
bool g_bWouldMakeIt = false;

public Plugin myinfo =
{
    name = "[Retakes] Instant Defuse",
    author = "B3none",
    description = "Allows a CT to instantly defuse the bomb when all Ts are dead and nothing can prevent the defusal.",
    version = "1.4.0",
    url = "https://github.com/b3none"
}

public void OnPluginStart()
{
    PrintToServer("%s Plugin loaded", MESSAGE_PREFIX);
    PrintToChatAll("%s Plugin loaded", MESSAGE_PREFIX);

    HookEvent("bomb_begindefuse", Event_BombBeginDefuse, EventHookMode_Post);
    HookEvent("bomb_planted", Event_BombPlanted, EventHookMode_Pre);
    HookEvent("molotov_detonate", Event_MolotovDetonate);
    HookEvent("hegrenade_detonate", Event_AttemptInstantDefuse, EventHookMode_Post);

    HookEvent("player_death", Event_AttemptInstantDefuse, EventHookMode_PostNoCopy);
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

    hInfernoDuration = CreateConVar("instant_defuse_inferno_duration", "7.0", "If Valve ever changed the duration of molotov, this cvar should change with it.");
    hEndIfTooLate = CreateConVar("instant_defuse_end_if_too_late", "0", "End the round if too late.");
    hDefuseIfTime = CreateConVar("instant_defuse_if_time", "1", "Instant defuse if there is time to do so.");

    // Added the forwards to allow other plugins to call this one.
    fw_OnInstantDefusePre = CreateGlobalForward("InstantDefuse_OnInstantDefusePre", ET_Event, Param_Cell, Param_Cell);
    fw_OnInstantDefusePost = CreateGlobalForward("InstantDefuse_OnInstantDefusePost", ET_Ignore, Param_Cell, Param_Cell);
}

public void OnMapStart()
{
    hTimer_MolotovThreatEnd = null;
}

public Action Event_RoundStart(Handle event, const char[] name, bool dontBroadcast)
{
    g_bAlreadyComplete = false;
    g_bWouldMakeIt = false;

    if (hTimer_MolotovThreatEnd != null)
    {
        delete hTimer_MolotovThreatEnd;
    }

    return Plugin_Continue;
}

public Action Event_BombPlanted(Handle event, const char[] name, bool dontBroadcast)
{
    g_c4PlantTime = GetGameTime();

    return Plugin_Continue;
}

public Action Event_BombBeginDefuse(Handle event, const char[] name, bool dontBroadcast)
{
    if (g_bAlreadyComplete)
    {
        return Plugin_Handled;
    }

    RequestFrame(Event_BombBeginDefusePlusFrame, GetEventInt(event, "userid"));

    return Plugin_Continue;
}

public void Event_BombBeginDefusePlusFrame(int userId)
{
    g_bWouldMakeIt = false;

    int client = GetClientOfUserId(userId);

    if (IsClientValid(client))
    {
        AttemptInstantDefuse(client);
    }
}

void AttemptInstantDefuse(int client)
{
    if (g_bAlreadyComplete || !GetEntProp(client, Prop_Send, "m_bIsDefusing") || HasAlivePlayer(CS_TEAM_T))
    {
        // PrintToChatAll("%s Can't instant defuse. Ts still alive.", MESSAGE_PREFIX);
        return;
    }

    int StartEnt = MaxClients + 1;

    int c4 = FindEntityByClassname(StartEnt, "planted_c4");

    if (c4 == -1)
    {
        return;
    }

    bool hasDefuseKit = HasDefuseKit(client);
    float c4TimeLeft = GetConVarFloat(FindConVar("mp_c4timer")) - (GetGameTime() - g_c4PlantTime);

    g_bWouldMakeIt = (c4TimeLeft >= 10.0 && !hasDefuseKit) || (c4TimeLeft >= 5.0 && hasDefuseKit);

    if (!g_bWouldMakeIt)
    {
        if (GetConVarInt(hEndIfTooLate) != 1) 
        {
            return;
        }
        
        if (!OnInstantDefusePre(client, c4))
        {
            return;
        }

        PrintToChatAll("%s CT can't defuse in time. Ts win", MESSAGE_PREFIX);

        g_bAlreadyComplete = true;

        // Force Terrorist win because they do not have enough time to defuse the bomb.
        EndRound(CS_TEAM_T);

        return;
    }
    else if (GetConVarInt(hDefuseIfTime) != 1 || GetEntityFlags(client) && !FL_ONGROUND)
    {
        return;
    }

    if (FindEntityByClassname(StartEnt, "hegrenade_projectile") != -1 || FindEntityByClassname(StartEnt, "molotov_projectile") != -1)
    {
        PrintToChatAll("%s Can't instant defuse. There's an active nade/molly.", MESSAGE_PREFIX);
        return;
    }
    else if (hTimer_MolotovThreatEnd != null)
    {
        PrintToChatAll("%s Can't instant defuse. There's an active molly.", MESSAGE_PREFIX);
        return;
    }
    
    if (!OnInstantDefusePre(client, c4))
    {
        return;
    }

    PrintToChatAll("%s CTs instant defused with %f seconds remaining.", MESSAGE_PREFIX, c4TimeLeft);

    g_bAlreadyComplete = true;

    EndRound(CS_TEAM_CT);

    OnInstantDefusePost(client, c4);
}

public Action Event_AttemptInstantDefuse(Handle event, const char[] name, bool dontBroadcast)
{
    int defuser = GetDefusingPlayer();

    if (StrContains(name, "detonate") != -1 && defuser != 0)
    {
        AttemptInstantDefuse(defuser);
    }

    return Plugin_Continue;
}

public Action Event_MolotovDetonate(Handle event, const char[] name, bool dontBroadcast)
{
    float Origin[3];
    Origin[0] = GetEventFloat(event, "x");
    Origin[1] = GetEventFloat(event, "y");
    Origin[2] = GetEventFloat(event, "z");

    int c4 = FindEntityByClassname(MaxClients + 1, "planted_c4");

    if (c4 == -1)
    {
        return Plugin_Continue;
    }

    float C4Origin[3];
    GetEntPropVector(c4, Prop_Data, "m_vecOrigin", C4Origin);

    if (GetVectorDistance(Origin, C4Origin, false) > 150)
    {
        return Plugin_Continue;
    }

    if (hTimer_MolotovThreatEnd != null)
    {
        delete hTimer_MolotovThreatEnd;
    }

    hTimer_MolotovThreatEnd = CreateTimer(GetConVarFloat(hInfernoDuration), Timer_MolotovThreatEnd, _, TIMER_FLAG_NO_MAPCHANGE);

    return Plugin_Continue;
}

public Action Timer_MolotovThreatEnd(Handle timer)
{
    hTimer_MolotovThreatEnd = null;

    int defuser = GetDefusingPlayer();

    if (defuser != 0)
    {
        AttemptInstantDefuse(defuser);
    }

    return Plugin_Continue;
}

void OnInstantDefusePost(int client, int c4)
{
    Call_StartForward(fw_OnInstantDefusePost);

    Call_PushCell(client);
    Call_PushCell(c4);

    Call_Finish();
}

void EndRound(int team, bool waitFrame = true)
{
    if (waitFrame)
    {
        RequestFrame(Frame_EndRound, team);

        return;
    }

    Frame_EndRound(team);
}

void Frame_EndRound(int team)
{
    int RoundEndEntity = CreateEntityByName("game_round_end");

    DispatchSpawn(RoundEndEntity);

    SetVariantFloat(1.0);

    if (team == CS_TEAM_CT)
    {
        AcceptEntityInput(RoundEndEntity, "EndRound_CounterTerroristsWin");
    }
    else if (team == CS_TEAM_T)
    {
        AcceptEntityInput(RoundEndEntity, "EndRound_TerroristsWin");
    }

    AcceptEntityInput(RoundEndEntity, "Kill");
}

stock int GetDefusingPlayer()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientValid(i) && IsPlayerAlive(i) && GetEntProp(i, Prop_Send, "m_bIsDefusing"))
        {
            return i;
        }
    }

    return 0;
}

stock bool OnInstantDefusePre(int client, int c4)
{
    Action response;

    Call_StartForward(fw_OnInstantDefusePre);
    Call_PushCell(client);
    Call_PushCell(c4);
    Call_Finish(response);

    return !(response != Plugin_Continue && response != Plugin_Changed);
}

bool HasDefuseKit(int client)
{
    bool hasDefuseKit = GetEntProp(client, Prop_Send, "m_bHasDefuser") == 1;
    return hasDefuseKit;
}

stock bool HasAlivePlayer(int team)
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientValid(i) && IsPlayerAlive(i) && GetClientTeam(i) == team)
        {
            return true;
        }
    }

    return false;
}

stock bool IsClientValid(int client)
{
    return client > 0 && client <= MaxClients && IsClientInGame(client) && !IsClientSourceTV(client);
}
