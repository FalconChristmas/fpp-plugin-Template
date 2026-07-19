# FPP Plugin Guidelines

Rules and conventions for a well-behaved FPP plugin. Companion to
[`PLUGININFO_FORMAT.md`](PLUGININFO_FORMAT.md) (the `pluginInfo.json` metadata
format) and the template plugin in this repository.

---

## For humans — the short version

An FPP plugin runs with full privileges on someone's show controller. A good one
behaves like a good guest:

- **One log file, and let FPP manage it.** Write all runtime logging to a single
  file in FPP's logs directory — don't scatter logs and don't roll your own
  rotation. FPP rotates plugin logs aggressively for you (it keeps only the last
  couple).
- **Clean up completely on uninstall.** Anything you set up *outside* your plugin
  folder — services, timers, cron jobs, symlinks, files under `/etc` — must be
  removed by your uninstall script, and that script must be safe to run twice.
- **Don't destabilize the host.** Never reboot the device or restart `fppd`
  yourself; ask FPP to do it through the proper flag/API. No `curl … | bash`.
- **Stay in your lane.** Read and write only inside your plugin directory (plus
  your one log file and anything you declared as a dependency).
- **Declare dependencies, don't smuggle them.** Put apt packages, scripts, and
  other required plugins in the `dependencies` block of `pluginInfo.json`. Anything
  installed ad-hoc from `fpp_install.sh` must go through `apt-get`, `npm`, or `uv` —
  never `curl … | bash` or `pip --break-system-packages`. No `sudo` (your
  install already runs as root).
- **Talk to FPP through its interfaces.** Prefer FPP's PHP helpers and the HTTP
  API over editing FPP's config files or restarting `fppd` by hand.
- **Make the UI work everywhere.** It must read correctly in **both light and dark
  themes** and on **phone to desktop / touch screens** — use FPP's Bootstrap-based
  helpers and never hardcode colors or fixed pixel widths.

> **Using an AI assistant (Claude, Copilot, Cursor, …) to build or change your
> plugin? Give it this file.** The detailed section below is written to be
> dropped straight into an AI assistant's context so it produces a plugin that
> follows these rules. Point your assistant at this document — or paste it in —
> before you start, and again when you ask it to add a feature.

---

## Detailed rules (for AI assistants and thorough authors)

Each rule is stated precisely so it can be checked mechanically. `<repoName>` is
the `repoName` from your `pluginInfo.json`. `<mediadir>` is FPP's media directory
— normally `/home/fpp/media` (exposed as `${MEDIADIR}` when you source
`${FPPDIR}/scripts/common`). Your plugin lives in
`<mediadir>/plugins/<repoName>/`.

### 1. Logging

1.1 **Exactly one runtime log file, with a fixed name:**
`<logdir>/plugin-<repoName>.log`, where `<logdir>` is FPP's logs directory
(normally `/home/fpp/media/logs`) and `<repoName>` is your `pluginInfo.json`
`repoName`. Do **not** hard-code `/home/fpp/media/logs` — resolve the logs
directory the FPP-provided way for your language (see the snippets below), so a
relocated media directory still works. Do not open a second log, write into your
plugin directory, use `/tmp`, or create dated/numbered variants yourself.

1.2 **Do not implement your own rotation, truncation, or cleanup cron.** FPP
rotates `plugin-*.log` for you — by size, keeping only the last **2** copies,
compressed — using `copytruncate`, so you may hold the file open across a rotation
without reopening it. (Do **not** open with truncate/`filemode="w"` as a poor-man's
rotation — that discards the log every restart.) Rolling your own rotation fights
FPP's.

1.3 **Nothing else logs.** Don't spam syslog, don't leave logs inside your plugin
directory or `/tmp`, and don't log secrets (tokens, passwords, PATs).

1.4 The `plugin-` prefix and the shared logs directory are what let FPP rotate
plugin logs aggressively (separately from its own logs) and surface them in the
log viewer and Support Zip — so a single, correctly-named log is all support needs.

