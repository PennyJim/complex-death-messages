---@class ComplexDeathGlobal
---@field lastDamage table<integer,{damage:LuaDamagePrototype, force:LuaForce?}>
global = {}
local gruesome = false

local gruesome_counts = {
	["physical"]	= 2,
	["impact"]		= 3,
	["fire"]			= 2,
	["acid"]			= 1,
	["poison"]		= 1,
	["explosion"]	= 2,
	["laser"]			= 2,
	["electric"]	= 2,
}

---Disables Better Chat's handler and registers our own
---@param event defines.events
---@param func fun(EventData)
---@param filter EventFilter?
function replace_event(event, func, filter)
	remote.call("better-chat", "disable_listener", script.mod_name, defines.events.on_player_died)
	script.on_event(event, func, filter)
end

function send_message(message, color, send_level, recipient)
	remote.call("better-chat", "send", message, color, send_level, recipient)
end


script.on_event(defines.events.on_entity_damaged, function (event)
	global.lastDamage = global.lastDamage or {} --[[@as table<integer,{damage: LuaDamagePrototype, force: LuaForce?}>]]
	if not event.entity.name == "character" then return log("Filter is bad!, got "..event.entity.type) end
	global.lastDamage[event.entity.player.index] = {
		damage = event.damage_type,
		force = event.force,
	}
end, {
	{
		filter = "type",
		type = "character",
	},
	{
		filter = "final-health",
		comparison = "<=",
		value = 0,
		mode = "and"
	}
})

---@param event EventData.on_player_died
local newDeathListener = function (event)
	local player = game.get_player(event.player_index)
	if not player then return log("No one died???") end
	if not player.character then return log("Player.character doesn't exist on death, change to pre-death") end

	local key_group = "complex-deaths."
	local key = ""
	local name = player.name
	local gps = player.character.gps_tag
	local color = player.chat_color

	local last_damage = global.lastDamage[player.index]
	local damage_type = "physical"
	if last_damage and last_damage.damage.valid then
		damage_type = last_damage.damage.name
	end
	if not gruesome_counts[damage_type] then
		log("Unknown damage type: "..damage_type)
		damage_type = "physical"
	end
	key = damage_type

	---@type LocalisedString, Color.0?, LocalisedString
	local killer, killer_color, weapon

	if event.cause then
		local cause = event.cause
		---@cast cause -?
		killer = cause.localised_name
		killer_color = last_damage.force.color

		if cause.name == "character" and cause.player then
			killer = cause.player.name
			killer_color = cause.player.chat_color
		elseif cause.type == "car" or cause.type == "spider-vehicle" then
			local driver = cause.get_driver() or {}
			local gunner = cause.get_passenger() or {}

			driver = driver.player
			gunner = gunner.player

			---@type LuaPlayer?
			local killer_player
			if key == "impact-by-with" then
				killer_player = driver
			else
				killer_player = (cause.driver_is_gunner and driver) or gunner or driver
			end

			if killer_player then
				weapon = killer
				killer = killer_player.name
				killer_color = killer_player.chat_color
			end
		end
	end

	if killer then
		key = key.."-by"
		killer_color = killer_color or color
	else
		killer_color = {}
	end

	if weapon then
		key = key.."-with"
	end

	if gruesome then
		key_group = "gruesome-deaths."
		key = math.random(gruesome_counts[damage_type]).."-"..key
	end


	send_message({
		key_group..key, name, gps, killer, weapon or "",
		killer_color.r, killer_color.g, killer_color.b
	}, color, "global")
end


script.on_init(function ()
	global.lastDamage = {}
	gruesome = settings.global["complex-deaths-do-gruesome"].value --[[@as boolean]]
	replace_event(defines.events.on_player_died, newDeathListener)
end)
script.on_load(function ()
	global.lastDamage = global.lastDamage or {}
	gruesome = settings.global["complex-deaths-do-gruesome"].value --[[@as boolean]]
	replace_event(defines.events.on_player_died, newDeathListener)
end)
---@param event EventData.on_runtime_mod_setting_changed
script.on_event(defines.events.on_runtime_mod_setting_changed, function (event)
	if event.setting ~= "complex-deaths-do-gruesome" then return end
	gruesome = settings.global["complex-deaths-do-gruesome"].value --[[@as boolean]]
end)