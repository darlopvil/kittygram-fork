local bignum = require("openssl.bignum")
local json = require("cjson")
local util = require("lapis.util")

local function check_nested_field(tbl, ...)
    local current = tbl
    for _, key in ipairs { ... } do
        if type(current) ~= "table" then
            return nil
        end
        current = current[key]
    end
    return current
end

local proxy_url = function(url)
    if type(url) ~= "string" then
        return url
    end
    return "/mediaproxy?url=" .. util.escape(url)
end

local function safe_json_decode(data)
    local status, result = pcall(json.decode, data)
    return status, result
end

-- add commas to a number.
-- e.g., 100000, 100,000
local function comma_value(separator)
    return function(amount)
        if type(amount) ~= "number" then
            return amount
        end

        local formatted = amount
        while true do
            local formatted_, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1" .. separator .. "%2")
            formatted = formatted_
            if k == 0 then
                break
            end
        end
        return formatted
    end
end

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

local function shortcode_to_id(shortcode)
    local num = bignum.new(0)

    for i = 1, #shortcode do
        local c = shortcode:sub(i, i)
        local value = ALPHABET:find(c, 1, true)
        assert(value, "Invalid character: " .. c)

        value = value - 1 -- convert to 0-63
        num = num * 64 + value
    end

    return tostring(num)
end

local create_error = {
    not_found = function(args)
        return {
            has_errors = true,
            error_type = "not_found",
            error_info = {
                message = args.message or "The requested content was not found.",
                blob = json.encode(args.blob),
            },
        }
    end,
    ratelimited = function(args)
        return {
            has_errors = true,
            error_type = "ratelimited",
            error_info = {
                message = args.message or "This instance may be rate-limited. Try again in a minute.",
                blob = json.encode(args.blob),
            },
        }
    end,
    blocked = function(args)
        return {
            has_errors = true,
            error_type = "blocked",
            error_info = {
                message = args.message
                    or "This instance has been blocked from accessing that content. This may be permanent",
                blob = json.encode(args.blob),
            },
        }
    end,
    network_error = function(args)
        return {
            has_errors = true,
            error_type = "network_error",
            error_info = {
                message = args.message
                    or "A network error occurred when trying to fetch this item. This is likely temporary.",
                blob = json.encode(args.blob),
            },
        }
    end,
    null_content = function(args)
        return {
            has_errors = true,
            error_type = "null_content",
            error_info = {
                message = args.message or "This post is unavailable.",
                blob = json.encode(args.blob),
            },
        }
    end,
    route_not_defined = function()
        return {
            has_errors = true,
            error_type = "route_not_defined",
            error_info = {
                error_message = "No route was defined for this request.",
                error_blob = nil,
            },
        }
    end,
    feature_not_supported = function()
        return {
            has_errors = true,
            error_type = "feature_not_supported",
            error_info = {
                message = "This feature is not yet supported on kittygram.",
                blob = nil,
            },
        }
    end,
    unknown = function(args)
        return {
            has_errors = true,
            error_type = "unknown",
            error_info = {
                message = args.message or "An unknown error occurred.",
                blob = json.encode(args.blob),
            },
        }
    end,
}

--[[
  Decodes a compressed sparse row bitmap string.
  Returns a list of integer indices where the original bits are 1.
  The string uses a custom base-64 encoding (digits, a-z, A-Z, '-', '_').
--]]
local function decode_csr_bitmap(encoded_str)
    local charset = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_"
    local char_to_val = {}
    for i = 1, #charset do
        char_to_val[charset:sub(i, i)] = i - 1
    end

    -- Step 1: convert each character to a 6‑bit binary string
    local bit_string = ""
    for i = 1, #encoded_str do
        local ch = encoded_str:sub(i, i)
        local val = char_to_val[ch] -- 0..63
        -- Build 6-bit binary representation manually (no external bit library needed)
        local bin = ""
        local v = val
        for _ = 1, 6 do
            bin = (v % 2) .. bin
            v = math.floor(v / 2)
        end
        bit_string = bit_string .. bin
    end

    -- Helper: read an Elias‑gamma encoded number from the bit string.
    -- pos is 0‑based.
    local function read_gamma(bits, pos)
        local z = 0
        -- count leading zeros
        while pos + z < #bits and bits:sub(pos + z + 1, pos + z + 1) == "0" do
            z = z + 1
        end
        -- need z+1 data bits
        if pos + z + z + 1 > #bits then
            return nil -- truncated, ran into padding
        end
        local num_bits = bits:sub(pos + z + 1, pos + z + z + 1)
        local val = tonumber(num_bits, 2) -- Lua 5.2+ ; otherwise implement manually
        return {
            val = val,
            new_pos = pos + z + z + 1,
        }
    end

    -- Step 2: the first bit is the initial run value (0 or 1)
    local cur_val = tonumber(bit_string:sub(1, 1))
    local pos = 1 -- 0‑based index of next bit

    -- Step 3: decode run lengths using gamma codes
    local runs = {}
    while pos < #bit_string do
        local result = read_gamma(bit_string, pos)
        if not result then
            break
        end
        table.insert(runs, { cur_val, result.val })
        pos = result.new_pos
        cur_val = 1 - cur_val -- runs alternate between 0 and 1
    end

    -- Step 4: expand runs into the list of indices where bit == 1
    local number_list = {}
    local current_idx = 0
    for _, run in ipairs(runs) do
        local run_val, run_len = run[1], run[2]
        if run_val == 1 then
            for k = 0, run_len - 1 do
                table.insert(number_list, current_idx + k)
            end
        end
        current_idx = current_idx + run_len
    end

    return number_list
end

-- the lapis function to do this is currently broken.
-- NOTE: Replace with the lapis function when it's fixed.
-- If a value is nil, that key is omitted.
local function encode_query_string(query_table)
    local query_string = ""
    for key, value in pairs(query_table) do
        local form_key, form_value
        if type(key) == "number" then
            form_key = value[1]
            form_value = value[2]
        else
            form_key = key
            form_value = value
        end

        if form_value ~= nil then
            if query_string == "" then
                query_string = form_key .. "=" .. util.escape(form_value)
            else
                query_string = query_string .. "&" .. form_key .. "=" .. util.escape(form_value)
            end
        end
    end

    return query_string
end

return {
    check_nested_field = check_nested_field,
    proxy_url = proxy_url,
    create_error = create_error,
    safe_json_decode = safe_json_decode,
    comma_value = comma_value,
    shortcode_to_id = shortcode_to_id,
    decode_csr_bitmap = decode_csr_bitmap,
    encode_query_string = encode_query_string,
}