#### Ready-to-use snippets

Each produces `<logdir>/plugin-<repoName>.log`. **Replace `<repoName>`** with your
plugin's `repoName`.

**PHP** — use the FPP-provided `$settings['logDirectory']`:

```php
$logFile = $settings['logDirectory'] . '/plugin-<repoName>.log';
file_put_contents($logFile, date('c') . ' your message' . "\n", FILE_APPEND | LOCK_EX);
```

**Python** (daemon / callback) — FPP exports `LOGDIR` to processes it launches;
fall back to the default install path:

```python
import os, logging

logdir = os.environ.get('LOGDIR', '/home/fpp/media/logs')
logging.basicConfig(
    filename=os.path.join(logdir, 'plugin-<repoName>.log'),  # default mode 'a' (append)
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s',
)
logging.info('your message')
```

**Shell** (install / lifecycle scripts, and shell daemons) — source FPP's
`common` to get `$LOGDIR`; `$FPPDIR` is provided by FPP:

```sh
: "${FPPDIR:=/opt/fpp}"
. "${FPPDIR}/scripts/common"        # sets LOGDIR (and MEDIADIR, etc.)
PLUGIN_LOG="${LOGDIR}/plugin-<repoName>.log"

echo "$(date '+%Y-%m-%d %H:%M:%S') your message" >> "$PLUGIN_LOG"
# background a helper into the same log:
# nohup ./your-daemon.sh >> "$PLUGIN_LOG" 2>&1 &
```

### 2. Install / uninstall lifecycle

FPP runs `scripts/fpp_install.sh` after cloning your repo, and
`scripts/fpp_uninstall.sh` when the plugin is removed. It also runs
`scripts/{preStart,postStart,preStop,postStop}.sh` around each `fppd` start/stop.

2.1 **Undo everything on uninstall.** Every side effect your install (or
`preStart.sh`/`postStart.sh`) creates *outside* the plugin directory must be
reversed in `fpp_uninstall.sh`: systemd units (`systemctl disable --now <unit>`
then remove the unit file), timers, cron entries, symlinks, and any files written
under `/etc`, `/usr/local`, etc.

2.2 **Uninstall must be idempotent.** Guard each removal so re-running the script —
or running it when the item was never created — still exits `0`
(e.g. `systemctl disable --now foo 2>/dev/null || true`, `rm -f`, test-before-remove).

2.3 **Install must be idempotent too.** `fpp_install.sh` is re-run by
**Reinstall All Plugins** and by updates, so it must be safe to run repeatedly —
guard service creation, don't append duplicates to config files, don't fail if a
step was already done.

2.4 **Do not remove declared dependencies yourself.** FPP reference-counts the apt
`packages` from your `dependencies` block and removes them only when nothing else
needs them. Removing shared packages by hand can break other plugins.

2.5 **Do not use `sudo`.** Install/uninstall/hook scripts already run as root.
`sudo apt …`, `sudo chmod …`, etc. are redundant and hide assumptions — call the
commands directly, and never loosen device permissions (no `chmod 666`/`a+w`).

2.6 **Hooks must be fast and non-blocking.** `preStart`/`postStart` run
**synchronously** and delay `fppd` starting a show; `preStop`/`postStop` delay it
stopping. Do not `sleep 30`, poll, or `while true` in a hook — background any
long-running work (`nohup ./daemon.sh >> "$PLUGIN_LOG" 2>&1 &`) and return quickly.

2.7 **Stop what you start.** A daemon or service you launch in `postStart` must be
stopped in `preStop`/`postStop` (not only on uninstall), so it doesn't linger or
double-run after an `fppd` restart.

