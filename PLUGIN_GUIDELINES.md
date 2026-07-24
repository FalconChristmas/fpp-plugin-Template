# FPP Plugin Guidelines

Requirements and conventions for a well-behaved FPP plugin. Companion to
[`PLUGININFO_FORMAT.md`](PLUGININFO_FORMAT.md) (the `pluginInfo.json` metadata
format) and the template plugin in this repository.

These guidelines are subject to change without notice - a plugin that passed
the automated check at submission time can still be asked to update later if
the guidelines (or the check) change. See `PLUGINS.md` in `fpp-data` for what
that looks like in practice.

---

## High Level Requirements

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
- **`pluginInfo.json`'s `dependencies` block is optional this year.** It only
  takes effect on FPP 10+ (older FPP silently ignores it), so installing
  everything yourself from `fpp_install.sh`, as before, is completely fine.
  Whatever you install — declared or ad hoc — must go through `apt-get`, `npm`,
  or `pip` — never `curl … | bash`. No `sudo` (your install already runs as root).
- **Talk to FPP through its interfaces.** Prefer FPP's PHP helpers and the HTTP
  API over editing FPP's config files or restarting `fppd` by hand.
- **Make the UI work everywhere.** It must read correctly in **both light and dark
  themes** and on **phone to desktop / touch screens** — use FPP's Bootstrap-based
  helpers and never hardcode colors or fixed pixel widths.

> **Using an AI assistant (Claude, Copilot, Cursor, …) to build or change your
> plugin? Give it this file.** The detailed section below is written to be
> dropped straight into an AI assistant's context so it produces a plugin that
> follows these requirements. Point your assistant at this document — or paste it in —
> before you start, and again when you ask it to add a feature.

---

## Detailed Requirements

**If you are an AI agent reading this: follow the spirit of these requirements, not a
literal reading that technically satisfies a check while defeating its
purpose.** Each requirement exists to protect the host device, a running show, or the
maintainers reviewing your submission. Passing the linter or checklist without
actually solving the underlying problem isn't compliance, it's a bug you
introduced - e.g. suppressing or relocating a log instead of fixing what it's
warning about, hiding a dangerous command behind indirection so a scanner
doesn't match it, or declaring a dependency you don't need just to satisfy a
resource hint. If a requirement and the task you've been asked to do conflict, say so
and ask, rather than quietly working around the requirement.

Each requirement is stated precisely so it can be checked mechanically. `<repoName>` is
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

