#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <sourcescramble>
#include <dhooks>

#define PLUGIN_VERSION "2.4"

public Plugin myinfo =
{
	name = "[L4D2] Checkpoint Spit Spread Control",
	author = "Forgetest",
	description = "Allow spit to spread in saferoom",
	version = PLUGIN_VERSION,
	url = "https://github.com/Target5150/MoYu_Server_Stupid_Plugins"
}

#define GAMEDATA_FILE "l4d2_checkpoint_spit_control"
#define KEY_DETONATE "CSpitterProjectile_Detonate"
#define KEY_BOUNCETOUCH "CSpitterProjectile_BounceTouch"

#define PATCH_SAFEROOM "SaferoomPatch"
#define PATCH_BRUSH_1 "BrushPatch1"
#define PATCH_BRUSH_2 "BrushPatch2"
#define PATCH_BRUSH_3 "BrushPatch3"

bool g_bLinux;
MemoryPatch g_hSaferoomPatch, g_hBrushPatch1, g_hBrushPatch2, g_hBrushPatch3;
DynamicDetour g_hDetour_Detonate, g_hDetour_BounceTouch;

ConVar g_hAllMaps, g_hAllIntros, g_hAllEntities;
StringMap g_hSpitSpreadMaps, g_hSpitSpreadExceptions;

// ==============================
// GameData
// ==============================
void LoadSDK()
{
	Handle conf = LoadGameConfigFile(GAMEDATA_FILE);
	if (conf == null)
		SetFailState("Missing gamedata \"" ... GAMEDATA_FILE ... "\"");
	
	int offset = GameConfGetOffset(conf, "OS");
	if (offset == -1)
		SetFailState("Failed to get offset \"OS\"");
		
	g_bLinux = !offset;
	
	g_hSaferoomPatch = MemoryPatch.CreateFromConf(conf, PATCH_SAFEROOM);
	if (!g_hSaferoomPatch || !g_hSaferoomPatch.Validate())
		SetFailState("Failed to validate patch \"" ... PATCH_SAFEROOM ... "\"");
	
	if (g_bLinux)
	{
		g_hBrushPatch1 = MemoryPatch.CreateFromConf(conf, PATCH_BRUSH_1);
		if (!g_hBrushPatch1 || !g_hBrushPatch1.Validate())
			SetFailState("Failed to validate patch \"" ... PATCH_BRUSH_1 ... "\"");
	}
	
	g_hBrushPatch2 = MemoryPatch.CreateFromConf(conf, PATCH_BRUSH_2);
	if (!g_hBrushPatch2 || !g_hBrushPatch2.Validate())
		SetFailState("Failed to validate patch \"" ... PATCH_BRUSH_2 ... "\"");
	
	g_hBrushPatch3 = MemoryPatch.CreateFromConf(conf, PATCH_BRUSH_3);
	if (!g_hBrushPatch3 || !g_hBrushPatch3.Validate())
		SetFailState("Failed to validate patch \"" ... PATCH_BRUSH_3 ... "\"");
	
	SetupDetour(conf);
	
	delete conf;
}

void SetupDetour(Handle conf)
{
	g_hDetour_Detonate = DynamicDetour.FromConf(conf, KEY_DETONATE);
	if (g_hDetour_Detonate == null)
		SetFailState("Missing detour setup \"" ... KEY_DETONATE ... "\"");
	
	g_hDetour_BounceTouch = DynamicDetour.FromConf(conf, KEY_BOUNCETOUCH);
	if (g_hDetour_BounceTouch == null)
		SetFailState("Missing detour setup \"" ... KEY_BOUNCETOUCH ... "\"");
}

// ==============================
// Patch togglers
// ==============================
void ApplySaferoomPatch(bool patch)
{
	static bool patched = false;
	
	if (patch && !patched)
	{
		if (!g_hSaferoomPatch.Enable())
			SetFailState("Failed to apply patch \"" ... PATCH_SAFEROOM ... "\"");
		
		patched = true;
	}
	else if (!patch && patched)
	{
		g_hSaferoomPatch.Disable();
		patched = false;
	}
}

void ApplyBrushPatch(bool patch)
{
	static bool patched = false;
	
	if (patch && !patched)
	{
		if (g_bLinux && !g_hBrushPatch1.Enable())
			SetFailState("Failed to apply patch \"" ... PATCH_BRUSH_1 ... "\"");
		
		if (!g_hBrushPatch2.Enable())
			SetFailState("Failed to apply patch \"" ... PATCH_BRUSH_2 ... "\"");
		
		if (!g_hBrushPatch3.Enable())
			SetFailState("Failed to apply patch \"" ... PATCH_BRUSH_3 ... "\"");
		
		patched = true;
	}
	else if (!patch && patched)
	{
		if (g_bLinux) g_hBrushPatch1.Disable();
		g_hBrushPatch2.Disable();
		g_hBrushPatch3.Disable();
		patched = false;
	}
}