2.8 **Native (C++) plugins: build in `fpp_install.sh`, not in a hook.** `make` (or
`cmake`/`g++`/`clang`) in `preStart.sh`/`postStart.sh` is a common copy-paste
mistake — it re-runs on **every** `fppd` start/stop (§2.6), and it's redundant work:
your plugin is already (re)built by three separate paths before `fppd` ever starts:
- **Fresh install**: `fpp_install.sh` runs the build itself (it should — see below).
- **Plugin-only update**: the Plugin Manager's Update button runs `scripts/fpp_upgrade.sh`
  if you have one, otherwise falls back to re-running `fpp_install.sh`.
- **FPP core upgrade**: FPP rebuilds every plugin directory with a root-level
  `Makefile` itself (`make -C <plugin> SRCDIR=$SRCDIR`) before restarting `fppd` —
  you don't need to do anything for this case at all.

Put your `make "SRCDIR=${SRCDIR}"` (or equivalent) in `fpp_install.sh`, which
already runs before either restart. Do not add a build step to
`preStart.sh`/`postStart.sh` "just in case" — if you have a build step that genuinely
can't wait for install/upgrade (e.g. recovering from a binary built for a different
CPU after an SD image clone), guard it behind a cheap check (compare a stored
version/arch fingerprint) so the common case is a no-op, not a rebuild.

### 3. Talk to FPP through its interfaces, not its internals

Use FPP's stable, documented surfaces; don't reach into its files or process
directly. **Why this matters: FPP's on-disk config formats (the `settings` file,
`channeloutputs.json`, `model-overlays.json`, …) are internal and can change at any
release without notice, whereas the command and HTTP APIs are a maintained,
versioned contract.** A plugin built on the APIs keeps working across FPP upgrades;
one built on the raw files breaks the first time a format shifts. In order of
preference:

3.1 **From a PHP page** (which runs inside the FPP web app): call FPP's **PHP
helper functions directly** — `$settings[...]`, the `PrintSetting*` helpers,
`WriteSettingToFile`, and the command helpers. This is the cheapest and most
stable path.

3.2 **To make FPP *do* something, trigger a named command** (from any language) via
the **Command API** — `POST /api/command` (or `POST /api/command/<name>` with a JSON
array body); names come from `GET /api/commands`, e.g. `"Volume Set"`,
`"Start Playlist"`. This is the same high-level, version-stable action layer the UI,
scheduler, events, and MQTT use — args are validated, and you can register your own
commands. Prefer it over hand-rolling low-level calls. Prefer the HTTP API over the
`fpp` CLI for integration.

3.3 **To *read* FPP state, use the documented HTTP API** at `http://localhost/api/…`
(the openapi.json contract). **Do not** call fppd's internal port **`:32322`**
directly — Apache proxies it under `/api/*`, and that proxied path is the stable
surface; the raw port is internal and can change.

3.4 **For *any* FPP data, use the API — never read or write the underlying files
directly.** This is a general rule, not a per-file list: whatever FPP manages has an
API endpoint or accessor, so use it rather than touching the JSON on disk. Examples,
not an exhaustive list: `GET /api/models` instead of `config/model-overlays.json`,
`/api/channel/output/*` instead of `channeloutputs.json`, `/api/playlists` /
`/api/schedule` / `/api/sequence`, and `getSetting()` / `$settings` for settings — and
the same holds for any other FPP data. The API is the stable representation, reflects
**live** state fppd may not have flushed to disk, and performs the right **side
effects** (e.g. `PUT /api/models` writes the file *and* sets the restart flag).
Hand-parsing or hand-editing FPP's files couples you to an internal format that can
change at any release, may not take effect until a restart, and can corrupt state.

3.5 **Your own config is the exception.** Store *your* settings the FPP way —
`WriteSettingToFile(key, value, "<repoName>")` (→ `config/plugin.<repoName>`) — and
your own data under `<mediadir>/plugindata/`. That is using FPP's plugin mechanism.

3.6 **To apply a restart/reboot, set the flag** — never restart `fppd`, reboot the
box, or call a direct-restart path (`RestartFPPD()`, `/api/system/fppd/restart`,
`systemctl restart fppd`, `fpp -r`). Set the flag with your language's native helper
so FPP sequences it safely around a running show:

