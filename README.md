<div align="center"> <!-- rumdl-disable-line MD033 --> <!-- rumdl-disable-line MD041 -->

# Kittygram

Kittygram is an anonymous, privacy-friendly, lightweight, and open-source
Instagram frontend inspired by [nitter](https://github.com/zedeus/nitter).
It offers a clean, fast way to browse Instagram without the usual clutter or tracking.

![preview](docs/assets/cover.png)

<!-- Colors - https://colorhunt.co/palette/14279b3d56b25c7aeae6e6e6 -->
[![Codeberg License](https://img.shields.io/badge/AGPL--3.0-5C7AEA?style=for-the-badge&logo=semanticscholar&logoColor=E6E6E6&label=LICENSE&labelColor=3D56B2)](https://www.gnu.org/licenses/agpl-3.0.en.html)
[![Codeberg Stars](https://img.shields.io/gitea/stars/irelephant/kittygram?gitea_url=https://codeberg.org&style=for-the-badge&logo=codeberg&logoColor=E6E6E6&labelColor=3D56B2&color=5C7AEA)](https://codeberg.org/irelephant/kittygram/stars)
[![Codeberg Issues](https://img.shields.io/gitea/issues/open/irelephant/kittygram?gitea_url=https://codeberg.org&style=for-the-badge&logo=gitbook&logoColor=E6E6E6&labelColor=3D56B2&color=5C7AEA)](https://codeberg.org/irelephant/kittygram/issues)

</div>

## Table of contents

- [Kittygram](#kittygram)
  - [Table of contents](#table-of-contents)
  - [Why Kittygram?](#why-kittygram)
    - [Limitations](#limitations)
  - [Instances](#instances)
  - [Installation](#installation)
    - [Method 1: Docker (Recommend!)](#-method-1-docker-recommend)
    - [Method 2: Running from scratch](#method-2-running-from-scratch)
  - [Info](#info)
    - [License](#license)
    - [Community](#community)

## Why Kittygram?

The official Instagram web interface is heavy on JavaScript,
slow to load, and filled with pop-ups.
Kittygram avoids all of that by serving fully prerendered pages,
making it faster and easier to use.

Kittygram also helps you avoid the heavy tracking instagram does,
as all requests are handled by kittygram.

### Limitations

- As of now, only the first ~20 comments on a post can be fetched.
- Instagram aggresively rate-limits requests coming from servers,
which can make running a public instance difficult.

## Instances

| Instance link:                                               | Operated by:                                  | Notes:                |
|--------------------------------------------------------------|-----------------------------------------------|-----------------------|
| [kittygram.irelephant.net](https://kittygram.irelephant.net) | [Irelephant](https://codeberg.org/irelephant) | Creator of Kittygram. |
| [kittygr.am](https://kittygr.am)                             | [FSKY](https://fsky.io)                       |                       |
| [kittygram.kareem.one](https://kittygram.kareem.one)         | [Kareem](https://kareem.one)                  | Cloudflare.           |
| [kittygram.nexussfan.cz](https://kittygram.nexussfan.cz)     | [NexusSfan](https://mrchicken.nexussfan.cz)   |                       |
| [kg.lus.lu](https://kg.lus.lu)                               | [ffb0f3](https://lus.lu)                      |                       |

<!-- Note: If you add a new instance, then edit the entire table to correct the length of the cells. -->

Also see `/instances.json` file.

## Installation

### ✨ Method 1: Docker (Recommend!)

1. Install [git](https://git-scm.org), [git-lfs](https://git-lfs.com) and [docker](https://docs.docker.com/engine/install).
2. Clone, move to Kittygram folder and setup LFS.

```bash
git clone https://codeberg.org/irelephant/kittygram.git
cd kittygram
git lfs pull
```

3. Start the container.

```bash
sudo docker compose up
```

### Method 2: Running from scratch

1. Install [openresty](https://openresty.org/en/installation.html),
[redis](https://redis.io/docs/latest/operate/oss_and_stack/install/archive/install-redis) or [valkey](https://valkey.io/topics/installation),
[luarocks](https://luarocks.org) (likely in your distro's package manager) and [git-lfs](https://git-lfs.com/).
2. Clone, move to Kittygram folder and setup LFS.

```bash
git clone https://codeberg.org/irelephant/kittygram.git
cd kittygram
git lfs pull
```

3. Copy the example configuration files:

```bash
cp nginx.example.conf nginx.conf
cp config.example.lua config.lua
```

4. Run:

```bash
luarocks init --lua-version=5.1 --lua-versions=5.1
CC="gcc -std=gnu99" luarocks build

lapis migrate

# Run the project
lapis serve production
```

## Info

### License

Kittygram is licensed under the [AGPL-3.0](https://codeberg.org/irelephant/kittygram/src/branch/main/LICENSE).

### Community

Feel free to join the [Matrix room](https://matrix.to/#/#kittygram:private.coffee), or email me at [irelephant@disroot.org](mailto:irelephant@disroot.org).

- Icon made by [nulla](https://codeberg.org/nulla).
- README design made by [Ivan Kopylov](https://codeberg.org/ivankopylov6603).

⭐ If you like this project, please consider giving it a star!
