local config = require("lapis.config").get()

if config.use_accounts then
    return {
        get_post = require("lib.instagram.web.get_post"),
        get_comments = require("lib.instagram.web.get_comments"),
        get_user = require("lib.instagram.web.user"),
        search = require("lib.instagram.web.search"),
        get_highlight = require("lib.instagram.web.highlights").get_highlight
    }
else
    return {
        get_post = require("lib.instagram.web.get_post"),
        get_comments = require("lib.instagram.web.get_comments"),
        get_user = require("lib.instagram.web.user"),
        search = require("lib.instagram.web.search"),
        get_highlight = require("lib.instagram.web.highlights").get_highlight
    }
end


