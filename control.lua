---@class ComplexDeathGlobal
---@field lastDamage table<integer,{damage:LuaDamagePrototype, force:LuaForce?}>
global = {}

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
	---@type LocalisedString
	local message = {
		"multiplayer.player-died",
		player.name,
		player.character.gps_tag
	}
	---@cast message -?
	if event.cause then
		local cause_name = event.cause.localised_name
		if event.cause.name  == "character" and event.cause.player then
			cause_name = event.cause.player.name
		elseif event.cause.type == "car" or event.cause.type == "spider-vehicle" then
			local vehicle = event.cause --[[@as LuaEntity]]
			local last_damage = global.lastDamage[event.player_index]
			local driver = vehicle.get_driver() or {}
			local gunner = vehicle.get_passenger() or {}
			if driver.player then driver = driver.player end
			if gunner.player then gunner = gunner.player end
			local old_cause = cause_name
			if last_damage.damage.name == "impact" then
		---@diagnostic disable-next-line: need-check-nil
				cause_name = driver.name
			else
			---@diagnostic disable-next-line: need-check-nil
				cause_name = (vehicle.driver_is_gunner and driver.name) or gunner.name or driver.name
			end
		
			if cause_name then
				cause_name = {"complex-deaths.bc-by-with", cause_name, old_cause}
			else
				cause_name = old_cause
			end
		end
		message[1] = "multiplayer.player-died-by"
		message[4] = message[3]
		message[3] = cause_name
	end
	send_message(message, player.chat_color, "global")
end


script.on_init(function ()
	global.lastDamage = {}
	replace_event(defines.events.on_player_died, newDeathListener)
end)
script.on_load(function ()
	global.lastDamage = global.lastDamage or {}
	replace_event(defines.events.on_player_died, newDeathListener)
end)