---@class damage_info
---@field damage LuaDamagePrototype
---@field force LuaForce?
---@field driver LuaPlayer?
---@field gunner LuaPlayer?

---@class ComplexDeathGlobal
---@field lastDamage table<integer,damage_info>
storage = {}
local basic = false

local death_type_counts = {
	["physical"]	= 14,
	["impact"]		= 8,
	["fire"]			= 5,
	["acid"]			= 3,
	["poison"]		= 5,
	["explosion"]	= 6,
	["laser"]			= 2,
	["electric"]	= 2,
}

local train_types = {
	["locomotive"] = true,
	["artillery-wagon"] = true,
	["cargo-wagon"] = true,
	["fluid-wagon"] = true,
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


---@param event EventData.on_entity_damaged
script.on_event(defines.events.on_entity_damaged, function (event)
	storage.lastDamage = storage.lastDamage or {} --[[@as table<integer,{damage: LuaDamagePrototype, force: LuaForce?}>]]
	if not event.entity.name == "character" then return log("Filter is bad!, got "..event.entity.type) end
	---@type damage_info
	local new_last = {
		damage = event.damage_type,
		force = event.force,
	}

	--- cause is nilable... Should've realized that
	if event.cause and event.cause.type == "car" then
		local driver = event.cause.get_driver()
		if driver and driver.object_name == "LuaEntity" then
			driver = driver.associated_player --[[@as LuaPlayer?]]
		end
		---@cast driver -LuaEntity

		local gunner = event.cause.get_passenger()
		if gunner and gunner.object_name == "LuaEntity" then
			gunner = gunner.associated_player --[[@as LuaPlayer?]]
		end
		---@cast gunner -LuaEntity

		new_last.driver = driver
		new_last.gunner = gunner
	end

	storage.lastDamage[event.entity.player.index] = new_last
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

	local key_group = "complex-deaths."
	local key = ""
	---@type LocalisedString|string
	local name = player.name
	---@cast name -?
	local gps = player.character.gps_tag
	local color = player.chat_color

	local last_damage = storage.lastDamage[player.index]
	local damage_type = "physical"
	if last_damage and last_damage.damage.valid then
		damage_type = last_damage.damage.name
	end
	if not death_type_counts[damage_type] then
		log("Unknown damage type: "..damage_type)
		damage_type = "physical"
	end
	key = damage_type

	---@type LocalisedString, Color?
	local killer, killer_color
	---@type LocalisedString, Color?
	local weapon, weapon_color

	if event.cause then
		local cause = event.cause
		---@cast cause -?
		if cause.supports_backer_name() then
			killer = {"", cause.localised_name, " ", cause.backer_name}
		else
			killer = cause.localised_name
		end
		killer_color = last_damage.force.color

		if cause.name == "character" and (cause.player or cause.associated_player) then
			local cause_player = cause.player or cause.associated_player
			---@cast cause_player -?
			killer = cause_player.name
			killer_color = cause_player.chat_color
		elseif cause.type == "car" or cause.type == "spider-vehicle" then
			local driver_entity = cause.get_driver() or last_damage.driver
			local gunner_entity = cause.get_passenger() or last_damage.gunner

			---@type LuaPlayer?, LuaPlayer?
			local driver, gunner

			-- Get the player for the driver
			if driver_entity and driver_entity.object_name ~= "LuaPlayer" then
				---@cast driver_entity LuaEntity
				driver = driver_entity.player or driver_entity.associated_player --[[@as LuaPlayer?]]
			else
				---@cast driver_entity LuaPlayer?
				driver = driver_entity --[[@as LuaPlayer?]]
			end

			-- Get the player for the gunner
			if gunner_entity and gunner_entity.object_name ~= "LuaPlayer" then
				---@cast gunner_entity LuaEntity
				gunner = gunner_entity.player or gunner_entity.associated_player --[[@as LuaPlayer?]]
			else
				---@cast gunner_entity LuaPlayer?
				gunner = gunner_entity
			end

			---@type LuaPlayer?
			local killer_player
			if damage_type == "impact" then
				killer_player = driver
			else
				killer_player = (cause.driver_is_gunner and driver) or gunner or driver
			end

			if killer_player then
				weapon = killer
				weapon_color = killer_color
				killer = killer_player.name
				killer_color = killer_player.chat_color
			end
		elseif train_types[cause.type] then
			-- Uncessary because it's set at the beginning of the condition
			-- killer = cause.backer_name or cause.localised_name
			killer_color = cause.force.color

			if cause.train.manual_mode then
				local driver_entity = cause.get_driver()
				---@type LuaPlayer?
				local driver

				if driver_entity and driver_entity.object_name ~= "LuaPlayer" then
					driver = driver_entity.player or driver_entity.associated_player --[[@as LuaPlayer?]]
				else
					---@cast driver_entity LuaPlayer?
					driver = driver_entity
				end

				if not driver then
					_, driver = next(cause.train.passengers)
					-- The train does not always have any passengers
					---@cast driver +?
				end

				if driver then
					weapon = killer
					weapon_color = killer_color
					killer = driver.name
					killer_color = driver.chat_color
				end
			end
		end
	end

	if killer then
		key = key.."-by"
		local killer_name = killer
		-- Color the killer's name
		killer_color = killer_color or color
		killer = {
			"complex-deaths.colored",
			killer,
			killer_color.r,
			killer_color.g,
			killer_color.b
		}

		if killer_name == player.name then
			-- Self kill
			key = key.."-self"
			-- Don't pass an unused parameter
			killer = nil
		elseif weapon then
			-- Murder with weapon
			key = key.."-with"
			-- Color the weapon name
			weapon_color = weapon_color or killer_color or color
			weapon = {
				"complex-deaths.colored",
				weapon,
				weapon_color.r,
				weapon_color.g,
				weapon_color.b,
			}
		end
	end

	if not basic then
		key_group = "gruesome-deaths."
		key = math.random(death_type_counts[damage_type]).."-"..key
	end

	-- TODO: Make a setting at some point
	-- probably pivot off of better-chat's setting
	if true then
		name = {
			"complex-deaths.colored",
			name,
			color.r,
			color.g,
			color.b
		}
		color = {r=1,g=1,b=1}
	end

	send_message({
		key_group..key, name, gps, killer, weapon,
	}, color, "global")
end

---@param event EventData.on_console_command
script.on_event(defines.events.on_console_command, function (event)
	if event.command ~= "test-deaths" then return end

	local player = game.get_player(1) --[[@as LuaPlayer]]
	local name = {
		"complex-deaths.colored", "PLAYER",
		player.chat_color.r, player.chat_color.g, player.chat_color.b
	}
	local killer = {
		"complex-deaths.colored", "MURDERER",
		0.87549018859863, 0.15000000596046, 0.51078432798386,
	}
	local weapon = {
		"complex-deaths.colored", "WEAPON",
		185, 0, 92,
	}
	local color = {r=1,g=1,b=1}

	---@type string
	local damage_type = event.parameters:match("%S+%s?") or ""
	if damage_type:find("%S+%s") then
		damage_type = damage_type:sub(1,-2)
	end
	if damage_type == "" or not death_type_counts[damage_type] then
		return
	end
	---@type string
	local key_type = (event.parameters:match("%s%S+") or ""):sub(2)

	local count = death_type_counts[damage_type]
	---@type LocalisedString
	local message = {"", damage_type..":"}
	local last_index = 2
	for i = 1, count, 1 do
		last_index = last_index+1
		message[last_index] = {"", "\n\t", {
			"gruesome-deaths."..i.."-"..damage_type..key_type,
			name, "[gps=0,0]", killer, weapon
		}}
	end
	send_message(message, color, "global")
end)

script.on_init(function ()
	storage.lastDamage = {}
	basic = settings.global["complex-deaths-basic-messages"].value --[[@as boolean]]
	replace_event(defines.events.on_player_died, newDeathListener)
end)
script.on_load(function ()
	basic = settings.global["complex-deaths-basic-messages"].value --[[@as boolean]]
	replace_event(defines.events.on_player_died, newDeathListener)
end)
---@param event EventData.on_runtime_mod_setting_changed
script.on_event(defines.events.on_runtime_mod_setting_changed, function (event)
	if event.setting ~= "complex-deaths-basic-messages" then return end
	basic = settings.global["complex-deaths-basic-messages"].value --[[@as boolean]]
end)