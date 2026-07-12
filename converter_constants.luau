local types = require("./converter_types")

local function keys<T>(tbl: { [T]: any }): { T }
	local result = {}
	for key in pairs(tbl) do
		table.insert(result, key)
	end
	return result
end

local CONVERSION_DISPLAY: { [types.ConversionScope]: string } = {
	entire_game = "Entire Game",
	selected_objects = "Selected Objects",
}

local SANDBOX_DISPLAY: { [types.SandboxScope]: string } = {
	sandbox = "Sandbox",
	unsandbox = "Unsandbox",
}

return {
	CONVERSION_DISPLAY = CONVERSION_DISPLAY,
	SANDBOX_DISPLAY = SANDBOX_DISPLAY,
	CONVERSION_VALUES = keys(CONVERSION_DISPLAY),
	SANDBOX_VALUES = keys(SANDBOX_DISPLAY),
}