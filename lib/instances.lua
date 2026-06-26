local http = require("resty.http")
local cache = require("lib.cache")
local version = require("version")
local helpers = require("lib.helpers")
local config = require("lapis.config").get()

local INSTANCES_LIST_URI = config.instances_list or "https://codeberg.org/irelephant/kittygram/raw/branch/main/instances.json"

local function get_instances()
    local query = cache.query_item("kg:instances_list")
    if query ~= ngx.null then
        return query
    end

    local httpc = http.new()
    local request, err = httpc:request_uri(INSTANCES_LIST_URI, {
        headers = {
            ["User-Agent"] = "Kittygram/" .. version .. " (Lua; Openresty) (+mailto:irelephant@disroot)"
        }
    })
    if err then
        ngx.log(ngx.ERR, "Network error: " .. err)
        return {}
    end

    local decode_status, result = helpers.safe_json_decode(request.body)

    if not decode_status then
        ngx.log(ngx.ERR, "Failed to decode instances list. List returned: " .. request.body)
        return {}
    else
        cache.cache_item("kg:instances_list", result, "instances_list")
        return result
    end
end

return {
    get_list = get_instances
}
