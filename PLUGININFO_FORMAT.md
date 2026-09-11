# `pluginInfo.json` Format Reference

Every FPP plugin ships a `pluginInfo.json` in the root of its repository. This
is the metadata file FPP reads to **list** the plugin in the Plugin Manager,
decide **which version** is compatible with the running FPP release and
hardware, and **install/update** it. To have a plugin appear in the Plugin
Manager it must also be added to
[`FalconChristmas/fpp-data/pluginList.json`](https://github.com/FalconChristmas/fpp-data/blob/master/pluginList.json),
which points at this file.

> **`pluginInfo.json` must be strict JSON.** FPP parses it with strict parsers
> (PHP `json_decode` and the browser's JSON fetch) and does **not** strip
> comments. A `//` or `/* … */` comment anywhere in the file will make the
> plugin fail to load and fail to install. That is why this reference lives in a
> separate Markdown file instead of as comments in the JSON.

> **Machine-readable schema — strictly enforced.** A JSON Schema for this format
> lives alongside this file:
> [`pluginInfo.schema.json`](https://github.com/FalconChristmas/fpp-plugin-Template/blob/master/pluginInfo.schema.json).
> Point your editor at it for validation and autocomplete, e.g. add
> `"$schema": "https://raw.githubusercontent.com/FalconChristmas/fpp-plugin-Template/master/pluginInfo.schema.json"`
> as the first key of your `pluginInfo.json`. The schema is the complete
> recognized field set and rejects anything not listed in it — including typos
> and made-up keys — and CI validates every submission against it. This is a
> separate, stricter check from FPP's own runtime parsing: FPP itself just
> reads the specific keys it needs and silently ignores whatever else is in the
> object (that's still true, and always will be — it's how `json_decode` +
> array access works), but the schema will reject a plugin that fails to
> disclose what it's putting in the file, even if FPP itself wouldn't have
> minded. Don't rely on FPP's runtime leniency to skip the schema.

---

## Top-level fields

| Field | Type | Required | Meaning |
|-------|------|----------|---------|
| `repoName` | string | **yes** | Unique identifier for the plugin. Used as the on-disk install directory name and passed to the installer, so keep it filesystem/shell safe (it is run through `escapeshellcmd`). Must match both the name used for this plugin in `fpp-data/pluginList.json` and the actual GitHub repository name (the one in `srcURL`) — CI flags a mismatch as a best-practice finding, since FPP installs into `${PLUGINDIR}/${repoName}` regardless of what the repo is actually called, so a mismatch only surfaces later as confusion (support, docs, cross-referencing). |
| `name` | string | **yes** | Human-readable title shown at the top of the plugin's card in the Plugin Manager. |
| `author` | string | **yes** | Author name / handle, shown in the **Author** field. |
| `description` | string | **yes** | Short description shown in the **Description** field. Keep it to a line or two. |
| `homeURL` | string | **yes** | Project home page. Rendered as the **home** link in the plugin card footer. Must start `http://` or `https://`. |
| `srcURL` | string | **yes** | Git clone URL (normally ending in `.git`). FPP clones this to install the plugin, and links to it as **View Source**. Must be a `github.com` repo — that's the only source FPP plugins support, and it's the trust anchor for the Official badge. |
| `bugURL` | string | **yes** | Issue tracker URL. Rendered as the **Report a Bug** link. Must start `http://` or `https://`. |
| `iconURL` | string | optional | Icon URL, used only when the repo has no `icon.png` (128x128 or 256x256) in its root — ship that so the icon renders offline. Must be an `https://raw.githubusercontent.com/...` URL ending in `.png`, `.jpg`, `.jpeg`, `.gif` or `.webp`; anything else is ignored. |
| `documentation` | string | optional | URL to human documentation for this plugin. Purely informational — not read or rendered by FPP itself. |
| `allowUpdates` | integer (`0`/`1`) | optional | Controls whether FPP offers in-place git updates for the installed plugin. When omitted it is treated as allowed. Set to `0` to hide the **Update Now** / **Check for Updates** buttons (install-once plugins). Can also be set per-version inside `versions[]` (the per-version value takes effect for that version). |
| `minMemoryMB` | integer | optional | Minimum system RAM (MB) the plugin needs to run acceptably, across all versions. If the device has less, FPP flags it (and hides it on the Basic UI level). See **Resource hints** below. |
| `minCpuCores` | integer | optional | Minimum recommended CPU cores, across all versions. If the device has fewer, FPP flags it (and hides it on the Basic UI level). |
| `private` | boolean | optional | Set `true` if the plugin is hosted in a **private** GitHub repo. FPP will clone it using the GitHub username + Personal Access Token configured on the Developer settings page, and show a **Private** badge. |
| `version` | — | **do not use** | Legacy. FPP does not read a top-level `version` — use `versions[]` entries for compatibility. Explicitly allowed by the schema only so a plugin carrying it from an older template doesn't fail validation. |
| `requires` | array | **do not use** | Legacy. FPP does not read a top-level `requires` — declare needs in the `dependencies` block. Explicitly allowed by the schema only so a plugin carrying it from an older template doesn't fail validation. |
| `linkName` | string | optional (legacy) | Creates a symlink in the plugin directory (`<linkName>` → the plugin) on install, removed on uninstall. Used by older plugins whose code expects a directory name different from `repoName`. **Only takes effect when the cloned repo does *not* ship its own `pluginInfo.json`** (i.e. info hosted externally) — for a modern plugin that ships this file, `linkName` does nothing. New plugins normally don't need it. |
| `delist` | boolean | optional | Set `true` to request removal from FPP's Plugin Manager list (retire the plugin). Existing installs are unaffected. Because only someone with write access to your repo can set it, it also proves ownership for a de-list request. Note this is a `fpp-data` / CI convention only — FPP itself never reads `delist`; the plugin disappears when its `pluginList.json` entry is removed. |
| `versions` | array | **yes** | One or more compatibility entries. See below. |
| `dependencies` | object | optional | Other things this plugin needs, installed automatically **before** the plugin's own `scripts/fpp_install.sh` runs: `packages` (apt), `python` (PyPI, via `pip`), `scripts` (script repository), and `plugins` (other FPP plugins, installed transitively). Applies to every entry in `versions[]`; a specific entry may declare its own `dependencies` too, additive to this one. See below. |

---

## The `versions` array

`versions` is a list of entries, each describing how to install the plugin for a
particular range of FPP releases (and, optionally, particular hardware). When
you open the Plugin Manager, FPP walks the whole list and picks the **last entry
whose FPP-version range and platform match** the machine you're on (the JS and
PHP selectors both overwrite the match on every hit, so a later entry wins over
an earlier one when two windows overlap). That entry's `branch`/`sha` is what
gets installed. List entries oldest-first so the newest window is the one that
wins.

### Version-entry fields

| Field | Type | Required | Meaning |
|-------|------|----------|---------|
| `minFPPVersion` | string | **yes** | Minimum FPP version this entry supports, e.g. `"9.0"`. Compared against the running FPP version. |
| `maxFPPVersion` | string | **yes** | Maximum FPP version this entry supports. The special values `"0"`, `"0.0"`, or `""` mean **open-ended**, but only within the major named by `minFPPVersion`: if that major matches the running FPP major the entry is unbounded, otherwise FPP caps it at the previous major's `.999` and treats the plugin as **untested** on this release (see below). Use an open-ended max on your newest entry, and bump that entry's `minFPPVersion` to each new FPP major once you've verified the plugin on it. |
| `branch` | string | **yes** | Git branch FPP checks out when installing this entry. |
| `sha` | string | **yes** | Specific commit to pin to. Use `""` (empty string) to always install the **latest** commit on `branch`. Pin a real SHA to freeze an entry to a known-good commit (typical for old FPP majors you no longer update). |
| `allowUpdates` | integer (`0`/`1`) | optional | Per-version override of the top-level `allowUpdates`. Set `0` on a frozen/pinned entry so FPP won't try to pull newer commits into an old FPP release. |
| `platforms` | array of strings | optional | Restrict this entry to specific hardware. If present, the entry only matches when the running platform is in the list. If omitted, the entry matches **all** platforms. See below. |
| `dependencies` | object | optional | Dependencies ADDITIONAL to the top-level `dependencies` block, installed only when this entry is selected (FPP 10+). See `## dependencies` below. |

### `minFPPVersion` / `maxFPPVersion` semantics

- Give each entry a version *window*. FPP picks the (last) entry whose window
  contains the running version. Bounds are compared against the full running
  version (`major.minor.patch`); the upper bound is inclusive in the Plugin
  Manager UI.
- The newest/current entry should use an open-ended max (`"0"`) so it stays
  valid as new point releases ship **within that major**.
- An open-ended entry is *not* carried forward across majors. On FPP 10, an
  entry `{"minFPPVersion": "9.0", "maxFPPVersion": "0"}` is treated as
  `9.0`–`9.999` and the plugin is flagged **untested**: the card carries a
  *Not updated for FPP 10* badge and an **Install anyway** button (the detail
  view spells out *"This plugin has not been updated to work with your version
  of FPP"*), it is hidden from the Basic UI level, and it can only be reached
  from Advanced/Developer. To clear the flag, bump
  `minFPPVersion` on the open-ended entry to the current major (adding a pinned
  entry for the old major if you still support it).
- If **no** entry matches and none is open-ended (every `maxFPPVersion` is a
  real version below the running one, or `platforms` excludes this board), the
  plugin is **incompatible**: it appears only in the *Incompatible* section on
  Advanced/Developer with *"No version is compatible with your FPP
  version/platform"* and **no install button at all**.

### Worked multi-version example

Recommended shape (`fpp-arcade` does something similar): every major you no
longer develop for is **pinned** to the last commit known to work there, with
updates off; only the current major tracks the branch tip. Note the last
entry's `minFPPVersion` is the **current** major (`10.0`); an open-ended entry
starting at `9.0` would show as *untested* on FPP 10. Never leave an old
major on `"sha": ""` — those boxes would keep pulling commits made for the
newer FPP:

```json
"versions": [
    {
        "minFPPVersion": "7.0",
        "maxFPPVersion": "9.99",
        "branch": "master",
        "sha": "4723c22f89200e25d683d73e310f96a922438814",
        "allowUpdates": 0
    },
    {
        "minFPPVersion": "10.0",
        "maxFPPVersion": "0",
        "branch": "master",
        "sha": "",
        "allowUpdates": 1
    }
]
```

---

## `platforms`

FPP runs on very different hardware. Use `platforms` on a version entry to keep a
build off boards it can't run on. The strings must **exactly match the platform
name FPP reports** (the contents of `/etc/fpp/platform` on the device).

The value FPP writes to `/etc/fpp/platform` is one of a fixed set:

| Value in `platforms` | Platform |
|----------------------|----------|
| `"Raspberry Pi"` | Raspberry Pi boards |
| `"BeagleBone Black"` | BeagleBone Black |
| `"BeagleBone 64"` | BeagleBone 64 |
| `"Armbian"` | Armbian-based SBCs |
| `"Debian"` | Generic Debian |
| `"Ubuntu"` | Generic Ubuntu |
| `"Fedora"` | Fedora |
| `"MacOS"` | macOS (native) |
| `"UNKNOWN"` | Unrecognized platform |

Match the string exactly, and confirm it against `/etc/fpp/platform` on the
target device before relying on it.

In practice `platforms` is used sparingly — e.g. `Dynamic_RDS` and
`fpp-node-red` both restrict to `[ "Raspberry Pi" ]` because they rely on
Pi-specific hardware/services.

Example — a version that only installs on Raspberry Pi:

```json
{
    "minFPPVersion": "10.0",
    "maxFPPVersion": "0",
    "branch": "master",
    "sha": "",
    "platforms": [ "Raspberry Pi" ]
}
```

---

## Resource hints

FPP runs on hardware ranging from a Pi Zero / BeagleBone (≈512 MB RAM, 1 core) up
to a Pi 5 / CM5 (2–8 GB, 4 cores). A demanding plugin can starve a low-end board
and disrupt a running show. A plugin may **optionally** declare the minimums it
needs so the Plugin Manager can steer users away from installs their device can't
run well.

> **Both fields are optional, self-reported, and fully backward-compatible.** A
> plugin that declares neither is treated as unconstrained, so existing plugins
> are unaffected. FPP **never hard-blocks** on these values — at most it hides a
> plugin from the Basic UI level and asks for confirmation on higher levels.

| Field | Type | Meaning |
|-------|------|---------|
| `minMemoryMB` | integer | Minimum RAM (MB) to run acceptably. |
| `minCpuCores` | integer | Minimum recommended CPU cores. |

The fields live at the **top level** of `pluginInfo.json` (next to `allowUpdates`),
not on individual `versions[]` entries — they describe the plugin as a whole, and
there is no per-version override, so you declare them once rather than repeating
them on every entry.

How FPP compares them against the device (total RAM + CPU cores, detected
automatically):

- **Advisory badge.** When a minimum isn't met, a muted `Not Enough RAM/CPU`
  badge appears on the plugin card / detail view, and the install button
  changes to **Install anyway**.
- **Basic UI level hides it.** If `minMemoryMB` or `minCpuCores` exceeds the
  device, the plugin is hidden on the Basic UI level (including from the Popular
  strip) so casual users never install something that would starve their board.
- **Advanced / Developer see it with a confirm.** The plugin stays visible with
  the badge, and installing it pops a confirmation noting the shortfall (the
  values are self-reported, and a power user may know their setup is fine).

Example — a plugin that wants 1 GB RAM and 2 CPU cores to run (top level,
alongside `allowUpdates`, **not** inside a `versions[]` entry — FPP ignores them
there):

```json
{
    "repoName": "fpp-plugin-Example",
    "allowUpdates": 1,
    "minMemoryMB": 1024,
    "minCpuCores": 2,
    "versions": [
        { "minFPPVersion": "10.0", "maxFPPVersion": "0", "branch": "master", "sha": "" }
    ]
}
```

---

## `dependencies`

A `dependencies` object lets a plugin declare things it needs. FPP installs them
**automatically, before the plugin's own `scripts/fpp_install.sh` runs**, so your
install script can rely on them being present.

> **FPP 10+ only.** Automatic installation of `dependencies` — the top-level
> block, a per-version one nested in `versions[]` (below), `packages`, `python`,
> `scripts`, `plugins`, all of it — is only implemented in FPP 10. On FPP 9 and
> earlier the entire block is **silently ignored** (FPP never errors on it, it
> just isn't read). **If your plugin still supports FPP 9/8/older, keep
> installing those same things yourself from `scripts/fpp_install.sh`** —
> `dependencies` doesn't cover those releases for you, so dropping the manual
> install there would silently break them.
>
> We expect to encourage plugins to migrate fully onto `dependencies` (and
> retire the manual installs in `fpp_install.sh`) once **FPP 11 or FPP 12**
> ships and FPP 8/9 support is no longer a concern for most plugins. There's no
> need to make that jump today if you still support older releases — declaring
> `dependencies` now is additive (it helps FPP 10+ users, e.g. with reference
> counting on uninstall) and doesn't require dropping your existing
> `fpp_install.sh` installs until you're ready to drop pre-10 support entirely.

**Top-level and per-version, and they combine.** A top-level `dependencies` block
applies to every entry in `versions[]`. A specific `versions[]` entry may *also*
declare its own `dependencies`, which are **additional** to the top-level set —
installed only when that particular entry is the one selected for the running
FPP version/platform. Use this when a dependency differs across FPP majors (a
package renamed between the FPP9 and FPP10 image, for example) rather than
duplicating the whole block per version:

```json
"dependencies": { "packages": [ "common-package" ] },
"versions": [
    { "minFPPVersion": "9.0", "maxFPPVersion": "9.99", "branch": "master", "sha": "",
      "dependencies": { "packages": [ "libfoo1" ] } },
    { "minFPPVersion": "10.0", "maxFPPVersion": "0", "branch": "master", "sha": "",
      "dependencies": { "packages": [ "libfoo-dev" ] } }
]
```
On FPP 10, the entry above resolves to `common-package` + `libfoo-dev` (not
`libfoo1` — that's only added when the FPP 9 entry is the one selected). One
caveat: the server-side selector used when a plugin is installed *as a
dependency of another plugin* treats `maxFPPVersion` as **exclusive** (the UI
treats it as inclusive), so an entry capped at exactly the running version
(e.g. `"maxFPPVersion": "10.1"` on FPP 10.1.0) matches in the Plugin Manager
but not during dependency resolution. Use `.99` caps and open-ended maxes to stay
clear of the edge. Note
this whole example is itself FPP-10-only per the callout above — the FPP 9
entry's own `dependencies` are declared for documentation/forward-compatibility
(so they're ready when you eventually drop pre-10 support) but won't actually
install anything on a real FPP 9 device; `fpp_install.sh` is still what
installs `libfoo1` there today.

```json
"dependencies": {
    "packages": [ "system-package-name1" ],
    "python":   [ "requests", "pyserial>=3.5" ],
    "scripts":  [ "Control/script-repository-script1" ],
    "plugins":  [ "fpp-plugin-CoolPlugin1" ]
}
```

They are resolved in this order — **packages → python → scripts → plugins**:

| Key | Meaning |
|-----|---------|
| `packages` | System (apt) packages. FPP runs `apt-get update` then installs each one, and records that **this plugin** requested it. |
| `python` | Python (PyPI) packages, installed with `pip install --break-system-packages` straight into FPP's **system** Python (not isolated per plugin, not reference-counted — a package shared by two plugins is just one shared install). Your scripts run against it via the plain `python3` on PATH (see `PLUGIN_GUIDELINES.md` §6.1). `pip` ships by default with FPP. |
| `scripts` | Script-repository entries in `"Category/file"` form (the same layout as the **Content Setup → Script Repository** page, backed by `FalconChristmas/fpp-scripts`). Each is downloaded into your scripts directory; note repository scripts may run their own `# InstallAction:` steps on install. |
| `plugins` | Other FPP plugins, by `repoName`. Each is cloned and installed the same way (its own dependencies resolved too), then its `fpp_install.sh` runs. The name **must exist in [`fpp-data/pluginList.json`](https://github.com/FalconChristmas/fpp-data/blob/master/pluginList.json)** — arbitrary URLs are not accepted here. Dependency chains are cycle-guarded, and an already-installed dependency is left as-is. |

> **`packages` needs a Debian-family platform** (Raspberry Pi, BeagleBone,
> Armbian, Debian, Ubuntu). On platforms without apt (Fedora, macOS) FPP
> **refuses to install a plugin that declares required packages** rather than
> leave it half-installed — so if your plugin genuinely needs packages, also
> restrict it to the supported hardware with `platforms[]`.

### Package ownership and removal

Package dependencies are **reference-counted**. FPP tracks every requester of a
package (the literal `"user"` for anything installed from the Package Manager
page, or a plugin's `repoName` for a package installed as its dependency). When
a plugin is **uninstalled**, its claim on each of its declared packages is
dropped, and a package is only actually `apt-get remove`d once **nothing else
still needs it** — so a package shared by two plugins, or one you also installed
yourself, stays put. This bookkeeping lives in
`/home/fpp/media/config/userpackages.json`, which is also what FPP replays to
reinstall your packages after an fppos OS upgrade.

Dependency **scripts and plugins are *not* auto-removed** on uninstall (a script
may have been customized, and a dependency plugin may be useful on its own) —
only packages are reference-counted and cleaned up.

### Still use `fpp_install.sh` for the rest

`dependencies` is for declaring named packages/scripts/plugins. Anything else
your plugin needs at install time — building code, downloading assets, writing
config — still belongs in your own `scripts/fpp_install.sh`, which FPP runs
after the dependencies are in place.

---

## Fields you should NOT set

These are added by FPP at install time and must **not** be authored in your
`pluginInfo.json`:

| Field | Why |
|-------|-----|
| `infoURL` | Injected by the Plugin Manager with the URL your `pluginInfo.json` was fetched from. |
| `useCredentials` | Runtime flag FPP sets when the file was loaded through its credentialed proxy (for private repos). Use `private: true` instead to declare a private repo. |

---

## Full annotated example

```json
{
    "repoName": "fpp-plugin-Template",
    "name": "Template Plugin for FPP Plugin developers",
    "author": "John Doe (jdoe)",
    "description": "This template plugin is designed to make it easier for plugin authors to create new FPP Plugins.",
    "homeURL": "https://github.com/FalconChristmas/fpp-plugin-Template",
    "srcURL": "https://github.com/FalconChristmas/fpp-plugin-Template.git",
    "bugURL": "https://github.com/FalconChristmas/fpp-plugin-Template/issues",
    "allowUpdates": 1,
    "versions": [
        {
            "minFPPVersion": "10.0",
            "maxFPPVersion": "0",
            "branch": "master",
            "sha": ""
        }
    ]
}
```

- `repoName` / `name` / `author` / `description` / `homeURL` / `srcURL` /
  `bugURL` / `versions` are the required fields.
- The single version entry says: "install on any FPP 10.x (open-ended within
  the 10 series), from the tip of `master`, and allow updates." When FPP 11
  ships this entry will show as *untested* there until `minFPPVersion` is
  bumped to `11.0` (or a second entry is added).
- Add `platforms` to a version entry to restrict hardware; add more entries to
  support older FPP majors with pinned commits.

---

## A note on comments

JSON has no comment syntax, and FPP's parser is strict, so you can't annotate
`pluginInfo.json` inline. This file is the reference instead. The template's
`pluginInfo.json` carries a `documentation` string pointing here — a real,
schema-recognized field (see the table above), not just a tolerated stray key.
