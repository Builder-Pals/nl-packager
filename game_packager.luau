local ReflectionService = game:GetService("ReflectionService")

local converter_actions = require("./converter_actions")

local PACKAGE_TAG = "nl_package"

local SUPPORTED_ATTRIBUTE_TYPES = {
	["boolean"] = true,
	["number"] = true,
	["string"] = true,
	["Vector2"] = true,
	["Vector3"] = true,
	["Color3"] = true,
	["CFrame"] = true,
	["UDim2"] = true,
	["Rect"] = true,
    ["EnumItem"] = true,
}

local SER_ENUM = "nl_enum_"

local function ser_property(value: unknown): unknown
    if typeof(value) == "EnumItem" then
        return `{SER_ENUM}{value.Name}`
    end

    return value
end

local function des_property(value: unknown): unknown
    if typeof(value) == "string" and string.sub(value, 1, #SER_ENUM) == SER_ENUM then
        local enum_name = value:sub(#SER_ENUM + 1)

        for _, enum in Enum:GetEnums() do
            for _, item in enum:GetEnumItems() do
                if item.Name == enum_name then
                    return item
                end
            end
        end

        warn(`[native legacy] Failed to deserialize enum item {enum_name}`)
        return nil
    end

    return value
end

-- clones an object's children and maintains references
local function clone_service(service: Instance)
    local current_camera = workspace.CurrentCamera

	local temp_reparent = Instance.new("Folder")
	temp_reparent.Name = "temp folder"

	for _, child in service:GetChildren() do
		local ok, err = pcall(function()
			child.Parent = temp_reparent
		end)

        if not converter_actions.can_sandbox(child) then
            continue
        end

		if not ok then
			assert(typeof(err) == "string", "unrecognized error")
			if not string.find(err, "Cannot change Parent") then
				warn(`[native legacy] Failed to reparent {child:GetFullName()}: {err}\n{debug.traceback()}`)
			end
		end
	end

	local clone = temp_reparent:Clone()
    clone:SetAttribute("ClassName", service.ClassName)
	clone.Name = service.Name

	for _, child in temp_reparent:GetChildren() do
		if child:HasTag(PACKAGE_TAG) or child == current_camera then
			continue
		end

		child.Parent = service
	end

	for _, prop in ReflectionService:GetPropertiesOfClass(service.ClassName) do
		local first_character = prop.Name:sub(1, 1)
		-- camel case fields are deprecated
		local is_pascal = first_character == first_character:upper()

		if
			prop.Serialized
			and prop.Permits.Write
			and is_pascal
			and service:IsPropertyModified(prop.Name)
			and prop.Type
			and prop.Type.ScriptType
			and SUPPORTED_ATTRIBUTE_TYPES[prop.Type.ScriptType]
		then
			clone:SetAttribute(prop.Name, ser_property((service :: Instance & {})[prop.Name]))
		end
	end

	return clone
end

local game_packager = {}

function game_packager.package(data_model: DataModel)
	local package = Instance.new("Configuration")
	package.Name = if #game.Name == 0 then "Unnamed Game Package" else `{game.Name} Game Package`
	package:AddTag(PACKAGE_TAG)

	local dom_items = Instance.new("Folder")
	dom_items.Name = "DataModel"
	dom_items.Parent = package

	for service_name in converter_actions.TARGET_SERVICES do
		local service = game:GetService(service_name)

		local clone = clone_service(service)
		converter_actions.convert_tree(clone)
		clone.Parent = dom_items
	end

	return package
end

return game_packager
