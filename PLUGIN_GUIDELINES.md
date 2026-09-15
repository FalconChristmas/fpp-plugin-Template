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
directory or `/tmp`, and don't log secrets (tokens, passwords, PATs). At the
default log level, never log credentials, phone numbers, message bodies or
e-mail addresses — a debug level the operator opts into may carry more, the
default may not (see §14.4 and §14.5).

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

2.8 **Install and uninstall already take effect live, for most plugins —
you don't need to opt in, but you do need a callbacks script.** The Plugin
Manager calls `POST /api/fppd/plugin/<name>/load` right after your install
script and `.../unload` right before your uninstall script, for script
plugins and native (C++) plugins alike. This re-registers (or withdraws) the
commands from your `commands/descriptions.json`, re-runs your callbacks
script's lifecycle hooks, and — for a native plugin — destroys and recreates
your `Plugin` object, all without restarting `fppd`. It's best-effort: if the
call fails (e.g. `fppd` isn't running), the install/uninstall itself still
succeeds and the change just takes effect at the next restart instead, same
as before this existed.

**The one gate on this: `load` checks for a `callbacks`/`callbacks.{sh,pl,php,py}`
file before doing anything else, and treats "none found" as a successful
no-op — it never even reaches the code that reads `commands/descriptions.json`.**
If your plugin registers commands but has no callbacks script at all (nothing
hooking show start/stop), your commands are *not* live-registered on install;
you still need `restartFlag` for that case. Any plugin that has a callbacks
script — even a trivial one — doesn't need it just for its own commands or
callbacks to activate; see §3.6.

Native plugins get one more layer on top of this: whether the `.so` itself is
actually unmapped (`dlclose()`d) from the process, versus staying mapped
(a few hundred KB) until `fppd` next restarts anyway. That's what
`FPP_PLUGIN_SUPPORTS_UNLOAD()` controls, and it's real memory hygiene for
frequent install/upgrade/uninstall cycles — but it is **not** what makes your
plugin's behavior update live; that already happens for every plugin per the
paragraph above.

2.9 **Native (C++) plugins: build so you can be unloaded, not just loaded.**
Opting in to `FPP_PLUGIN_SUPPORTS_UNLOAD()` (§2.8) so your `.so` mapping is
actually released needs a few things done deliberately, not by default:

- **Register HTTP routes through FPP, not straight on Drogon.** Call
  `FPPPlugins::registerPluginApi()`/`unregisterPluginApi()` for every route —
  never `drogon::app().registerHandler()` directly. Drogon has no route-removal
  API, so a handler wired in directly stays in the router for the process
  lifetime; that alone makes a plugin impossible to unload or hot-swap for a
  rebuilt version.
- **Withdraw your own commands.** A `Command` you register with
  `CommandManager::addCommand()` is yours: in `shutdown()`, call
  `removeCommand()` for each one and delete it — `removeCommand()` only
  unregisters, it doesn't free anything. fppd keeps a backstop that deletes
  anything you leave behind at unload (and logs a warning naming your plugin),
  but that's a net, not a substitute — a command left running after unload
  reads through a dangling pointer into your (possibly unmapped) plugin.
- **Implement `shutdown()`, not just a destructor.** `FPPPlugins::Plugin::shutdown()`
  is the teardown point, called once your routes are disarmed and before your
  plugin is destroyed — a destructor runs too late for anything that could
  still be entered concurrently. Return a readiness predicate
  (`std::function<bool()>`) rather than blocking: fppd polls it (about once a
  second, capped at 60s) before proceeding, so asynchronous teardown (a media
  pipeline unwinding, a queued Drogon callback) has a real way to say "not yet"
  instead of racing destruction.
- **Tag your outbound `CurlManager` requests with your plugin name.** Every
  `add*` call takes a trailing owner argument; passing your name lets fppd
  cancel your in-flight requests as a group on unload, without running their
  callbacks.
- **Opt in explicitly with `FPP_PLUGIN_SUPPORTS_UNLOAD()`** (in your `Plugin`
  subclass) once the above is actually true — it's what lets fppd `dlclose()`
  your `.so` instead of just detaching the object and leaving the mapping
  until fppd itself restarts.
- **Build through FPP's shared `makefiles/common/setup.mk`**
  (`include $(SRCDIR)/makefiles/common/setup.mk` in your `Makefile`, same as
  every plugin in the catalog) rather than a hand-rolled build — that's what
  applies `-fno-gnu-unique` on your behalf. Without it, a single
  `static const std::string` inside *any* method defined in a class body
  (which is every inline method) can make glibc mark your whole `.so`
  NODELETE: `dlclose()` then reports success and unmaps nothing, silently, for
  the life of the process — `FPP_PLUGIN_SUPPORTS_UNLOAD()` ends up meaning
  less than it says. Verify after a build with
  `nm -D lib<repoName>.so | awk '$2=="u"'` — any output means this plugin has
  the problem.
- **Expect refusal if you produce a channel output.** A plugin defining
  `createChannelOutput()` is always refused a runtime unload while that output
  is in use, regardless of how well it does everything else above — the
  output object is owned by the output system and may be mid-show.

None of this is required to *load* — a plugin that skips it still installs,
uninstalls, and updates live per §2.8, just without its `.so` mapping actually
being released between cycles.

2.10 **Document HTTP routes with `apiDocs.json`.** A plugin that registers
routes via `registerPluginApi()` (see 2.9) can **optionally** ship an
`apiDocs.json` at the **root of the repo** (alongside `pluginInfo.json`, not
inside `versions[]`) to document those routes on FPP's `/api` reference page.
Without it, the routes still work — they just show up as "Undocumented - see
plugin documentation" there, since Drogon's route table records a path but not
which plugin registered it or what it does.

The file is an OpenAPI fragment: a bare `"paths"` object, keyed by the path
you passed to `registerPluginApi()`. FPP merges it into the generated spec
verbatim, so any standard OpenAPI operation shape (`summary`, `parameters`,
`requestBody`, `responses`, …) is fair game:

```json
{
    "paths": {
        "/api/plugin/<repoName>/status": {
            "get": {
                "summary": "Current plugin status",
                "responses": { "200": { "description": "OK" } }
            }
        }
    }
}
```

A subpath of a `family=true` registration can be documented too, even though
only the parent path is actually registered with Drogon (so FPP itself never
sees the subpaths to report them as undocumented in the first place).

Two safety notes: a plugin can't claim a path FPP core already documents (its
entry is silently ignored, not overwritten), and a malformed `apiDocs.json`
is logged and skipped rather than breaking the API page for anyone else.

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

