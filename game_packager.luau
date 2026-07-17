local ReflectionService = game:GetService("ReflectionService")

local actions = require("./converter_actions")
local serdes = require("./converter_serdes")
local types = require("./converter_types")

type IndexableInstance = Instance & {}

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

local PROP_SETS: ReflectionMemberFilter = {
	ExcludeDisplay = true,
	ExcludeInherited = false,
}

local prop_cache: { [string]: { ReflectedProperty } } = {}

local function filter_props(props: { ReflectedProperty }): { ReflectedProperty }
	local output = {}

	for _, prop in props do
		if prop.Permits and prop.Permits.Write and prop.Permits.Read then
			table.insert(output, prop)
		end
	end

	return output
end

local function get_props(class: string): { ReflectedProperty }
	if prop_cache[class] then
		return prop_cache[class]
	end

	print(`Getting properties for {class}`)
	local props = ReflectionService:GetPropertiesOfClass(class, PROP_SETS)

	if props == nil then
		warn(`{class} has no properties or is invalid!`)
		prop_cache[class] = {}
		return prop_cache[class]
	end

	prop_cache[class] = filter_props(props)
	return prop_cache[class]
end

--- clones an object's children and maintains references
local function new_service_pack(service: Instance)
	local clone = Instance.new("Folder")
	clone:SetAttribute("ClassName", service.ClassName)
	clone.Name = service.Name

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
			clone:SetAttribute(prop.Name, serdes.ser_property((service :: IndexableInstance)[prop.Name]))
		end
	end

	return clone
end

local function dump_game_to(destination: Instance)
	if destination:IsDescendantOf(game) then
		warn(`it's much faster if the destination isn't parented to the DOM before dumping.\n{debug.traceback()}`)
	end

	local remapping: { [Instance]: Instance } = {}
	local pending_refs = {}

	remapping[game] = destination

	local function deep_copy(instance: Instance)
		if instance:HasTag(PACKAGE_TAG) or instance:HasTag("nl_ignore") or not instance.Archivable then
			return
		end

		for _, child in instance:GetChildren() do
			if not child.Archivable then
				warn(`wont copy {child:GetFullName()}`)
				continue
			end

			local ok, copy = pcall(function()
				return Instance.fromExisting(child)
			end)

			if not copy or not ok then
				warn(`failed to pack {child:GetFullName()}: {copy}`)
				continue
			end

			if copy:IsA("Script") or copy:IsA("LocalScript") or copy:IsA("ModuleScript") then
				actions.convert_script(copy)
			end

			remapping[child] = copy

			for _, property in get_props(copy.ClassName) do
				if not child:IsPropertyModified(property.Name) then
					continue
				end

				local get_ok, get_err = pcall(function()
					local value = child[property.Name]

					if typeof(value) == "Instance" then
						-- Instance references will need to be changed to use
						-- their copied counterparts.
						table.insert(pending_refs, { clone = copy, name = property.Name, value = value })
					end
				end)

				if not get_ok then
					warn(`failed to get {property.Name} on {copy.ClassName}: {get_err}\n🧵{debug.traceback()}`)
				end
			end

			deep_copy(child)
		end
	end

	for _, service in game:GetChildren() do
		if not TARGET_SERVICES[service.ClassName] then
			continue
		end

		print(`copying game.{service}`)
		deep_copy(service)

		local container = new_service_pack(service)
		container.Parent = destination
		remapping[service] = container
	end

	-- after making all copies, update Instance references
	for _, pack in pending_refs do
		pack.clone[pack.name] = remapping[pack.value] or pack.value
		pack.value = remapping[pack.value] or pack.value
		print(`remapping {pack.clone}.{pack.name} to {remapping[pack.value] or "FAILURE"}`)
	end

	print(pending_refs)
end

local game_packager = {}
game_packager.TARGET_SERVICES = TARGET_SERVICES

--- Creates a sandboxed package of the game that's marketplace ready.
--- Packges can be read and loaded by *Native Legacy*
function game_packager.dump_game_as_package()
	local package = Instance.new("Configuration")
	package.Name = if #game.Name == 0 then "Unnamed Game Package" else `Game Package ({game.Name})`
	package:AddTag(PACKAGE_TAG)

	local dom_items = Instance.new("Folder")
	dom_items.Name = "DataModel"
	dom_items:SetAttribute("name", game.Name)
	dom_items.Parent = package

	dump_game_to(dom_items)

	return package
end

local function read(input: Instance): types.Package
	local function build_property_table(instance: Instance): types.PropertyMap
		local properties = {}

		for key, value in instance:GetAttributes() do
			if key == "ClassName" then
				continue
			end

			properties[key] = serdes.des_property(value)
		end

		return properties
	end

	local function get_class_name(service: Instance)
		local class_name = service:GetAttribute("ClassName")

		if type(class_name) == "string" then
			return class_name
		end

		return service.Name
	end

	local dom_container = input:FindFirstChild("DataModel") or input:FindFirstChild("startPlace")

	if not dom_container then
		const MISSING_CHILD_ERROR = "invalid - a legacy package was detected, but it's missing required children"
		local place_config = input:FindFirstChild("NewNostalgicPlaceConfig")
		assert(place_config, MISSING_CHILD_ERROR)
		local dataModelPackage = place_config:FindFirstChild("DataModelPackage")
		assert(dataModelPackage, MISSING_CHILD_ERROR)
		local services = dataModelPackage:FindFirstChild("Services")
		assert(services, MISSING_CHILD_ERROR)
		dom_container = services
	end

	assert(dom_container, "invalid - package is missing a DataModel container")

	local services: { types.ServiceInfo } = {}

	for _, child in dom_container:GetChildren() do
		local service = game:GetService(get_class_name(child))

		local service_info: types.ServiceInfo = {
			service = service,
			content = child,
			properties = build_property_table(service),
		}

		table.insert(services, service_info)
	end

	local package: types.Package = {
		read_ok = true,
		services = services,
	}

	return package
end

--- Parses a DOM package to a typed package for loading.
function game_packager.read(package: Instance): types.SomePackage
	local ok, result = pcall(read, package)
	return if ok then result else { read_ok = false, error = tostring(result) }
end

function game_packager.unpack_service(info: types.ServiceInfo)
	for key, value in info.properties do
		pcall(function()
			(info.service :: IndexableInstance)[key] = value
		end)
	end

	for _, child in info.content:GetChildren() do
		if child:IsA("StarterPlayerScripts") or child:IsA("StarterPlayer") then
			for _, sub_child in child:GetChildren() do
				sub_child.Parent = info.service:FindFirstChild(child.ClassName)
			end
		else
			child.Parent = info.service
		end
	end
end

return game_packager
