export type ConversionScope = "none" | "entire_game" | "selected_objects"
export type SandboxScope = "none" | "sandbox" | "unsandbox"

export type PropertyMap = { [string]: any }

--[=[
    Contains the info required to unpack a service
]=]
export type ServiceInfo = {
    service: Instance,
    content: Instance,
    properties: PropertyMap
}

export type Package = {
    read_ok: true,
    services: { ServiceInfo }
}

export type FailedPackage = {
    read_ok: false,
    error: string
}

export type SomePackage = Package | FailedPackage

return nil