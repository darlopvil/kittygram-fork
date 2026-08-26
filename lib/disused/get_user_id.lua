local helpers = require("lib.helpers")
local html = require("htmlparser")
local http = require("resty.http")
local json = require("cjson")

local ajax_headers = {
    ["Accept"] = "*/*",
    ["content-type"] = "application/x-www-form-urlencoded",
    ["sec-fetch-site"] = "same-origin",
}
-- I found that user IDs can be collected using this endpoint. I managed to get 400 useful responses before instagram permanently banned my ip from that endpoint, lol.
-- This will likely be useless, but I'll keep it documented here.
local function get_user_id_ajax(username)
    local httpc = http:new()

    local request_body = "route_urls[0]=%2F" .. username .. "&__d=www&__a=1&__comet_req=7"

    local id_request, err = httpc:request_uri("https://www.instagram.com/ajax/bulk-route-definitions/", {
        method = "POST",
        headers = ajax_headers,
        body = request_body,
    })

    if not id_request then
        ngx.log(ngx.ERR, "Request failed: " .. err)
    end

    local payload = json.decode(id_request.body:sub(10, -1))

    return payload.payload.payloads["/" .. username].result.exports.hostableView.props.page_logging.params.profile_id
end

return get_user_id_ajax
