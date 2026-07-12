local SER_ENUM = "nl_enum_"

local converter_serdes = {}

function converter_serdes.ser_property(value: unknown): unknown
    if typeof(value) == "EnumItem" then
        return `{SER_ENUM}{value.Name}`
    end

    return value
end

function converter_serdes.des_property(value: unknown): unknown
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

return converter_serdes