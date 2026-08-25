local http_request = require("lib.http")
local html = require("htmlparser")
local helpers = require("lib.helpers")
local html_util = require("lib.instagram.web.html_util")
local web_state = ngx.shared.web_state
local errors = require("lib.helpers").create_error
local config = require("lapis.config").get()
local ngx_resp = require("ngx.resp")
local json = require("cjson")

local function create_headers(cookie)
    return {
        { "accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7" },
        { "accept-language", "en-GB,en;q=0.9" },
        { "dpr", "1" },
        { "user-agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36" },
        { "sec-ch-prefers-color-scheme", "dark" },
        { "sec-ch-ua", "\"Chromium\";v=\"135\", \"Not)A;Brand\";v=\"24\"" },
        { "sec-ch-ua-full-version-list", "\"Google Chrome\";v=\"135.0.0.0\", \"Chromium\";v=\"135.0.0.0\", \"Not.A/Brand\";v=\"24\"" },
        { "sec-ch-ua-mobile", "?0"},
        { "sec-ch-ua-model", "\"\"" },
        { "sec-ch-ua-platform-version", "\"10.0.19045\""},
        { "sec-fetch-dest", "document" },
        { "sec-fetch-mode", "navigate" },
        { "sec-fetch-site", "none" },
        { "upgrade-insecure-requests", "1" }
    }
end


local function process_json(array, collector)
    local function insert_key(key, value, _dbg_itm)
        if value == nil then
            return
        end

        -- these values may be used in future, but for now they're not needed.
        -- They're removed to avoid polluting the table with unneccessary data.
        if key:match("cr:*") then
            return
        end

        if collector[key] then
            table.insert(collector[key], value)
        else
            collector[key] = {
                value
            }
        end
    end

    local function check_sub_array(sub_array)
        if sub_array.__bbox and sub_array.__bbox ~= json.null then
            process_json(sub_array.__bbox, collector)
            return true
        elseif sub_array.require or sub_array.define then
            process_json(sub_array, collector)
            return true
        else
            return false
        end
    end

    local function process_item(value_position, item)
        local is_subarray = check_sub_array(item)

        if not is_subarray then
            local key = item[1]
            local value = item[value_position]

            if type(value) == "table" then
                for _, subvalue in ipairs(value) do
                    if type(subvalue) == "table" then
                        check_sub_array(subvalue)
                    end
                end
            end
            insert_key(key, value, item)
        end
    end


    if array.require then
        for _, item in ipairs(array.require) do
            process_item(4, item)
        end
    end
    if array.define then
        for _, item in ipairs(array.define) do
            process_item(3, item)
        end
    end

    return collector
end

local function parse_initial_html(html_body)
    local html_root = html.parse(html_body)
    local json_elements = html_root:select("[type='application/json']")

    local collector = {}
    for _, element in ipairs(json_elements) do

        local json_content = element:getcontent()
        local decode_status, decoded_content = helpers.safe_json_decode(json_content)

        if decode_status and decoded_content then
            process_json(decoded_content, collector)
        end
    end
    return collector
end

local WINDOW_LENGTH = config.ratelimits.window_length
local REQUEST_LIMIT = config.ratelimits.request_limit

local function cooldown(url_pattern)
    local key = "html:" .. url_pattern
    local count = web_state:get(key)
    ngx.log(ngx.WARN, "Rate limit hit on " .. tostring(url_pattern) .. " after " .. tostring(count) .. " requests.")
    if config.ratelimits.cooldown_on_ratelimit then
        -- Get the remaining ttl on the key
        local key_ttl = web_state:ttl(key)
        if key_ttl and key_ttl > 0 then
            web_state:replace(key, REQUEST_LIMIT + 999, key_ttl)
        else
            web_state:replace(key, REQUEST_LIMIT + 999, WINDOW_LENGTH)
        end
    end
end

-- The pattern paramter is used mostly for ratelimit tracking.
local function html_request(url, pattern, skip_processing)
    local request_count = web_state:incr("html:" .. pattern, 1, 0, WINDOW_LENGTH)
    if request_count > REQUEST_LIMIT and config.ratelimits.cooldown_on_ratelimit then
        return errors.ratelimited{
            message = "The server has blocked further requests to Instagram temporarily.",
        }
    end

    local headers = create_headers()

    local request, err = http_request(url, {
        headers = headers,
        method = "GET"
    })

    if config.include_debug_headers then
        ngx_resp.add_header("X-Kg-Debug-Endpoints", "html:" .. tostring(pattern))
    end

    if request.status == 302 then
        cooldown(pattern)
        return errors.ratelimited{
            message = "Instagram returned 302 with location: " .. tostring(request.headers.location),
            blob = request.body
        }
    elseif request.status == 429 then
        cooldown(pattern)
        return errors.ratelimited{
            message = "Instagram returned 429."
        }
    end

    if skip_processing then
        return {
            raw_content = request.body,
            status = request.status
        }
    end

    local processed_data = parse_initial_html(request.body)

    return {
        data = html_util.pare_initial_data(processed_data),
        raw_content = request.body,
        status = request.status
    }

end

return {
    parse_initial_html = parse_initial_html,
    request = html_request,
}
