<div align="center">

<!-- TODO: Update preview/cover image. -->
<!-- https://colorhunt.co/palette/14279b3d56b25c7aeae6e6e6 -->

![Kittygram](./docs/assets/cover.png)

# Kittygram

Kittygram is an anonymous, privacy-friendly, lightweight, and open-source
Instagram frontend inspired by [Nitter](https://github.com/zedeus/nitter). It
offers a clean, fast way to browse Instagram without the usual clutter or
tracking.

</div>

## Table of contents

- [Why Kittygram?](#why-kittygram)
  - [Limitations](#limitations)
- [Instances](#instances)
- [Installation](#installation)
  - [Method 1: Containers](#method-1-containers)
    - [Docker](#docker)
    - [Podman](#podman)
  - [Method 2: Native](#method-2-native)
- [Info](#info)
  - [License](#license)
  - [Community](#community)

## Why Kittygram?

The official Instagram web interface is heavy on JavaScript, slow to load, and
filled with pop-ups. Kittygram avoids all of that by serving fully prerendered
pages, making it faster and easier to use.

Kittygram also helps you avoid the heavy tracking Instagram does, as all
requests are handled by Kittygram.

### Limitations

- Instagram aggressively rate-limits requests coming from servers, which can
  make running a public instance difficult.
- Some features (such as stories) are not yet viewable.

## Instances

| Instance link:                     | Operated by:                                  | Notes:               |
| ---------------------------------- | --------------------------------------------- | -------------------- |
| <https://kittygram.irelephant.net> | [Irelephant](https://codeberg.org/irelephant) | Kittygram maintainer |
| <https://kittygr.am>               | [FSKY](https://fsky.io)                       |                      |
| <https://kittygram.kareem.one>     | [Kareem](https://kareem.one)                  | Cloudflare           |
| <https://kittygram.nexussfan.cz>   | [NexusSfan](https://mrchicken.nexussfan.cz)   |                      |
| <https://kg.lus.lu>                | [ffb0f3](https://lus.lu)                      |                      |
| <https://kg.meowing.de>            | [patrick](https://patriick.dev)               |                      |
| <https://kittygram.nadeko.net>     | [Fijxu](https://nadeko.net)                   |                      |

<!-- NOTE: If you add a new instance, then edit the entire table to correct the length of the cells. -->

Also see the `instances.json` file.

## Installation

### Method 1: Containers

> [!NOTE]
>
> It's the recommended way to run Kittygram.

#### Docker

1. Install [git](https://git-scm.org), [git-lfs](https://git-lfs.com) and
   [Docker](https://docs.docker.com/engine/install).

   > [!TIP]
   >
   > You can also install
   > [Docker Desktop for GUI](https://www.docker.com/products/docker-desktop),
   > or [LazyDocker for TUI](https://github.com/jesseduffield/lazydocker).

2. Clone the repository, move to the `kittygram` folder, set up Git LFS, and
   start the container:

   ```bash
   git clone git@codeberg.org:irelephant/kittygram.git --depth=1 && cd kittygram && git lfs pull
   sudo docker compose up
   ```

#### Podman

1. Install [git](https://git-scm.org), [git-lfs](https://git-lfs.com),
   [Podman](https://podman.io/docs/installation) and
   [Podman Compose](https://docs.podman.io/en/latest/markdown/podman-compose.1.html).

   > [!TIP]
   >
   > You can also install [Podman Desktop for GUI](https://podman-desktop.io),
   > or [Podman TUI](https://github.com/containers/podman-tui).

2. Clone the repository, move to the `kittygram` folder, set up Git LFS, and
   start the container:

   > [!WARNING]
   >
   > Don't run Podman as root (`sudo` / `doas`).

   ```bash
   git clone git@codeberg.org:irelephant/kittygram.git --depth=1 && cd kittygram && git lfs pull
   podman-compose -p kittygram -f compose.yaml up -d
   ```

   > [!NOTE]
   >
   > If you have DNS/network issues, change DNS in `compose.yaml` to Podman
   > native using: `podman compose exec kittygram cat /etc/resolv.conf`.

### Method 2: Native

1. Install [openresty](https://openresty.org/en/installation.html),
   [redis](https://redis.io/docs/latest/operate/oss_and_stack/install/archive/install-redis)
   or [valkey](https://valkey.io/topics/installation),
   [luarocks](https://luarocks.org) (likely in your distro's package manager)
   and [git-lfs](https://git-lfs.com).

2. Clone the repository, move to the `kittygram` folder, and set up Git LFS.

   ```bash
   git clone git@codeberg.org:irelephant/kittygram.git --depth=1 && cd kittygram && git lfs pull
   ```

3. Copy the example configuration files:

   ```bash
   cp nginx.example.conf nginx.conf && cp config.example.lua config.lua
   ```

4. Run:

   ```bash
   luarocks init --lua-version=5.1 --lua-versions=5.1
   CC="gcc -std=gnu99" luarocks build && lapis migrate

   lapis serve production
   ```

## Info

### License

Kittygram is licensed under the
[AGPL-3.0](https://codeberg.org/irelephant/kittygram/src/branch/main/LICENSE).

### Community

Feel free to join the
[Matrix room](https://matrix.to/#/#kittygram:private.coffee), or email me at
[irelephant@disroot.org](mailto:irelephant@disroot.org).

- Icon made by [nulla](https://codeberg.org/nulla).
- README design made by [koru](https://codeberg.org/koru).

⭐ If you like this project, please consider giving it a star!