// ==============================
// Detour toggler
// ==============================
void ToggleDetour(bool enable)
{
	static bool enabled = false;
	if (enable && !enabled)
	{
		if (!g_hDetour_BounceTouch.Enable(Hook_Pre, OnSpitProjectileBounceTouch))
			SetFailState("Failed to enable pre-detour \"" ... KEY_BOUNCETOUCH ... "\"");
		
		if (!g_hDetour_BounceTouch.Enable(Hook_Post, OnSpitProjectileBounceTouch_Post))
			SetFailState("Failed to enable post-detour \"" ... KEY_BOUNCETOUCH ... "\"");
		
		if (!g_hDetour_Detonate.Enable(Hook_Pre, OnSpitProjectileDetonate))
			SetFailState("Failed to enable pre-detour \"" ... KEY_DETONATE ... "\"");
		
		enabled = true;
	}
	else if (!enable && enabled)
	{
		if (!g_hDetour_BounceTouch.Disable(Hook_Pre, OnSpitProjectileBounceTouch))
			SetFailState("Failed to enable pre-detour \"" ... KEY_BOUNCETOUCH ... "\"");
		
		if (!g_hDetour_BounceTouch.Disable(Hook_Post, OnSpitProjectileBounceTouch_Post))
			SetFailState("Failed to enable post-detour \"" ... KEY_BOUNCETOUCH ... "\"");
		
		if (!g_hDetour_Detonate.Disable(Hook_Pre, OnSpitProjectileDetonate))
			SetFailState("Failed to disable pre-detour \"" ... KEY_DETONATE ... "\"");
		
		enabled = false;
	}
}

// ==============================
// Start Up
// ==============================
public void OnPluginStart()
{
	LoadSDK();
	
	g_hAllMaps = CreateConVar(
					"cssc_global",
					"0",
					"Remove saferoom spit-spread preservation mechanism on all maps.",
					FCVAR_NOTIFY, true, 0.0, true, 1.0
				);
	
	g_hAllIntros = CreateConVar(
					"cssc_intros",
					"0",
					"Remove saferoom spit-spread preservation mechanism on all intro maps.",
					FCVAR_NOTIFY, true, 0.0, true, 1.0
				);
	
	g_hAllEntities = CreateConVar(
					"cssc_all_entities",
					"0",
					"Modify projectile behavior to allow spit burst on non-world entities.",
					FCVAR_NOTIFY, true, 0.0, true, 1.0
				);
	
	g_hAllEntities.AddChangeHook(OnAllEntitiesChanged);
	ToggleDetour(g_hAllEntities.BoolValue);
	
	g_hSpitSpreadMaps = new StringMap();
	g_hSpitSpreadExceptions = new StringMap();
	
	RegServerCmd("saferoom_spit_spread", SetSaferoomSpitSpread);
	RegServerCmd("saferoom_spit_spread_except", SetSaferoomSpitSpreadException);
}

// ==============================
// Map Settings
// ==============================
public Action SetSaferoomSpitSpread(int args)
{
	char map[128];
	GetCmdArg(1, map, sizeof map);
	String_ToLower(map);
	bool dummy;
	if (!g_hSpitSpreadExceptions.GetValue(map, dummy))
		g_hSpitSpreadMaps.SetValue(map, true, false);
}

public Action SetSaferoomSpitSpreadException(int args)
{
	char map[128];
	GetCmdArg(1, map, sizeof map);
	String_ToLower(map);
	bool dummy;
	if (!g_hSpitSpreadMaps.GetValue(map, dummy))
		g_hSpitSpreadExceptions.SetValue(map, true, false);
}

// ==============================
// Forwards
// ==============================
public void OnAllEntitiesChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	ToggleDetour(g_hAllEntities.BoolValue);
}

public void OnMapStart()
{
	ApplySaferoomPatch(g_hAllMaps.BoolValue || IsSaferoomSpitSpreadMap());
}

public void OnConfigsExecuted()
{
	ToggleDetour(g_hAllEntities.BoolValue);
}

// ==============================
// Map detection
// ==============================
bool IsSaferoomSpitSpreadMap()
{
	char map[128];
	GetCurrentMapLower(map, sizeof map);
	
	bool dummy;
	if (g_hSpitSpreadExceptions.GetValue(map, dummy))
		return false;
	
	if (g_hAllIntros.BoolValue && L4D_IsFirstMapInScenario())
		return true;
	
	return g_hSpitSpreadMaps.GetValue(map, dummy);
}

// ==============================
// Non-world entity workaround
// ==============================
int g_iProjectileLastTouch = 0;
public MRESReturn OnSpitProjectileBounceTouch(int pThis, DHookParam hParams)
{
	g_iProjectileLastTouch = hParams.Get(1);
}

public MRESReturn OnSpitProjectileBounceTouch_Post(int pThis, DHookParam hParams)
{
	g_iProjectileLastTouch = 0;
}

public MRESReturn OnSpitProjectileDetonate(int pThis)
{
	ApplyBrushPatch(IsValidForSpitBurst(g_iProjectileLastTouch));
}

bool IsValidForSpitBurst(int entity)
{
	return IsValidEntity(entity) && entity > MaxClients && Entity_IsSolid(entity);
}

// ==============================
// Helper functions
// ==============================
// https://forums.alliedmods.net/showthread.php?t=147732
#define SOLID_NONE 0
#define FSOLID_NOT_SOLID 0x0004
/**
 * Checks whether the entity is solid or not.
 *
 * @param entity            Entity index.
 * @return                    True if the entity is solid, false otherwise.
 */
stock bool Entity_IsSolid(int entity)
{
    return (GetEntProp(entity, Prop_Send, "m_nSolidType", 1) != SOLID_NONE &&
            !(GetEntProp(entity, Prop_Send, "m_usSolidFlags", 2) & FSOLID_NOT_SOLID));
}

stock int GetCurrentMapLower(char[] buffer, int maxlength)
{
	int bytes = GetCurrentMap(buffer, maxlength);
	String_ToLower(buffer);
	return bytes;
}

stock void String_ToLower(char[] buffer)
{
	int len = strlen(buffer);
	for (int i = 0; i < len; ++i) buffer[i] = CharToLower(buffer[i]);
}