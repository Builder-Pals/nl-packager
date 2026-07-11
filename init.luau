local converter_types = require("@self/converter_types")

export type ConversionScope = converter_types.ConversionScope
export type SandboxScope = converter_types.SandboxScope

return {
    constants = require("@self/converter_constants"),
    actions = require("@self/converter_actions"),
    packager = require("@self/game_packager")
}