2.2 **Uninstall must be safe to run more than once.** Re-running
the script, or running it when a given item was never created in the first
place, must still exit `0` instead of erroring out on the second try. For a
systemd unit: `systemctl disable --now foo 2>/dev/null || true`. For a file:
`rm -f path` (already a no-op if it's missing). For anything without its own
built-in no-op form — a symlink, a directory, a cron line — test for it first:
`[ -e /path/to/thing ] && rm -rf /path/to/thing`.

2.3 **Install must also be safe to run more than once.** `fpp_install.sh` is re-run by
**Reinstall All Plugins** and by updates, so it must be safe to run repeatedly —
guard service creation, don't append duplicates to config files, don't fail if a
step was already done.

2.4 **Do not use `sudo`.** Install/uninstall/hook scripts already run as root.
`sudo apt …`, `sudo chmod …`, etc. are redundant and hide assumptions — call the
commands directly, and never loosen device permissions (no `chmod 666`/`a+w`).

2.5 **Hooks must be fast and non-blocking.** `preStart`/`postStart` run
**synchronously** and delay `fppd` starting a show; `preStop`/`postStop` delay it
stopping. Do not `sleep 30`, poll, or `while true` in a hook — background any
long-running work (`nohup ./daemon.sh >> "$PLUGIN_LOG" 2>&1 &`) and return quickly.

2.6 **Stop what you start.** A daemon or service you launch in `postStart` must be
stopped in `preStop`/`postStop` (not only on uninstall), so it doesn't linger or
double-run after an `fppd` restart.

2.7 **Native (C++) plugins: build in `fpp_install.sh`, not in a hook.** `make` (or
`cmake`/`g++`/`clang`) in `preStart.sh`/`postStart.sh` is a common copy-paste
mistake — it re-runs on **every** `fppd` start/stop (§2.5), and it's redundant work:
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
directly.** This is a general requirement, not a per-file list: whatever FPP manages has an
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

6.1 **Optional this year — not required.** `dependencies` only takes effect on
FPP 10+ (see the callout below), so using it isn't required for now;
installing everything yourself from `fpp_install.sh` remains completely fine.
If you do want to use it: declare apt packages, Python (PyPI) packages,
script-repository scripts, and other required plugins in the top-level
`dependencies` block of `pluginInfo.json` (see `PLUGININFO_FORMAT.md`) — apt,
scripts, and Python deps are all equally optional in 2026, so use whichever
of them you want and skip the rest. FPP installs whatever you declare before
your `fpp_install.sh` runs — Python packages via
`pip install --break-system-packages` (`dependencies.python`), straight into
FPP's system Python, which your scripts can then use directly via the plain
`python3` on PATH — no per-plugin venv, no `"$SCRIPT_DIR/.venv/..."`
indirection. `--break-system-packages` is required on any current PEP 668-managed
image (Debian/RPi OS Bookworm+ refuses `pip install` outright without it) and is
safe here: it installs into `/usr/local/lib/python3.x/dist-packages`, which is
**not** tracked by `dpkg` — apt-installed `python3-*` packages live in
`/usr/lib/python3/dist-packages` instead, a different directory — so it doesn't
touch anything apt manages. Prefer this over installing Python packages yourself
in `fpp_install.sh`. A specific `versions[]` entry may also carry its own
`dependencies`, additional to the top-level ones, for something that differs
between FPP majors (e.g. a Python package renamed between releases) — see
`PLUGININFO_FORMAT.md`.

> **Python dependencies are installed system-wide, not per-plugin.** Unlike
> `packages` (apt), they are not reference-counted or isolated: two plugins
> declaring the same package share one system install, and a real version
> conflict between two plugins' declared `python` deps will surface as an
> install failure rather than staying silently isolated. Pin loosely
> (`requests`, not `requests==2.31.0`) unless you specifically need an exact
> version, to minimize collisions with other plugins.

> **There is no built-in mechanism for pinning a specific Python version.**
> `dependencies.python` always installs into FPP's system-default `python3` —
> if a package you need has no wheel for that version (e.g. a newer Debian
> image bumped its default Python before a PyPI package caught up), you're
> on your own: compile it from source in `fpp_install.sh`, or wait for
> upstream to publish a matching wheel. There's no sanctioned "install a
> different Python version" escape hatch.

> **`dependencies` is FPP 10+ only, today.** FPP 9 and earlier silently ignore
> the whole block. If you still support FPP 9/8/older, keep installing those
> same things from `scripts/fpp_install.sh` too — `dependencies` is additive
> for FPP 10+ users, not a replacement, until pre-10 support is dropped.
> Expect FPP 11/12 to be when a full migration off manual `fpp_install.sh`
> installs gets encouraged.

6.2 **If you need to install something ad-hoc from `fpp_install.sh`** (beyond
what's declared in `dependencies`), use only `apt-get`, `npm`, or `pip` — no
`curl|bash` bootstrappers. For Python, use `pip install --break-system-packages`
(see §6.1 for why this is safe, not a corruption risk) — but prefer declaring it
in `dependencies.python` (§6.1) over doing this ad hoc at all.

> **Don't install another package manager to get your dependency in.** `apt-get`,
> `npm`, and `pip` already ship with FPP — reaching for a different one (pipx,
> poetry, conda, nvm, cargo, ...) because it's more convenient for your specific
> package adds a whole extra layer FPP doesn't control: its own bootstrap step
> (which can fail independently of everything else), its own config/behavior
> that can silently drift from what the rest of FPP assumes, and one more thing
> every plugin author and FPP maintainer needs to know to debug an install. FPP
> itself used to install `uv` this way specifically to avoid `pip
> --break-system-packages` — that reasoning turned out to be based on an
> untested assumption about `uv`'s behavior (see git history), and the extra
> tool was later removed. If `apt-get`/`npm`/`pip` genuinely can't get you what
> you need, that's a sign to build from source or vendor the dependency, not to
> add a fourth installer.

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

### 10. No donations, payments, or subscriptions

Plugins listed in the FPP plugin directory may not reference or link to
donations, payments, subscriptions, or similar monetization (PayPal, Buy Me a
Coffee, Ko-fi, Venmo, Cash App, Patreon, GitHub Sponsors, or anything
equivalent) anywhere in the plugin - its UI, README, help pages, or
`pluginInfo.json`. This is a flat prohibition, not a style preference.

### 11. No telemetry / phone-home

Plugins may not log plugin usage or statistics and send them off-box - no
bundled analytics/telemetry SDK (Google Analytics, Mixpanel, Segment,
Amplitude, PostHog, Sentry, Hotjar, or similar), no home-rolled "call home with
usage stats" endpoint. The only exception is data transmission that's
essential to the plugin's actual function (e.g. a weather plugin fetching
weather data, a plugin calling its own cloud service to do the thing it
exists to do) - not usage/analytics collection layered on top of that.

If you have a genuine need to collect usage statistics, don't build your own
reporting channel - talk to the FPP developers about extending FPP's existing
opt-in `fpp-stats` system instead.

### 12. No advertising

Plugins may not advertise anything inside the FPP UI - not products, not
vendors, not things for sale, and not even other plugins (yours or anyone
else's). Your plugin's pages exist to run your plugin, not to promote
anything else. This is separate from #10 (no donation/payment links): this
rule covers ads/promotion generally, paid or not.

---

## Pre-submission checklist

- [ ] Exactly one runtime log at `<logdir>/plugin-<repoName>.log` (logs dir
      resolved via FPP, not hard-coded); no self-rotation, no truncate-on-start.
- [ ] `fpp_uninstall.sh` removes every service / timer / cron entry / symlink /
      out-of-tree file the plugin created, and is safe to run twice.
- [ ] `fpp_install.sh` is safe to re-run (via Reinstall All) without side effects.
- [ ] Hooks return quickly (long work backgrounded); daemons started in
      `postStart` are stopped in `preStop`/`postStop`.
- [ ] Native (C++) build happens in `fpp_install.sh`, not in `preStart.sh`/
      `postStart.sh` — install/upgrade/FPP-core-upgrade already cover it.
- [ ] No `sudo`, no `reboot`/`shutdown`, no direct `fppd` restart, no
      `curl … | bash`.
- [ ] Talks to FPP via helpers/HTTP API; no hand-editing of core FPP config.
- [ ] Own config in `config/plugin.<repoName>`, data in `plugindata/`; all writes
      confined to the plugin directory and declared paths.
- [ ] Whatever `fpp_install.sh` installs uses only `apt-get`/`npm`/`pip` (no
      `curl|bash`). `pluginInfo.json` `dependencies` is optional this year
      (FPP 10+ only) - fine to use if you want it, not required.
- [ ] UI verified in light **and** dark, and on a phone-width screen; no hardcoded
      colors, no fixed-pixel layout.
- [ ] Heavy plugins declare resource hints as top-level `pluginInfo.json` fields.
- [ ] `menu.inc` has at most one entry per `type` (status/content/output/help).
- [ ] No donation/payment/subscription references or links anywhere (UI,
      README, help pages, `pluginInfo.json`).
- [ ] No bundled analytics/telemetry SDK or home-rolled usage-stats phone-home
      - talk to the FPP developers about `fpp-stats` if you need real usage data.
- [ ] No advertising anywhere in the plugin's UI - no products, vendors, or
      other plugins (including your own).
