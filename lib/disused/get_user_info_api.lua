local http = require("resty.http")
local json = require("cjson")

local instagram_headers = {
    ["X-IG-App-ID"] = "936619743392459", -- TODO: let this be configurable
    ["X-CSRFToken"] = "exampletexthere", -- this can be anything.  TODO: probably should make it configurable as well
    ["Content-Type"] = "application/x-www-form-urlencoded",
    ["Accept"] = "*/*",
}

local function get_user_info_api(username)
    local start_uri = "https://www.instagram.com/api/v1/users/web_profile_info/?username="
    local httpc = http.new()

    local user_request = httpc:request_uri(start_uri .. username, { headers = instagram_headers })

    if helpers.check_nested_field(json.decode(user_request.body), "data", "user") then
        return json.decode(user_request.body).data.user
    else
        return json.decode(user_request.body)
    end
end
