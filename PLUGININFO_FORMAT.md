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
> separate Markdown file instead of as comments in the JSON. FPP only reads the
> keys it knows about, so extra keys (like `_documentation`) are ignored safely.

---

## Top-level fields

| Field | Type | Required | Meaning |
|-------|------|----------|---------|
| `repoName` | string | **yes** | Unique identifier for the plugin. Used as the on-disk install directory name and passed to the installer, so keep it filesystem/shell safe (it is run through `escapeshellcmd`). Must match the name used for this plugin in `fpp-data/pluginList.json`. |
| `name` | string | **yes** | Human-readable title shown at the top of the plugin's card in the Plugin Manager. |
| `author` | string | recommended | Author name / handle, shown in the **Author** field. |
| `description` | string | recommended | Short description shown in the **Description** field. Keep it to a line or two. |
| `homeURL` | string | recommended | Project home page. Rendered as the **home** link in the plugin card footer. |
| `srcURL` | string | **yes** | Git clone URL (normally ending in `.git`). FPP clones this to install the plugin, and links to it as **View Source**. |
| `bugURL` | string | recommended | Issue tracker URL. Rendered as the **Report a Bug** link. |
| `allowUpdates` | integer (`0`/`1`) | optional | Controls whether FPP offers in-place git updates for the installed plugin. When omitted it is treated as allowed. Set to `0` to hide the **Update Now** / **Check for Updates** buttons (install-once plugins). Can also be set per-version inside `versions[]` (the per-version value takes effect for that version). |
| `private` | boolean | optional | Set `true` if the plugin is hosted in a **private** GitHub repo. FPP will clone it using the GitHub username + Personal Access Token configured on the Developer settings page, and show a **Private** badge. |
| `linkName` | string | optional (legacy) | Creates a symlink in the plugin directory (`<linkName>` → the plugin) on install, removed on uninstall. Used by older plugins whose code expects a directory name different from `repoName`. **Only takes effect when the cloned repo does *not* ship its own `pluginInfo.json`** (i.e. info hosted externally) — for a modern plugin that ships this file, `linkName` does nothing. New plugins normally don't need it. |
| `versions` | array | **yes** | One or more compatibility entries. See below. |

> **Fields FPP ignores.** Some plugins in the wild also carry a top-level
> `version` (e.g. `"1.0.1"`) or a `requires` array. **FPP does not read
> either** — they have no effect. Don't rely on them; use the `versions[]`
> entries for compatibility and `scripts/fpp_install.sh` for dependencies.

---

## The `versions` array

`versions` is a list of entries, each describing how to install the plugin for a
particular range of FPP releases (and, optionally, particular hardware). When
you open the Plugin Manager, FPP walks the list and picks the **first entry
whose FPP-version range and platform match** the machine you're on. That entry's
`branch`/`sha` is what gets installed.

### Version-entry fields

| Field | Type | Required | Meaning |
|-------|------|----------|---------|
| `minFPPVersion` | string | **yes** | Minimum FPP version this entry supports, e.g. `"9.0"`. Compared against the running FPP version. |
| `maxFPPVersion` | string | **yes** | Maximum FPP version this entry supports. The special values `"0"`, `"0.0"`, or `""` mean **open-ended** — FPP treats the entry as valid through the rest of the current major version series (internally, up to that major's `.999`). Use an open-ended max on your newest entry so it keeps working on the current release. |
| `branch` | string | **yes** | Git branch FPP checks out when installing this entry. |
| `sha` | string | **yes** | Specific commit to pin to. Use `""` (empty string) to always install the **latest** commit on `branch`. Pin a real SHA to freeze an entry to a known-good commit (typical for old FPP majors you no longer update). |
| `allowUpdates` | integer (`0`/`1`) | optional | Per-version override of the top-level `allowUpdates`. Set `0` on a frozen/pinned entry so FPP won't try to pull newer commits into an old FPP release. |
| `platforms` | array of strings | optional | Restrict this entry to specific hardware. If present, the entry only matches when the running platform is in the list. If omitted, the entry matches **all** platforms. See below. |
| `dependencies` | object | optional | **Reserved — not currently used by FPP** (see below). |

### `minFPPVersion` / `maxFPPVersion` semantics

- Give each entry a version *window*. FPP picks the entry whose window contains
  the running version.
- The newest/current entry should use an open-ended max (`"0"`) so it stays
  valid as new point releases ship.
- If FPP finds **no** matching entry for the current version, the plugin is shown
  as having compatible versions for other FPP releases, and (if you install it
  anyway) is flagged **"Install untested plugin at your own risk."**

### Worked multi-version example

Modeled on how `fpp-arcade` does it — freeze old majors to a specific commit and
disable updates for them, keep the current major open-ended:

```json
"versions": [
    {
        "minFPPVersion": "7.0",
        "maxFPPVersion": "8.99",
        "branch": "master",
        "sha": "4723c22f89200e25d683d73e310f96a922438814",
        "allowUpdates": 1
    },
    {
        "minFPPVersion": "9.0",
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

Platform names referenced in the FPP UI code include:

| Value in `platforms` | Hardware |
|----------------------|----------|
| `"Raspberry Pi"` | Raspberry Pi boards |
| `"BeagleBone Black"` | BeagleBone Black |
| `"BeagleBone 64"` | BeagleBone 64 |

Other platform strings FPP emits are shown verbatim in the compatibility notice.
This table lists the values the UI special-cases; confirm the exact string for
any other target against `/etc/fpp/platform` on that device before relying on it.

In practice `platforms` is used sparingly — e.g. `Dynamic_RDS` and
`fpp-node-red` both restrict to `[ "Raspberry Pi" ]` because they rely on
Pi-specific hardware/services.

Example — a version that only installs on Raspberry Pi:

```json
{
    "minFPPVersion": "9.0",
    "maxFPPVersion": "0",
    "branch": "master",
    "sha": "",
    "platforms": [ "Raspberry Pi" ]
}
```

---

## `dependencies` (reserved — currently unused)

The template includes a `dependencies` object with `plugins`, `packages`, and
`scripts` arrays:

```json
"dependencies": {
    "plugins":  [ "fpp-plugin-CoolPlugin1" ],
    "packages": [ "system-package-name1" ],
    "scripts":  [ "Control/script-repository-script1" ]
}
```

**No current FPP code reads this block** — it is reserved for possible future
use. To install real dependencies today, do it from your plugin's own
`scripts/fpp_install.sh`, which FPP runs automatically after cloning the plugin
(via `scripts/install_plugin`). Put `apt` package installs, extra setup, etc.
there.

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
            "minFPPVersion": "9.0",
            "maxFPPVersion": "0",
            "branch": "master",
            "sha": ""
        }
    ]
}
```

- `repoName` / `name` / `srcURL` / `versions` are the required fields.
- The single version entry says: "install on FPP 9.0 and up (open-ended), from
  the tip of `master`, and allow updates."
- Add `platforms` to a version entry to restrict hardware; add more entries to
  support older FPP majors with pinned commits.

---

## A note on comments

JSON has no comment syntax, and FPP's parser is strict, so you can't annotate
`pluginInfo.json` inline. This file is the reference instead. The template's
`pluginInfo.json` carries a single `_documentation` string pointing here; FPP
ignores unknown keys, so it's harmless.
