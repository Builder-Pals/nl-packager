local WRAPPER = [[require(game:WaitForChild("native_legacy"))(getfenv());]]

local IGNORE_TAGS = {
	"nl_dont_sandbox",
	"nl_ignore"
}

local DONT_SANDBOX_FLAG = "nl_dont_sandbox"

local TARGET_SERVICES = {
    Workspace = true,
    Players = true,
    Lighting = true,
    ReplicatedStorage = true,
    ReplicatedFirst = true,
    ServerScriptService = true,
    ServerStorage = true,
    StarterGui = true,
    StarterPack = true,
    StarterPlayer = true,
    Chat = true,
    Teams = true,
    SoundService = true,
}

-- the LuaSourceContainer type doesn't include the Source property, so we'll do it ourselves :>
type SourceContainer = ModuleScript | Script | LocalScript

local function has_ignore_tag(instance: Instance)
	for _, tag in ipairs(IGNORE_TAGS) do
		if instance:FindFirstChild(tag) or instance:HasTag(tag) then
			return true
		end
	end

	return false
end

local function can_sandbox(instance: Instance)
	return instance.Archivable and instance:FindFirstChild(DONT_SANDBOX_FLAG) == nil and not has_ignore_tag(instance)
end

local converter_actions = {}
converter_actions.TARGET_SERVICES = TARGET_SERVICES

converter_actions.can_sandbox = can_sandbox

function converter_actions.convert_source(source: string)
	return if source:sub(1, #WRAPPER) == WRAPPER then source else WRAPPER .. source
end

function converter_actions.convert_script(script: SourceContainer)
	print(`converting {script:GetFullName()}`)
	script.Source = converter_actions.convert_source(script.Source)
end

function converter_actions.revert_script(script: SourceContainer)
	print(`reverting {script:GetFullName()}`)
	if script.Source:sub(1, #WRAPPER) == WRAPPER then
		print(`\tyea - revert required`)
		script.Source = script.Source:sub(#WRAPPER + 1)
	end
end


local function convert_node(instance: Instance)
	if
		can_sandbox(instance)
		and (instance:IsA("ModuleScript") or instance:IsA("Script") or instance:IsA("LocalScript"))
	then
		converter_actions.convert_script(instance)
	end

	for _, child in ipairs(instance:GetChildren()) do
		if can_sandbox(child) then
			convert_node(child)
		end
	end
end

function converter_actions.convert_game(data_model: DataModel)
    for _, service in ipairs(data_model:GetChildren()) do
        if TARGET_SERVICES[service.Name] then
            convert_node(service)
        end
    end
end

function converter_actions.revert_game(data_model: DataModel)
	for _, service in ipairs(data_model:GetChildren()) do
		if TARGET_SERVICES[service.Name] then
			for _, child in ipairs(service:GetDescendants()) do
				if child:IsA("ModuleScript") or child:IsA("Script") or child:IsA("LocalScript") then
					converter_actions.revert_script(child)
				end
			end
		end
	end
end

--- Sandboxes an Instance (and all of its descendants)
function converter_actions.convert_tree(instance: Instance)
	convert_node(instance)
end

function converter_actions.revert_tree(instance: Instance)
	for _, child in ipairs(instance:GetDescendants()) do
		if child:IsA("ModuleScript") or child:IsA("Script") or child:IsA("LocalScript") then
			converter_actions.revert_script(child)
		end
	end
end

return converter_actions