| Context | Set the restart flag |
|---|---|
| Shell (install/hooks) | source `${FPPDIR}/scripts/common` (defines the function), then `setSetting restartFlag 1` |
| C++ | `setSetting("restartFlag", "1")` (declared in `settings.h`, already pulled in via `fpp-pch.h`) |
| PHP config form | pass `$restart = 1` to `PrintSetting*` |
| Browser JS (config page) | `SetRestartFlag(1)` |
| External process (Python…) | `PUT /api/settings/restartFlag` body `1` |

Use `rebootFlag` / `SetRebootFlag(1)` for a reboot.

### 4. Don't destabilize the host

4.1 **Never** call `reboot`/`shutdown`, and never restart, kill, or `systemctl
restart fppd` directly — use the restart/reboot flags (§3.5) so FPP sequences it
safely around a running show.

4.2 **No piped remote execution** (`curl … | bash`, `wget … | sh`,
`… | sudo bash`). Install pinned, declared dependencies instead.

4.3 Don't disable or reconfigure core FPP services or system configuration.

### 5. Filesystem boundaries

Read and write only within: your plugin directory
(`<mediadir>/plugins/<repoName>/`), your single log file, your config in
`config/plugin.<repoName>`, your data in `<mediadir>/plugindata/`, and paths you
explicitly declared. Never write into other plugins, FPP core, or arbitrary system
locations.

### 6. Dependencies

6.1 Declare apt packages, Python (PyPI) packages, script-repository scripts, and
other required plugins in the top-level `dependencies` block of `pluginInfo.json`
(see `PLUGININFO_FORMAT.md`). FPP installs them before your `fpp_install.sh` runs —
Python packages via `uv pip install --system` (`dependencies.python`), straight
into FPP's system Python, which your scripts can then use directly via the plain
`python3` on PATH — no per-plugin venv, no `"$SCRIPT_DIR/.venv/..."` indirection.
Prefer this over installing Python packages yourself in `fpp_install.sh`. A
specific `versions[]` entry may also carry its own `dependencies`, additional to
the top-level ones, for something that differs between FPP majors (e.g. a
renamed apt package) — see `PLUGININFO_FORMAT.md`.

> **Python dependencies are installed system-wide, not per-plugin.** Unlike
> `packages` (apt), they are not reference-counted or isolated: two plugins
> declaring the same package share one system install, and a real version
> conflict between two plugins' declared `python` deps will surface as an
> install failure rather than staying silently isolated. Pin loosely
> (`requests`, not `requests==2.31.0`) unless you specifically need an exact
> version, to minimize collisions with other plugins.

> **`dependencies` is FPP 10+ only, today.** FPP 9 and earlier silently ignore
> the whole block. If you still support FPP 9/8/older, keep installing those
> same things from `scripts/fpp_install.sh` too — `dependencies` is additive
> for FPP 10+ users, not a replacement, until pre-10 support is dropped.
> Expect FPP 11/12 to be when a full migration off manual `fpp_install.sh`
> installs gets encouraged.

