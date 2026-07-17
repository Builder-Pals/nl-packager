local WRAPPER = [[require(game:WaitForChild("native_legacy"))(getfenv());]]

local IGNORE_TAGS = {
	"nl_dont_sandbox",
	"nl_ignore",
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

local LUA_KEYWORDS = {
	["and"] = true,
	["break"] = true,
	["do"] = true,
	["else"] = true,
	["elseif"] = true,
	["end"] = true,
	["false"] = true,
	["for"] = true,
	["function"] = true,
	["if"] = true,
	["in"] = true,
	["local"] = true,
	["nil"] = true,
	["not"] = true,
	["or"] = true,
	["repeat"] = true,
	["return"] = true,
	["then"] = true,
	["true"] = true,
	["until"] = true,
	["while"] = true,
}

local function is_identifier_start(character: string): boolean
	return character:match("[A-Za-z_]") ~= nil
end

local function is_identifier_part(character: string): boolean
	return character:match("[A-Za-z0-9_]") ~= nil
end

local function long_bracket_level(source: string, start_index: number): number?
	if source:sub(start_index, start_index) ~= "[" then
		return nil
	end

	local index = start_index + 1
	while source:sub(index, index) == "=" do
		index += 1
	end

	if source:sub(index, index) == "[" then
		return index - start_index - 1
	end

	return nil
end


local function long_bracket_end(source: string, start_index: number, level: number): number
	local delimiter = "]" .. string.rep("=", level) .. "]"
	local content_start = start_index + level + 2
	local close_start = source:find(delimiter, content_start, true)

	return if close_start then close_start + #delimiter - 1 else #source
end


local function quoted_string_end(source: string, start_index: number): number
	local quote = source:sub(start_index, start_index)
	local index = start_index + 1

	while index <= #source do
		local character = source:sub(index, index)
		if character == "\\" then
			-- The escaped character cannot terminate the string. This also handles
			-- escaped line endings; the following LF in a CRLF pair is harmless.
			index += 2
		elseif character == quote then
			return index
		else
			index += 1
		end
	end

	return #source
end


local function line_comment_end(source: string, start_index: number): number
	local index = start_index
	while index <= #source do
		local character = source:sub(index, index)
		if character == "\r" or character == "\n" then
			return index - 1
		end
		index += 1
	end

	return #source
end


-- Interpolated strings are deliberately not converted, but they still need to
-- be scanned as one token so quotes and comments inside them are not mistaken
-- for ordinary source. These two functions locate nested interpolation safely.
local interpolated_string_end: (source: string, start_index: number) -> number

local function interpolation_expression_end(source: string, start_index: number): number
	local index = start_index
	local brace_depth = 1

	while index <= #source do
		local character = source:sub(index, index)
		local next_character = source:sub(index + 1, index + 1)

		if character == "'" or character == '"' then
			index = quoted_string_end(source, index) + 1
		elseif character == "`" then
			index = interpolated_string_end(source, index) + 1
		elseif character == "-" and next_character == "-" then
			local level = long_bracket_level(source, index + 2)
			if level ~= nil then
				index = long_bracket_end(source, index + 2, level) + 1
			else
				index = line_comment_end(source, index + 2) + 1
			end
		elseif character == "[" then
			local level = long_bracket_level(source, index)
			if level ~= nil then
				index = long_bracket_end(source, index, level) + 1
			else
				index += 1
			end
		elseif character == "{" then
			brace_depth += 1
			index += 1
		elseif character == "}" then
			brace_depth -= 1
			if brace_depth == 0 then
				return index
			end
			index += 1
		else
			index += 1
		end
	end

	return #source
end

interpolated_string_end = function(source: string, start_index: number): number
	local index = start_index + 1

	while index <= #source do
		local character = source:sub(index, index)
		if character == "\\" then
			index += 2
		elseif character == "`" then
			return index
		elseif character == "{" then
			index = interpolation_expression_end(source, index + 1) + 1
		else
			index += 1
		end
	end

	return #source
end


local function wrap_string_literals(source: string): string
	local output = {}
	local index = 1
	local last_token_kind: string? = nil
	local last_token_text: string? = nil
	local last_token_output_index: number? = nil
	local previous_token_kind: string? = nil
	local previous_token_text: string? = nil

	local function record_token(kind: string, text: string, output_index: number?)
		previous_token_kind = last_token_kind
		previous_token_text = last_token_text
		last_token_kind = kind
		last_token_text = text
		last_token_output_index = output_index
	end

	local function last_token_accepts_string_argument(): boolean
		return last_token_kind == "identifier" and not LUA_KEYWORDS[last_token_text :: string]
			or last_token_kind == "call"
			or last_token_kind == "punctuation"
				and (last_token_text == ")" or last_token_text == "]" or last_token_text == "}")
	end

	local function append_string(end_index: number)
		local literal = source:sub(index, end_index)
		local already_wrapped = last_token_kind == "identifier" and last_token_text == "__STRDEC"
			or last_token_kind == "punctuation"
				and last_token_text == "("
				and previous_token_kind == "identifier"
				and previous_token_text == "__STRDEC"

		if already_wrapped then
			table.insert(output, literal)
			record_token("call", literal, #output)
		else
			local is_string_call_argument = last_token_accepts_string_argument()

			if is_string_call_argument then
				-- Put the opening parenthesis directly after the callable token. If a
				-- comment and newline separate it from the string, placing the opening
				-- parenthesis at the string would trigger Luau's ambiguous-call error.
				local callable_output_index = last_token_output_index :: number
				output[callable_output_index] ..= "("
				table.insert(output, "__STRDEC " .. literal .. ")")
				record_token("call", literal, #output)
			else
				local preceding_character = source:sub(index - 1, index - 1)
				local separator = if preceding_character ~= "" and is_identifier_part(preceding_character) then " " else ""
				table.insert(output, separator .. "__STRDEC " .. literal)
				record_token("string", literal, #output)
			end
		end

		index = end_index + 1
	end

	while index <= #source do
		local character = source:sub(index, index)
		local next_character = source:sub(index + 1, index + 1)

		if character == "-" and next_character == "-" then
			local level = long_bracket_level(source, index + 2)
			local end_index = if level ~= nil
				then long_bracket_end(source, index + 2, level)
				else line_comment_end(source, index + 2)
			table.insert(output, source:sub(index, end_index))
			index = end_index + 1
		elseif character == "'" or character == '"' then
			append_string(quoted_string_end(source, index))
		elseif character == "[" then
			local level = long_bracket_level(source, index)
			if level ~= nil then
				append_string(long_bracket_end(source, index, level))
			else
				table.insert(output, character)
				record_token("punctuation", character, #output)
				index += 1
			end
		elseif character == "`" then
			local end_index = interpolated_string_end(source, index)
			table.insert(output, source:sub(index, end_index))
			local token_kind = if last_token_accepts_string_argument() then "call" else "string"
			record_token(token_kind, source:sub(index, end_index), #output)
			index = end_index + 1
		elseif is_identifier_start(character) then
			local end_index = index + 1
			while end_index <= #source and is_identifier_part(source:sub(end_index, end_index)) do
				end_index += 1
			end

			local identifier = source:sub(index, end_index - 1)
			table.insert(output, identifier)
			record_token("identifier", identifier, #output)
			index = end_index
		else
			table.insert(output, character)
			if not character:match("%s") then
				record_token("punctuation", character, #output)
			end
			index += 1
		end
	end

	return table.concat(output)
end

function converter_actions.convert_source(source: string)
	return if source:sub(1, #WRAPPER) == WRAPPER then source else WRAPPER .. wrap_string_literals(source)
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
