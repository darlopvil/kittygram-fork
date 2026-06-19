local endpoints = {
  web_profile_info = {
       path = "users/web_profile_info/",
       method = "GET",
       requires_auth = false,
   },
}

local create_params = {
    web_profile_info = function(username)
        return {
            username = username
        }
    end,
}