6.2 **If you need to install something ad-hoc from `fpp_install.sh`** (beyond
what's declared in `dependencies`), use only `apt-get`, `npm`, or `uv` — no
`curl|bash` bootstrappers, and **never** `pip install --break-system-packages`,
which corrupts the system Python. For Python, use `uv pip install --system`
(PEP 668-safe) instead of bare `pip` — but prefer declaring it in
`dependencies.python` (§6.1) over doing this ad hoc at all.

6.3 Anything else your install genuinely needs belongs in `fpp_install.sh`, and
stays inside your plugin directory.

### 7. Resource honesty

If your plugin is memory- or CPU-hungry, declare it with the optional
`minMemoryMB` / `minCpuCores` top-level fields in `pluginInfo.json` (see
`PLUGININFO_FORMAT.md`). FPP uses these to keep your plugin off boards that
can't run it well, rather than letting it disrupt a show.

### 8. User interface

FPP's UI runs on desktops, tablets, and phones in the field, in both light and
dark themes. Your plugin's pages must too.

8.1 **Build on FPP's UI, don't reinvent it.** Use the `PrintSetting*` / toggle
helpers for config forms and Bootstrap 5.3 utility classes for layout — you
inherit theming, responsiveness, persistence, and restart/reboot handling for
free. Use `$.jGrowl({ themeState: 'success'|'danger' })` for toasts.

8.2 **Theme-aware — never hardcode colors.** No hex (`#000`/`#fff`), named colors,
or `rgb()` in markup or inline styles. Use Bootstrap semantic classes
(`text-body`, `text-danger`, `border`, `bg-body-tertiary`) and CSS variables
(`var(--bs-border-color)`, `var(--fpp-*)`). **Test every page in both light and
dark** (FPP's theme toggle / `data-bs-theme`). *(The old `border: 2px solid #000`
fieldset pattern is exactly what breaks in dark mode — use `class="border"`.)*

8.3 **Responsive — no fixed pixel widths.** Use the Bootstrap grid, `%`/`rem`, and
`max-width: 100%`; wrap wide tables in `.table-responsive`. Pages must work from a
~320px phone to a large desktop with **no horizontal page scroll**.

8.4 **Touch-friendly.** Use real tap targets (buttons/toggles, not tiny icon
links), avoid hover-only interactions, and leave finger-sized spacing.

8.5 **Minimize custom CSS.** If it's truly unavoidable, scope it to your plugin and
theme it with `[data-bs-theme="dark"]` overrides plus variables — never a fixed
palette.

### 9. Menu entries

`menu.inc` registers your plugin's entries into FPP's menu, one array per entry
with a `type` of `status`, `content`, `output`, or `help`.

9.1 **At most one entry per `type`.** Each of the four menu areas may contain no
more than one entry from your plugin — a plugin can still appear under multiple
areas (e.g. one `status` entry *and* one `help` entry), just never more than one
entry within the *same* area. If you have several things a user might want under
one area (e.g. a help page, a home-page link, and a credits/about page), combine
them onto a single page rather than adding a menu entry per page — the template's
default `menu.inc` (three separate `help` entries) is the anti-pattern to avoid,
not an example to copy.

---

## Pre-submission checklist

- [ ] Exactly one runtime log at `<logdir>/plugin-<repoName>.log` (logs dir
      resolved via FPP, not hard-coded); no self-rotation, no truncate-on-start.
- [ ] `fpp_uninstall.sh` removes every service / timer / cron entry / symlink /
      out-of-tree file the plugin created, and is safe to run twice.
- [ ] `fpp_install.sh` is idempotent (safe to re-run via Reinstall All).
- [ ] Hooks return quickly (long work backgrounded); daemons started in
      `postStart` are stopped in `preStop`/`postStop`.
- [ ] Native (C++) build happens in `fpp_install.sh`, not in `preStart.sh`/
      `postStart.sh` — install/upgrade/FPP-core-upgrade already cover it.
- [ ] No `sudo`, no `reboot`/`shutdown`, no direct `fppd` restart, no
      `curl … | bash`, no `pip --break-system-packages`.
- [ ] Talks to FPP via helpers/HTTP API; no hand-editing of core FPP config.
- [ ] Own config in `config/plugin.<repoName>`, data in `plugindata/`; all writes
      confined to the plugin directory and declared paths.
- [ ] apt packages / scripts / plugin deps declared in `pluginInfo.json`
      `dependencies` where possible; any ad-hoc install in `fpp_install.sh` uses
      only `apt-get`/`npm`/`uv` (no `curl|bash`).
- [ ] UI verified in light **and** dark, and on a phone-width screen; no hardcoded
      colors, no fixed-pixel layout.
- [ ] Heavy plugins declare resource hints as top-level `pluginInfo.json` fields.
- [ ] `menu.inc` has at most one entry per `type` (status/content/output/help).