3.6 **Most plugins never need to touch `restartFlag` — but check the gate in
§2.8 before assuming you're one of them.** Install and uninstall reload your
commands and callbacks live *if you have a callbacks script*; that used to
always require a restart and, for that case, no longer does. If your plugin
ships commands with no callbacks script at all, still set the flag — the
live-reload path skips you entirely. Also reach for the flag when your plugin
genuinely needs a full `fppd` restart for something outside the install/
uninstall live-reload path (e.g. a change that only takes effect during
fppd's own startup sequence). When you do need it, set the flag — never
restart `fppd`, reboot the box, or call a direct-restart path (`RestartFPPD()`,
`/api/system/fppd/restart`, `systemctl restart fppd`, `fpp -r`). Set the flag
with your language's native helper so FPP sequences it safely around a
running show:

| Context | Set the restart flag |
|---|---|
| Shell (install/hooks) | source `${FPPDIR}/scripts/common` (defines the function), then `setSetting restartFlag 1` |
| C++ | `setSetting("restartFlag", "1")` (declared in `settings.h`, already pulled in via `fpp-pch.h`) |
| PHP config form | pass `$restart = 1` to `PrintSetting*` |
| Browser JS (config page) | `SetRestartFlag(1)` |
| External process (Python…) | `PUT /api/settings/restartFlag` body `1` |

Use `rebootFlag` / `SetRebootFlag(1)` for a reboot.

3.7 **ArtNet: use the opcode handler API, never register the socket yourself.**
ArtNet fixes the port it listens on, so FPP's own e131bridge and any plugin
adding ArtNet trigger/timecode support necessarily share one socket. That
descriptor's epoll registration belongs solely to `e131bridge.cpp` — call
`AddArtNetOpcodeHandler()`/`RemoveArtNetOpcodeHandler()` for your opcode(s)
instead of registering the fd with `EPollManager` yourself. `EPollManager`
holds a single callback per descriptor, so a second direct registration
silently replaces the first, and removing yours takes ArtNet reception away
from *everyone* until something re-registers it.

### 4. Don't destabilize the host

4.1 **Never** call `reboot`/`shutdown`, and never restart, kill, or `systemctl
restart fppd` directly — use the restart/reboot flags (§3.5) so FPP sequences it
safely around a running show.

4.2 **No piped remote execution** (`curl … | bash`, `wget … | sh`,
`… | sudo bash`). Install pinned, declared dependencies instead.

4.3 Don't disable or reconfigure core FPP services or system configuration.

4.4 **The installer may not change the host's network exposure.** `fpp_install.sh`
(and the start/stop hooks) must not enable Samba or another file-sharing
service, open a listening port, join an overlay network, or set up a tunnel.
Anything of that kind is opt-in from the plugin's own config page after
install, and whatever the plugin enables it must reverse on uninstall (§2.1) —
including any edit it made to FPP's own settings file to get there. See §14
for how this shows up in the install dialog.

### 5. Filesystem boundaries

Read and write only within: your plugin directory
(`<mediadir>/plugins/<repoName>/`), your single log file, your config in
`config/plugin.<repoName>`, your data in `<mediadir>/plugindata/`, and paths you
explicitly declared. Never write into other plugins, FPP core, or arbitrary system
locations. Writing a system file to enable a service or share is a change to
network exposure, which the installer may not make (§4.4). Anything sensitive
— credentials, personal data, device-bound identity — belongs in `plugindata/`,
not `config/` (§14.11).

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
what's declared in `dependencies`), use only the public package managers that
already ship on the FPP image — `apt-get`, `npm`, `pip`, and `cpan` for Perl
(prefer `apt-get install lib<module>-perl` when Debian packages the module;
`cpan` fetches and builds from CPAN mirrors as root, which is slow on a Pi) —
no `curl|bash` bootstrappers. For Python, use `pip install --break-system-packages`
(see §6.1 for why this is safe, not a corruption risk) — but prefer declaring it
in `dependencies.python` (§6.1) over doing this ad hoc at all.

> **Don't install another package manager to get your dependency in.** `apt-get`,
> `npm`, `pip` and `cpan` already ship with FPP — reaching for a different one
> (gem, cargo, pipx, poetry, conda, nvm, ...) because it's more convenient for
> your specific package adds a whole extra layer FPP doesn't control: its own bootstrap step
> (which can fail independently of everything else), its own config/behavior
> that can silently drift from what the rest of FPP assumes, and one more thing
> every plugin author and FPP maintainer needs to know to debug an install.
> If `apt-get`/`npm`/`pip`/`cpan` genuinely can't get
> you what you need, that's a sign to build from source or vendor the
> dependency, not to add another installer. gem, cargo and any other package
> manager that is not already on the image are **not allowed** unless described
> in the `privacy` block (a `systemChanges` entry of kind `download`) and named
> in the description: everything fetched at install time runs as root, and
> every host it is fetched from is a recipient of the user's IP address (§14.1).
> Packages taken from the default apt, PyPI, npm and CPAN sources are *not* a
> `download` and need no `privacy` entry — the "Can it be checked?" light
> counts a package from a public source *whose source is published* as
> checkable code (a closed binary wheel or vendor SDK from PyPI or npm is
> not: that is `closedCode: true`). So is an open-source
> project's own release of its public code (its `.deb` from GitHub releases,
> say): declare the fetch as a `download` system change, but `closedCode`
> stays `false`. Only code nobody can read — a vendor binary, a downloaded
> `.so` with no source, an obfuscated script — is `closedCode: true`. The same
> goes for adding a package *source* — see §14.14.

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
"Essential" is bounded by §14.1 to §14.3: an essential transmission is allowed
only when the recipient is named in the description, it is off by default
(or is the one service the plugin exists to talk to), and it carries only
what that purpose needs - no hostname, serial, version or settings riding
along "because the API accepts them".

