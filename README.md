# kittygram-fork

An independent fork of [Kittygram](https://codeberg.org/irelephant/kittygram) by
[irelephant](https://codeberg.org/irelephant), an anonymous, lightweight
Instagram frontend inspired by [Nitter](https://github.com/zedeus/nitter).

This is a fork in its own right, not a fork for contributing back: it follows
its own direction and changes are not sent upstream. It powers a personal
instance, but issues and pull requests are welcome here. For the original
project, its public instances and its community, see the
[upstream repository](https://codeberg.org/irelephant/kittygram).

## What this fork changes

- **Working authenticated search.** With an optional web session, search queries
  Instagram live through `PolarisSearchBoxRefetchableQuery`. The session tokens
  (`fb_dtsg`, `lsd`, actor id, build tokens) are read from an authenticated page,
  cached in Redis and refreshed automatically when Instagram rejects them. See
  [`lib/instagram/web/session.lua`](lib/instagram/web/session.lua).
- **Local search fallback.** If live search fails or no session is configured,
  results come from the local index of users the instance has already seen.
  Profiles are indexed from every view, and queries are normalized, so
  `tomb raider`, `@TombRaider` and 1-2 character prefixes all match.
- **No leaks on error pages.** Raw Instagram responses are no longer shown on
  error pages, API errors or logs, unless `show_error_details` is enabled.
- **GraphQL overrides.** Rotated `doc_id`s can be fixed from `config.lua`
  (`graphql_overrides`) without rebuilding the image.
- **Persistent database and automatic migrations.** SQLite lives in the `data/`
  volume and pending migrations run on every container start.
- **No public instance list.** No runtime download of `instances.json` and no
  random-instance links.
- **Profiles that work again.** List and tile views and full-media Atom feeds
  go through the web session (`use_for.user_posts`), since Instagram now
  requires login for them; without it, profiles are shown as a grid. Private
  profiles show a notice instead of an error.
- **Atom feeds** (`/<user>/atom.xml`) for any feed reader, served from the
  cache, newest post first.

## Deployment

Requires Docker with Compose, plus Git LFS for the static assets.

```bash
git clone https://github.com/darlopvil/kittygram-fork.git kittygram && cd kittygram
git lfs pull
cp config.example.lua config.lua
cp compose.example.yaml docker-compose.yml
mkdir -p data
sudo chown 65534:65534 data
sudo chown 1000:65534 config.lua && sudo chmod 640 config.lua
docker compose up -d --build
```

- Change `secret` in `config.lua`, and write your own `about_message`: it is
  shown at the top of the home page.
- The container serves as `nobody` (65534): `config.lua` must be readable by
  that group and `data/` writable by it.
- Edit `config.lua` in place (e.g. with `nano`). `sed -i` recreates the file and
  resets its owner and permissions.
- To update: `git pull && docker compose up -d --build`. Migrations run on start.

### Atom feeds (optional)

Set `enable_atom = true` and `base_atom_path` (the instance's public URL, with
a trailing slash) in `config.lua`, or the `ENABLE_ATOM=true` and
`BASE_ATOM_PATH` environment variables in the docker environment. With the web
session enabled for `user_posts`, entries carry the full media and the real
date; without it, they are built from the anonymous grid (thumbnail, caption
and the date decoded from the media id). All media goes through `/mediaproxy`.

### Web session (optional)

Live search needs a logged-in Instagram session. Use a dedicated account:
Instagram may restrict or ban accounts used this way.

1. Log in with that account in a private window and copy these cookies:
   `sessionid`, `csrftoken`, `ds_user_id`, `mid`, `ig_did`.
2. In `config.lua`, set `web_session.cookies` to
   `"sessionid=...; csrftoken=...; ds_user_id=...; mid=...; ig_did=..."`.
3. Optionally set `web_session.user_agent` to the user agent of that browser.
4. Enable `web_session.use_for` only where it is needed: `search` for live
   search and `user_posts` for list and tile views and full-media feeds.
   Grids, posts and comments work anonymously, and routing more through the
   account only increases the risk of losing it.

Keep `show_error_details = false` when a session is configured: raw responses
can reveal the account.

## License

[AGPL-3.0](LICENSE), as the original project. Kittygram is © irelephant and its
contributors; the changes in this fork are © darlopvil. Anyone running a
modified version as a network service must offer its source to the service's
users: the home page links to this repository.

Icon by [nulla](https://codeberg.org/nulla).
