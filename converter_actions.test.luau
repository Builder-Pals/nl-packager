local actions = require("./converter_actions")

local wrapper = [[require(game:WaitForChild("native_legacy"))(getfenv());]]
local cases = {
	{
		[[local asset_id = "rbxassetid://"]],
		[[local asset_id = __STRDEC "rbxassetid://"]],
	},
	{
		[=[local owner_names = { [[Telemon]], 'dave' .. 'bazuka' }]=],
		[=[local owner_names = { __STRDEC [[Telemon]], __STRDEC 'dave' .. __STRDEC 'bazuka' }]=],
	},
	{
		[[warn"message"]],
		[[warn(__STRDEC "message")]],
	},
	{
		[[return"value"]],
		[[return __STRDEC "value"]],
	},
	{
		[====[local x = [==[long ]=] text]==] -- "comment"
--[=[ 'long comment' ]=]
local y = "escaped \" quote"]====],
		[====[local x = __STRDEC [==[long ]=] text]==] -- "comment"
--[=[ 'long comment' ]=]
local y = __STRDEC "escaped \" quote"]====],
	},
	{
		[[local x = `plain "text" {'expression'}`]],
		[[local x = `plain "text" {'expression'}`]],
	},
	{
		[[local x = `outer {`nested {"quoted"}`} tail`]],
		[[local x = `outer {`nested {"quoted"}`} tail`]],
	},
	{
		[[local x = __STRDEC "already"]],
		[[local x = __STRDEC "already"]],
	},
	{
		"local x = get_value -- call continues after its comment\n[=[long value]=]",
		"local x = get_value( -- call continues after its comment\n__STRDEC [=[long value]=])",
	},
	{
		[[local x = object["key"] .. ("value"):upper()]],
		[[local x = object[__STRDEC "key"] .. (__STRDEC "value"):upper()]],
	},
	{
		[[local x = factory"first"'second']],
		[[local x = factory(__STRDEC "first")(__STRDEC 'second')]],
	},
	{
		[[local kinds = { type"value", continue"value", goto"value" }]],
		[[local kinds = { type(__STRDEC "value"), continue(__STRDEC "value"), goto(__STRDEC "value") }]],
	},
}

for index, case in cases do
	local converted = actions.convert_source(case[1]):sub(#wrapper + 1)
	assert(converted == case[2], `case {index}\nexpected: {case[2]}\nactual:   {converted}`)
	local reconverted = actions.convert_source(converted):sub(#wrapper + 1)
	assert(reconverted == converted, `case {index} was wrapped more than once`)
	local chunk, syntax_error = loadstring("local __STRDEC = function(value) return value end\n" .. converted)
	assert(chunk, `syntax failure in case {index}: {syntax_error}`)
end

local converted_once = actions.convert_source([[local value = "once"]])
assert(actions.convert_source(converted_once) == converted_once, "convert_source must be idempotent")

local transformer_source = require("@lune/fs").readFile("converter_actions.luau")
local converted_transformer = actions.convert_source(transformer_source):sub(#wrapper + 1)
local converted_chunk, converted_syntax_error = loadstring(converted_transformer)
assert(converted_chunk, `transforming converter_actions.luau produced invalid syntax: {converted_syntax_error}`)

print(`passed {#cases} transformer cases`)