If you have a genuine need to collect usage statistics, don't build your own
reporting channel - talk to the FPP developers about extending FPP's existing
opt-in `fpp-stats` system instead.

### 12. No advertising

Plugins may not advertise anything inside the FPP UI - not products, not
vendors, not things for sale, and not even other plugins (yours or anyone
else's). Your plugin's pages exist to run your plugin, not to promote
anything else. This is separate from #10 (no donation/payment links): this
rule covers ads/promotion generally, paid or not.

### 13. Disclose third-party remote-access/tunneling services

If your plugin sets up, installs, or depends on a third-party tunneling or
remote-access service (Dataplicity, ngrok, Cloudflare Tunnel, Tailscale,
ZeroTier, localtunnel, serveo, pagekite, or similar) to work around FPP not
having a public HTTPS endpoint, that has to be clearly stated in
`pluginInfo.json`'s `description` field - not just buried in a README or setup
page. A user deciding whether to install your plugin needs to know upfront
that doing so may expose their FPP box's control surface to the internet
through a third party, before they've already installed it and started
configuring credentials.

This isn't a prohibition on using these services - they're often the only
practical way to receive an inbound webhook on a home network - it's a
transparency requirement. Say what the service is and why it's needed, e.g.
"*Uses Dataplicity to expose a public HTTPS endpoint so \<Provider\> can send
webhook events to your Pi.*"

### 14. Privacy and personal data

A plugin runs as root on a device that sits on someone's home network, plays
their show, and — depending on the plugin — may hold their credentials, talk to
services on their behalf, or handle data about visitors who never agreed to
anything. FPP builds the install confirmation dialog from the `privacy` block
in your `pluginInfo.json` (see `PLUGININFO_FORMAT.md`), so the rules below are
both what a good plugin does and what you describe there. They apply equally to
official and community plugins. §13 (disclose tunnelling services) is a
special case of 14.1.

You do not have to write the block by hand. The
[Privacy disclosure builder](https://falconchristmas.github.io/fpp-data/plugin_privacy_builder/)
(`?repo=owner/repo` pre-fills from your repo, or paste the JSON) walks
through the eight keys one at a time with the schema's own wording, applies
the same rules as the listing check while you type (GitHub hosts, `http://`,
hardware identifiers, `why` casing, length caps) and hands back the block on
its own or merged into your whole `pluginInfo.json`. The
[Plugin preview](https://falconchristmas.github.io/fpp-data/plugin_preview/)
then shows the card and install dialog FPP will build from it (§14.15).

14.1 **Name every off-box recipient up front.** Every host your plugin sends
to or fetches from — a cloud API, a content filter, a mail server, an MQTT
broker, a licence server, a package source other than the default apt, PyPI,
npm and CPAN ones — is
named in `pluginInfo.json`'s `description` (and in the `privacy` block's
`sends`), with *what* is sent and *why*. §13 already requires this for
tunnelling services; it applies to every recipient. "Profanity checker" is not
a disclosure when the checker is a third-party API that receives every message
a visitor sends; "installs from the vendor's own repository" is a recipient
too, and so is a CDN, font service or badge host that your own pages make
the operator's browser load — it sees their browser's address every time the
page opens; declare it in `sends` like any other hostname (`what`: "your
browser's address", `why`: "page styling" or similar). That applies only
when the load actually happens: FPP serves plugin pages under its own
Content-Security-Policy (`script-src 'self'`, `style-src 'self'`, `font-src
'self' data:`, `img-src 'self' data: blob:`, `default-src 'self'` for the
rest), so a CDN tag is a dead tag unless your install script whitelists the
host with `${FPPDIR}/scripts/ManageApacheContentPolicy.sh add <directive>
<host>` — the script takes `script-src`, `style-src`, `img-src`, `font-src`,
`connect-src`, `object-src` or `default-src`; an iframe or media load is
governed by `default-src`, so that is the key to add (the Template's
`scripts/fpp_install.sh` shows the call) — or the page
is served by your own listener (`remoteAccess` other than `none`). If you
whitelist it or serve it yourself, declare it in `sends`; if not, bundle the
file with the plugin or remove the tag — FPP's own pages bundle jQuery and
Bootstrap for the same reason (a show network is often offline). The listing
check sees these loads (`<script src>`, `<link href>`, `<img src>`, iframe
and media sources, CSS `url()`, `fetch()` literals, CSP `*-src` hosts you
set yourself), reads your `ManageApacheContentPolicy.sh add` calls, and
reports a missing whitelisted-or-self-served host as
`privacy-undeclared-recipients`; a host FPP's policy blocks gets
`privacy-csp-blocked-load` ("bundle the file or remove the tag") instead. A
user reads the description before installing and should not discover a
recipient by watching their router.

14.2 **Anything that transmits is off until the user turns it on.** No default
setting may send data to an optional third-party service. The one exception is
the single service the plugin exists to talk to (a weather plugin's weather
API, a vendor plugin's own vendor), and that one is named in the description
and the block's `summary`. A feature that *can* use a remote provider (say, a
filter with a local and a remote engine) defaults to the local one.

14.3 **Send only what the purpose needs.** Don't include the hostname, CPU
serial, IP address, FPP version, installed-plugin list, settings or the
contents of a whole mailbox unless the service genuinely cannot work without
them. Fetching "everything" and filtering locally still sent everything.

14.4 **Credentials.** Any setting holding a password, token, API key or secret:

- has a key name containing `Password`, `Token`, `Key` or `Secret` (the
  crash bundler redacts by key name — see below), and is declared
  `type: password` in the plugin's `settings.json` so the config UI masks it;
- is rendered with `inputType='password'` in the config UI;
- is never written to the log (§1.3), never placed in a URL, and never passed
  on a subprocess command line (`sshpass -p`, `curl -u user:pass`,
  `mysql -p…` all show up in `ps` for anything on the box — use the
  environment or a `0600` file instead);
- lives in a file that is `0600`, never `0777`.

Be aware that the crash-report bundle at its fullest level copies every
text file under `config/` through a redactor that works by key name only:
`password`, `passwd`, `passphrase`, `passcode`, `pwd`, `psk`, `secret`,
`token` or `credential` anywhere in the key, and `pass`, `key`, `auth` or
`pat` when not followed by a lowercase letter (so `apikey`, `mailpass` and
`authToken` are caught; `keyframe` is not), plus the keys
FPP's own `settings.json` marks `type: password`. Your plugin's `settings.json`
is never read, so a secret under a key like `mailcode` or `licence` ships in
clear. Binary files under `config/` (SQLite, gzip) are replaced by a stub.
That is why the key-name rule exists, and why 14.11 moves secrets out of
`config/` altogether.

14.5 **Personal data about people other than the operator.** Phone numbers,
message text, e-mail addresses, names, photos, camera frames, audio, and
records of visitor interactions (song requests, votes, doorbell presses):

- say in the description that the plugin collects it, from whom, and where it
  is kept (and describe it under `collects` in the `privacy` block);
- keep it out of the log at the default level (§1.3);
- give it a retention limit with automatic purge — default 30 days or less —
  and a delete control in the UI;
- never send it off-box except to the recipient disclosed for that purpose.

A visitor message that lands in a database, a JSON file *and* the log, and is
never deleted from any of them, fails all four.

14.6 **Cameras and microphones.** If the plugin uses either, the description
says whether frames or audio are stored, streamed (and where to) or discarded
immediately, and reminds the operator of their own obligations if a camera
covers a public area (footpath, street). "We discard everything" is worth
saying — silence reads as "we keep it".

14.7 **Radio and broadcast.** An FM/RDS, LoRa, or similar plugin says what it
broadcasts, that anyone in range receives it, and whether it is encrypted.

14.8 **A privacy control shown in the UI must do what it says.** A "delete after
download" checkbox that deletes nothing, or a "disable" command that writes
the wrong key, is worse than no control: the operator believes they are
protected. Test every privacy-related setting end to end.

14.9 **Never read or write FPP's privacy settings.** These eight keys are the
operator's decisions about *their* data and are off limits to plugins entirely:

`statsPublish`, `statsPublishUrl`, `ShareCrashData`, `FetchVendorLogos`,
`SendVendorSerial`, `SendVendorLogos`, `privacyConsent` and
`LegalJurisdiction`.

A write to `statsPublish` causes FPP to publish statistics within two
minutes, so this is a rule about a plugin transmitting on the operator's
behalf. The listing check fails on **any** write to these keys. Reading core
*credential* settings (`password`, the Wi-Fi PSK, `MQTTPassword`, `emailpass`,
`remoteToken`, OAuth secrets) is allowed only when described in the
`privacy` block as a `systemChanges` entry of kind `reads-core-credentials`
(which earns a red System changes light) and needed for the stated purpose — and for a native
plugin that includes the in-memory `getSetting()` path, not just the file.

14.10 **Inbound webhooks authenticate the caller** before the body is read —
a signature, a token, or the vendor's own request validator (vendoring the
validator and never calling it does not count). The help text next to any
"forward a port to this box" instruction must say plainly that doing so
exposes the whole FPP UI, which has no password by default.

14.11 **Store credentials, personal data and device-bound identity in
`plugindata/`, not `config/`.** Two FPP mechanisms make `config/` the wrong
place for anything sensitive: the crash bundler copies every text file under
`config/` at its fullest level (through the key-name redactor of 14.4; binary
files such as SQLite databases are stubbed) and never reads `plugindata/`; and
the JSON backup always carries
every plugin config in clear, so a restore writes it onto whichever player
receives it — pairing tokens, hardware-bound licences and invited-user
databases included. Non-sensitive settings may stay in `config/plugin.<repoName>`
(§3.5); tokens, passwords, visitor databases and anything tied to this specific
device go under `<mediadir>/plugindata/<repoName>/`, mode `0600`.

14.12 **Traffic through FPP's own helpers is the plugin's traffic.** Publishing
on FPP's MQTT connection, fetching through `CurlManager` or `urlGet`, or
registering HTTP routes with `registerPluginApi()` counts as sending or
listening and must be disclosed and described in the `privacy` block exactly
as if the plugin opened the socket itself. "My source contains no network call" is not a defence
when every message goes out via core.

14.13 **In-process plugins gate themselves.** A native (shared-library) plugin
is loaded at boot and is active whenever `fppd` runs, regardless of any
checkbox on its config page. Every listener and every publisher must be off
until the plugin's *own* enable setting is on — a fresh install must not start
receiving triggers or publishing state while the UI shows it disabled. A send
that happens whenever `fppd` runs, regardless of that setting, is
`alwaysOn: true` in the `privacy` block. A Python daemon started from a
callback is treated the same way.

#### 14.14 Package sources

Adding a package source (`/etc/apt/sources.list.d/`, a pip `index-url`, an
npm registry, a Docker or Flatpak remote) hands the operator of that source
root on the device, forever. The default answer is **no**. It is allowed only
when the package exists in no Debian or Raspberry Pi OS archive, and then all
of the following hold:

- it is described in the `privacy` block as a `systemChanges` entry of kind
  `package-source`, with the host and the package names in `what`, and named
  in the description;
- the signing key ships **in your repo** and is written to
  `/etc/apt/keyrings/` and referenced with `Signed-By` — never
  `curl … | apt-key add`, never `trusted=yes`;
- an apt preferences file pins the source to the named packages only, so it
  can never supply `libc`, `apache2`, or FPP itself;
- `fpp_uninstall.sh` removes the source, the keyring and the preferences file
  (§2.1).

A source needed only by an optional feature is added from a button *after*
install, with the same disclosure, not from `fpp_install.sh`. The listing
check compares `fpp_install.sh` and the rest of the code against the block (`privacy-undeclared-install`,
`-services`, `-privileges`, §14.16); nothing is checked at install time on the
player.

#### 14.15 How the install dialog is coloured

FPP computes six lights from your `privacy` block — you never pick a colour,
and every sentence in the dialog is FPP's, with your text inserted only as
fragments (`to`, `what`, `why`, `where`, `systemChanges[].what`, `summary`,
`other`). The same six lights appear as dots on the Plugins page cards and in
full in a plugin's detail modal. Red lines are always shown in the dialog;
amber and green open on tap.
The lights are named **Sends data · Collects data · Camera & mic · Remote
access · System changes · Can it be checked?**

You don't need an FPP box to see the result: the
[Plugin preview](https://falconchristmas.github.io/fpp-data/plugin_preview/?repo=owner/repo)
renders the card and the install dialog from your `pluginInfo.json` with the
same script FPP runs (`www/js/fpp-privacy-lights.js`, loaded from the FPP
repo), so the colours, summary, chip lines and button label below are
exactly what it shows (the headline appears on the card's tooltip, and in
the dialog only when nothing is disclosed). Paste the JSON if the file isn't pushed yet.

**What earns each colour.** Red rules are tested before amber; the first match
wins. Green needs the key itself: a light whose key is missing (or of the
wrong type) is grey "not disclosed" inside your block, never green, and a
block with none of the six keys is treated as no block at all. A `to` counts
as a hostname when it contains a dotted domain whose last label is not a
reserved LAN suffix (`.local`, `.lan`, `.home`, `.internal`, `.localdomain`)
or a file extension (`remotes.json`), or when it is a public IP address
(IPv4, or IPv6 bare or in brackets); a LAN name, a private address
(`192.168.…`, `10.…`, `fe80::…`, `fd00::…`, `::1`), an operator-entered
phrase or a broadcast is not "the internet" and is never red. A `what` names a hardware
identifier when it contains `serial number`, `cpu serial`, `mac address`,
`hardware id`, `hwid`, `hw id`, `device id` or `device uuid` as words
("serial port" and "the playlist uuid" do not count; if you really send a
serial, write "serial number").

| Light | Green | Amber | Red |
|---|---|---|---|
| Sends data | `sends` empty | any send whose `what` says "your browser" (a page asset, 14.1: "your browser's address") → "Your browser loads files from <host>", whatever `alwaysOn` says; else any `alwaysOn` send to a LAN name or private address → "Sends on its own to a device on your network"; else any `alwaysOn` send to any other phrase (an address you enter, a broadcast, a named server, the device itself) → "Sends on its own"; any other send (including `http://` to an operator-entered address) | any `what` naming a hardware identifier → "Sends identifying data"; any `alwaysOn` send to the internet (a browser-load send excepted) → "Sends to the internet on its own"; any `to` starting `http://` **to the internet** (browser-load send excepted) → "Sends unencrypted to the internet" |
| Collects data | `collects` empty | any collects | `about` visitors, passers-by, third-parties or performers with `keptDays` null (a time limit is what leaves red) |
| Camera & mic | `sensors` empty | any sensor: camera/microphone not stored → "Camera, not stored"; any other type stored → "Sensor readings kept"; any other type not stored → "Uses a sensor, not stored" | `stored` true for a camera, microphone or tracker; type face-/body-tracking |
| Remote access | `none` | `lan`, `internet-authenticated` | `internet-open`, `exposes-fpp`, `tunnel` |
| System changes | `systemChanges` empty | any change | kind `package-source` or `tunnel` → "Changes this device permanently"; `reads-core-credentials` → "Reads FPP's credentials"; `privilege` → "Grants extra privileges" |
| Open code | `closedCode` false and no `download` | any `download` kind | `closedCode` true |

**How each colour is phrased.** This is FPP's text, never yours:

| Light | Green | Amber | Red |
|---|---|---|---|
| Sends data | No sending disclosed | Sends when enabled · Sends on its own to a device on your network · Sends on its own · Your browser loads files from <host> (per rule) | Sends to the internet on its own · Sends unencrypted to the internet · Sends identifying data (per rule) |
| Collects data | No collection disclosed | Collects, with limits | Collects visitor data |
| Camera & mic | No camera or mic disclosed | Camera, not stored · Sensor readings kept · Uses a sensor, not stored (per rule) | Records people |
| Remote access | No remote access disclosed | Listens on your network · Reachable from the internet, with a login (per value; an unknown value reads Listens for connections) | Can be reached from the internet |
| System changes | No system changes disclosed | Changes this device | Changes this device permanently · Reads FPP's credentials · Grants extra privileges (per rule) |
| Open code | Author says all its software can be checked | Downloads extra software | Includes software that can't be checked |
| No disclosure (any) | — | — | "<light name>: not disclosed" (grey when only that key is missing) |

Under each light FPP composes one line from a fixed template with your
fragments inserted — for a send, `<to> · always on` or `· only when you use
that feature` (plus `, unencrypted` when `to` starts with `http://`; the
scheme itself is not shown) then `<What> — <why>.`; for a collect, `Keeps
<what> about visitors in <where>, for 30 days, with a delete control`; for a
sensor, `Camera · nothing kept` (the type in words, never the enum value);
for a system change, `Service: <what>.` (kind labels: Service ·
Network · FPP settings · Download · Package source · Tunnel · Reads FPP
credentials · Privilege); for remote access, a fixed sentence per value; for
Open code, "Includes software whose source is not available." when
`closedCode` is true and, when any `download` change exists, FPP's own
sentence *"Installs extra software from a public source; see System
changes."* -- the download itself is listed once, under System changes, not
repeated. The green lines are attributed to you: "Author says it talks only to FPP on
this device.", "Author says it keeps only your own settings.", "Author
says no camera or microphone.", "Author says no way in from outside
this device.", "Author says nothing outside its own directory.", "Author
says everything that runs is in the repository or comes from a public
package source such as apt, pip or npm."

**The headline** above the strip is chosen by rule, first match wins:

1. Open code red → **"Part of this plugin is a black box"**, with the fixed
   explainer *"Almost every FPP plugin is made entirely of code anyone can
   read. Part of this one is not, so nobody — not FPP, not you — can check
   what that part does, and the disclosure below cannot be checked for it
   either."* A closed component does not just earn its own red light; it
   undermines every other line, because the listing check cannot compare
   your block with code it cannot read.
2. Collects data or Camera & mic red → "Handles other people's data".
3. Remote access red → "Can be reached from the internet".
4. Sends data red → the Sends chip text ("Sends to the internet on its own",
   "Sends unencrypted to the internet" or "Sends identifying data").
5. System changes red → the System chip text ("Changes this device
   permanently", "Reads FPP's credentials" or "Grants extra privileges").
6. Any light grey because its key is missing → "Not everything is disclosed".
7. Any send → "Author says it talks to online services" — or "Author says it
   talks to devices on your network" when no `to` is on the internet.
8. Any other amber light → that light's chip text (the first of Collects,
   Camera, Remote, System, Open code), so a LAN listener or a camera never
   reads as "runs on this device only".
9. Otherwise → "Author says it runs on this device only".

**Why the greens are worded differently from the reds.** The block is your
own description and FPP does not verify it. A statement against your interest
(an amber or red line) is credible on its face, so the dialog states it as a
finding — "Sends identifying data", "Records people". A favourable one is only
a claim, so every green line and headline is attributed to you — "No sending
disclosed", "Author says…" — the label line above the headline reads "DISCLOSED
BY THE AUTHOR · not verified by FPP", and the card shows green as a hollow dot
rather than a filled one. Every community-plugin dialog also carries FPP's own
warning that no block changes — untrusted third-party code that will run as
root, able to read and change any setting including the privacy settings and
reach anything on the network, inherently dangerous, not tested, vetted or
guaranteed by the FPP project, install only if you trust the author — so a
row of six greens is a description of *your* plugin as you describe it, not a
badge. The listing check (14.16) is the one place your block is compared with
your code.

**The Install button** takes its text and colour from the worst finding, in
the same order as the headline. It always starts with "Install"; Cancel stays
"Cancel".

| Worst finding | Button | Class |
|---|---|---|
| No disclosure | Install, no disclosure | btn-danger |
| Open code red | Install, black box included | btn-danger |
| Collects/Camera red | Install, handles others' data | btn-danger |
| Remote red | Install, opens FPP to internet | btn-danger |
| Sends red | Install, sends data out | btn-danger |
| System red | Install, permanent changes | btn-danger |
| Any amber, any send, or a light grey for a missing key | Install anyway | btn-warning |
| All green | Install | btn-success |
| Official, all green | Install | btn-success |

FPP's existing developer-mode and resource warnings still force "Install
anyway" (btn-warning at least) when they fire and the finding-based label
would be plainer.

**Plugins with no block.** Every listed plugin must carry a `privacy` block:
the listing check's `privacy-missing` finding is a blocker for new listings
and for updates to listed plugins. Saying nothing is never better than
describing honestly: an undeclared plugin gets the red "Install, no
disclosure" button.

FPP's own install dialog (for a plugin installed outside the listing, or one
installed before it carried a block) keys its rendering to the constant
`PRIVACY_DECLARATION_REQUIRED_FROM` in `fpp-privacy-lights.js`, compared
against the player's own date:

| | Before 1 January 2027 | On or after |
|---|---|---|
| Lights | grey, "Not disclosed", hollow dots | red, "Not disclosed" |
| Headline | grey "No privacy disclosure" | red **"No privacy disclosure"** with the explainer *"Every FPP plugin has been required to describe what it does with data since 1 January 2027. This one has not."* |
| Label line | "NO DISCLOSURE · the author has not said what this plugin does with data" | same |
| Button | "Install, no disclosure", danger | same |

**Upgrades.** FPP diffs the stored block against the new one over everything
except `summary` (`other` included), and re-shows the dialog ("This update changes
the privacy disclosure of *name*") before applying an update that changes it.

#### 14.16 How the listing check treats these

The compliance CI uses three tiers.

**Blocker** (fails listing):

- `privacy-unknown-key` — a key outside the eight, or outside an entry's
  fields (a v2 key names its v3 replacement). A missing key or a value
  outside its enum fails the schema check itself.
- `privacy-missing` — no `privacy` block at all. A blocker for new listings
  and for updates to listed plugins.
- `privacy-template-text` — `summary` or `other` still carries the
  "TEMPLATE TEXT - replace me" placeholder fpp-plugin-Template ships. A
  blocker: the block was never filled in, and that text would otherwise be
  shown to every installer.
- `privacy-undeclared-*` — the code does something the block does not say:
  `privacy-undeclared-recipients` (a host literal, MQTT publish or
  core-helper fetch with no matching `sends` entry; also a host your pages
  make the browser load — `<script src>`, `<link href>`, `<img src>`,
  iframe/media sources, CSS `url()`, `fetch()` literals, CSP `*-src` hosts —
  when you whitelist it with `ManageApacheContentPolicy.sh add` or serve
  the page yourself (`remoteAccess` not `none`); worded as "loads …
  (browser-side)" so you know to declare it with `what`: "your browser's
  address", 14.1; an `<a href>` link is not a load),
  `privacy-undeclared-install` (a package source, `curl | sh` or install-time
  download with no `package-source`/`download` change),
  `privacy-undeclared-selfupdate` (`git pull` or `reset --hard` in an install
  hook with no `download` change), `privacy-undeclared-sensors`,
  `privacy-undeclared-listeners` (a listener with `remoteAccess: none` and no
  `network` or `tunnel` system change naming it),
  `privacy-undeclared-services`, `privacy-undeclared-core-config` (a write to
  FPP's own files or settings with no `core-settings` change),
  `privacy-undeclared-credentials` (a read of a core credential with no
  `reads-core-credentials` change), `privacy-undeclared-privileges` (sudoers,
  group membership, kernel module or udev rule with no `privilege` change).
- `privacy-setting-write` — any write to the eight privacy settings (14.9).
- `privacy-setting-read` (best practice) — reading one of them to decide
  whether the plugin may send: FPP's consent settings are the operator's
  answer to FPP, not to the plugin; gate your own traffic on your own
  setting, off by default.
- 14.2, 14.4, 14.5's retention limit and delete control, 14.10, 14.12, 14.13,
  and every point of 14.14.

**Best practice** (flagged, fix expected):

- `privacy-text-length` — `summary` over 200 characters, or a `what`/`why`
  over 100 (`systemChanges[].what` over 120). Never blocks.
- `privacy-csp-blocked-load` — a page loads a script, stylesheet, font,
  image, frame, media file or `fetch()` URL from a host FPP's
  Content-Security-Policy blocks (nothing in the plugin adds it with
  `ManageApacheContentPolicy.sh add <directive> <host>`, and the page is
  served by FPP, not by your own listener). It never loads, so it is not a
  `sends` entry: bundle the file with the plugin or remove the tag; if you
  do want it, whitelist it and declare it (14.1). Fires even when `sends`
  already names the host — that entry then describes traffic that does not
  happen.
- `privacy-closedcode-unverified` — `closedCode` is `false` but the install
  script or code takes a package from pip, npm, CPAN or similar, or fetches a
  binary or archive with `curl`/`wget` (`apt-get` and `dpkg` installs are not
  counted; a `.deb` fetched by URL is). The
  check cannot tell a published-source package from a closed wheel or vendor
  SDK, so it names each package page or URL for the reviewer to check; it
  is reported on every run and does not block listing. Never fires with
  `closedCode: true`.
- 14.6, 14.7, a one-line editable notice on visitor-facing pages, removing
  self-update buttons in favour of FPP's upgrade path, uninstall reverting
  every system change (including publishing empty retained MQTT messages),
  describing local activity logs (GPIO, commands, sequences) under `collects`
  with `about: "household"`, and saying in `other` what the vendor keeps and
  where its policy is.

**Optional**: retention of 30 days or less, and pseudonymising visitor
identifiers (hashing phone numbers) where the feature allows.

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
- [ ] Native (C++) plugins: HTTP routes go through `registerPluginApi()`/
      `unregisterPluginApi()` (never `drogon::app().registerHandler()`
      directly); `Makefile` includes `makefiles/common/setup.mk`; if claiming
      `FPP_PLUGIN_SUPPORTS_UNLOAD()`, `shutdown()` withdraws+deletes every
      `addCommand()`-registered command and `nm -D lib<repoName>.so | awk
      '$2=="u"'` comes back empty.
- [ ] No `sudo`, no `reboot`/`shutdown`, no direct `fppd` restart, no
      `curl … | bash`.
- [ ] Talks to FPP via helpers/HTTP API; no hand-editing of core FPP config.
- [ ] Own config in `config/plugin.<repoName>`, data in `plugindata/`; all writes
      confined to the plugin directory and declared paths.
- [ ] Whatever `fpp_install.sh` installs uses only `apt-get`/`npm`/`pip`/`cpan`
      (no `curl|bash`, no installer that isn't already on the image). `pluginInfo.json` `dependencies` is optional this year
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
- [ ] If the plugin sets up/depends on a tunneling or remote-access service
      (Dataplicity, ngrok, Cloudflare Tunnel, Tailscale, ZeroTier, etc.), that's
      stated up front in `pluginInfo.json`'s `description` field.
- [ ] `pluginInfo.json` carries a `privacy` block (all eight keys present,
      `other` filled in, `summary` written for a neighbour) that matches what
      the code does - built with the
      [Privacy disclosure builder](https://falconchristmas.github.io/fpp-data/plugin_privacy_builder/)
      and checked in the
      [Plugin preview](https://falconchristmas.github.io/fpp-data/plugin_preview/).
- [ ] Every off-box host the plugin talks to is named in the `description`,
      with what is sent and why.
- [ ] Nothing transmits by default except the one service the plugin exists
      for; every optional recipient is off until the user turns it on.
- [ ] Credentials sit under password-shaped keys (`Password`/`Token`/`Key`/
      `Secret`, `type: password`), render as password inputs, and never appear
      in the log, a URL, or a command line.
- [ ] Personal data about visitors has a retention limit with automatic purge
      and a delete control, and the description says it is collected.
- [ ] Cameras, microphones and radio say what leaves the device and what is kept.
- [ ] Inbound webhooks verify a signature/token before reading the body.
- [ ] `fpp_install.sh` changes nothing about network exposure (no services
      enabled, ports opened, shares mounted, tunnels set up).
- [ ] No package sources (apt/pip/npm/other) without a `systemChanges` entry, a shipped
      signing key, pinning to named packages, and removal on uninstall; no
      gem/cargo or other package manager not already on the image unless
      described there (default apt/PyPI/npm/CPAN packages need no entry).
- [ ] Nothing sensitive in `config/` - credentials, visitor data and
      device-bound identity live in `plugindata/`, mode `0600`.
- [ ] No reads or writes of FPP's privacy settings (`statsPublish`,
      `statsPublishUrl`, `ShareCrashData`, `FetchVendorLogos`,
      `SendVendorSerial`, `SendVendorLogos`, `privacyConsent`,
      `LegalJurisdiction`).
- [ ] Native/in-process plugins: every listener and publisher is off until the
      plugin's own enable setting is on; traffic via core helpers is in `sends`.
