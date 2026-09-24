# Reviewing your own plugin before you submit it

`PLUGIN_GUIDELINES.md` tells you the rules. This document is about finding the
things the rules don't name — the bugs that only show up when your plugin is
installed on someone else's FPP, next to other plugins, by a user who will
never read your code. It's the same process a maintainer uses when reviewing a
submission, minus the parts that only make sense from the maintainer's side.

None of this is required. The automated check runs on every listing issue and
a maintainer reads the submission (`PLUGINS.md`); that's the process. But a
plugin that's been through this once tends to pass on the first try and — more
to the point — tends not to come back as a bug report from someone's show on
the 20th of December.

> This describes FPP 10 on the standard Raspberry Pi OS image, as of writing.
> FPP, Debian, and the libraries underneath all change; check behaviour on
> your own box before relying on anything here. This is maintainer
> experience, not a guarantee, and you follow it at your own risk — this
> document is provided under the repository's LICENSE, which has the
> no-warranty language. It's documentation, not part of your plugin
> — delete this file from your fork.

> **Working with an AI coding assistant?** You can point it at this file and
> ask it to review your plugin against these checks — that's what this
> document is written for. Two cautions: everything under **§C** (installing
> and diffing on real hardware) and **§F** (block devices) can change or break
> the box, so have the assistant propose those commands for you to run and
> confirm, not run them autonomously against a box you care about. And this
> file is deliberately the *author-facing* half of a maintainer review — an
> assistant can't infer the catalog's automated checks from it, so passing
> everything here is not the same as passing submission.

## Most plugins are simple. Start here.

If your plugin is a settings page and/or a script or two — PHP and bash, no
compiled code, no long-running daemon, doesn't touch disks or hardware — these
four checks are the whole job. The rest of this document is for daemons,
native (C++) plugins, and plugins that touch block devices; skip it unless
that's you.

1. **Install it through the Plugin Manager on your own Pi, use it for ten
   minutes, then uninstall it.** Not `git clone` — the Plugin Manager, the way
   a user will. Confirm your log shows up at
   `media/logs/plugin-<repoName>.log` (File Manager → Logs), and that
   `media/logs/apache2-error.log` didn't start filling with your plugin's
   name (§A explains the usual cause). If the plugin didn't install, or its
   menu entry never appeared, check `media/logs/fpp_plugin_manager.log` (same
   Logs tab) — that's where your install script's own errors land.
2. **Install it a second time.** `fpp_install.sh` re-runs on every "Reinstall
   All Plugins" and every update, so it has to be safe to run twice — no
   duplicate config lines, no failing because something already exists
   (guidelines §2.3).
3. **Trace every setting to where it's used.** For each value your settings
   page saves, follow it to the shell command, file path, or URL it ends up
   in. FPP has no login by default, so "the form validates it" means nothing
   to someone sending the request directly — the check has to be where the
   value is *used*, not where it's entered. (More in §B.)
4. **Don't name a file `api.php` unless it's a real API registrar** (§A) —
   it's a reserved filename FPP treats specially.

That's it for a simple plugin. If you have a daemon, C++, or block-device
code, read on.

---

## A. Things FPP does that your plugin has to know about

These are mechanics that surprise authors because they're only visible in
FPP's own source.

**`api.php` is a reserved filename.** FPP loads every installed plugin's
`<repoName>/api.php` on *every* `/api/*` request — from any page, by any user
— expecting it to declare a `getEndpoints<repoName>()` function (dashes
stripped from the name) that returns route definitions, plus the callback
functions those routes name:

```php
<?php
function getEndpointsmyplugin() {          // <repoName> with dashes removed
    return array(
        array('method' => 'GET',  'endpoint' => 'status', 'callback' => 'myplugin_status'),
        array('method' => 'POST', 'endpoint' => 'reset',  'callback' => 'myplugin_reset'),
    );
}
function myplugin_status() { return json(array('ok' => true)); }
function myplugin_reset()  { /* ... */ return json(array('ok' => true)); }
```

Those routes then answer at `/api/plugin/<repoName>/status`. Prefix your
function names with the plugin name — and your classes and constants too:
they all land in one shared global namespace with FPP core and every other
plugin. Don't use limonade's reserved names for a top-level function
(`before`, `after`, `initialize`, `configure`, `not_found`, `server_error`,
and similar) — those hook into every API request, not just yours. Anything
*else* in that file
— an `echo`, a `header()`, a `switch` on `$_GET`, a `require` that doesn't
resolve when the file is loaded from FPP's `www/api/` directory — runs, or
fails, on every API call FPP serves, for every user. If a plugin's `api.php`
collides with a function FPP already defines, or fails to parse, FPP skips
that plugin's API and writes one line to `apache2-error.log` (no error
reaches the UI) — which is why the §1 log check catches this. If you just
want a plain AJAX endpoint for your own page, call the file something else and
reach it via `plugin.php?plugin=<repoName>&page=ajax.php&nopage=1`.

**Declare the hardware/OS your plugin needs with `platforms`.** If your
plugin only works on certain hardware or an OS with `apt` (GPIO, something
under `/boot/firmware`, a Pi-only tool), list the platforms it supports on its
`versions[]` entry. FPP offers a version entry only when the box's `Platform`
is one of the listed strings (matched exactly — the valid strings are in
`PLUGININFO_FORMAT.md`; a typo like `"Pi"` or `"RPi"` matches nothing, so the
plugin is silently unavailable everywhere, while a bare string where an array
is expected is ignored entirely, so the restriction silently does nothing and
the plugin is offered everywhere), and an entry with no `platforms` is offered
on *every* box — including ones where it can't run, where it then installs and
fails. A plugin
that declares `apt` packages is also refused up front on a platform without
`apt`, rather than half-installed.

**`fpp_uninstall.sh` runs, then the directory is deleted no matter what.**
`scripts/uninstall_plugin` ignores your script's exit code and `rm -rf`s the
plugin directory afterwards. Whatever cleanup you need has to be in that
script and correct on its own; there's no second chance and no error reaches
the user.

**A plugin-only update runs `scripts/fpp_upgrade.sh` *instead of*
`fpp_install.sh`, if you ship one.** (It has to be at `scripts/fpp_upgrade.sh`
— a repo-root copy is ignored.) Anything `fpp_install.sh` does that an update
also needs — build a native `.so`, create a directory — must be in both, or
`fpp_upgrade.sh` must call `fpp_install.sh`. If you have no `fpp_upgrade.sh`,
updates fall back to `fpp_install.sh` and you're already covered.
If those updates aren't git commits (a prebuilt release binary, say), FPP
won't see them without a `scripts/fpp_update_check.sh` to report them — see
`PLUGININFO_FORMAT.md` › *Updates that aren't git commits*.

**You usually don't need to set `restartFlag`.** On FPP 10 the install asks
fppd to load your plugin, and the uninstall asks it to unload, so neither
normally needs a restart — which on a running show means not interrupting it.
Don't set the flag unconditionally; that forces the restart FPP just avoided.
Guidelines §3.6 has the cases that genuinely still need it — chiefly a plugin
that ships `commands/descriptions.json` but *no* `callbacks` script (fppd
picks up those commands only at its own startup), and anything that only takes
effect during fppd's startup. Set it with your language's helper (§3.6), never
by restarting fppd yourself.

**Packages you declare in `dependencies.packages` are reference-counted.**
Declare apt packages there and let FPP install them (guidelines §6). FPP
records who asked for each one, and on uninstall only apt-removes a package
when nobody else still claims it *and* apt confirms removing it wouldn't drag
anything else off the box; a package that was already on the image is marked
as the system's and stays. A package you instead `apt-get install` yourself
from `fpp_install.sh` is untracked — it also isn't reinstalled after an FPP OS
upgrade, so prefer the declared list. One thing to watch either way:
`apt-get install <pkg>` on a package that's *already installed* upgrades it to
the newest version — and if that's a base-system package (things like
`e2fsprogs` or `dosfstools`, anything with an initramfs hook — a script that
runs when certain packages change and can rebuild the Pi's boot image), the
upgrade can trigger a boot-image rebuild you didn't intend. Don't run
`apt-get update` in an install script, and if you must install something by
hand, install it only when it's missing:

```bash
command -v rsync >/dev/null || apt-get install -y rsync
```

(Prefer declaring packages in `dependencies.packages` over an ad-hoc
`apt-get install` in the script — use the script form only when you're
supporting pre-FPP-10 boxes too, or for a package you deliberately don't want
removed on uninstall.)

## B. Read your plugin four times, as four different people

Skimming once and mentally tagging things isn't the same as re-reading with a
specific question in mind. Each pass takes ten to twenty minutes and finds
different bugs.

**As someone who cares about security.** Where does input you don't control
enter — an HTTP parameter, a settings value read back from disk, an MQTT/OSC
message, a webhook body, a filename on a USB stick — and what does it reach?
Follow each one all the way to the shell command, file path, outbound URL,
SQL string, or line in a config/`.ini`/`.conf` file, systemd unit, or crontab
that another program later reads — a newline in a value can add a directive
to a file like that, and it may be run as root. A value that passes through
two or three intermediate variables on the way is still the same untrusted
value. FPP has no login by default, so a value can arrive straight from the
LAN — validate it where it's *used*. The same "no login" means a page in the
operator's browser can be made to act on FPP by any site they visit while
it's open, so make state-changing actions a POST (never do real work on a
GET), and don't rely on a request having come from FPP's own UI. And if you
expose an inbound webhook, verify the caller (a shared secret, a signature)
before you act on the body — otherwise anyone on the network can trigger it.

Remember what an injection actually costs here: your install and
uninstall scripts, your lifecycle hooks, and your fppd commands all run as
**root**, and your page's PHP runs as the `fpp` user, which can `sudo` without
a password — either way, a command injection is root on the box. Never log a
secret (API key, token, password), echo one back in a response, or commit one
to the repo; and note that anything a plugin writes under `media/config` is
readable over FPP's unauthenticated API, so credentials belong in
`plugindata/` (guidelines §14.11), not `config/`, regardless of a
`type="password"` field masking them in the form.

**As an FPP core developer.** Could this degrade FPP itself, not just your
feature? Slow work in `preStart.sh`/`postStart.sh` delays every show start. A
polling loop with no sleep, a retry with no cap, or an outbound HTTP call with
no timeout can stall a page render or fppd. A daemon started in `postStart`
and not stopped in `preStop`/`postStop` is still running after fppd restarts —
and if it opens its own port, bind it to `127.0.0.1` (FPP core does), or it
sidesteps the UI password entirely when a user sets one. Do you write anywhere
outside your own directory, your one log, your `config/plugin.<repoName>`
settings, and `plugindata/`? Do you declare a PHP function, class, or constant
with a generic name (`getStatus`, `save`, `Config`) another plugin might also
declare? Prefix every global name with your plugin's, so two plugins can be
installed at once.

**As the person using it from a phone in the yard.** Toggle FPP's dark theme
and look at every page. Shrink the browser to phone width. Does it use FPP's
`PrintSetting*` helpers and Bootstrap classes, or its own CSS and colours
(guidelines §8)? Does a failed action tell the user what went wrong, or fail
silently? Is the terminology FPP's?

**As a stranger reading it fresh.** Read your own code as someone who's never
seen it and doesn't assume the best. Is there a "temporary" debug endpoint, a
hardcoded credential, a commented-out block that would do something dangerous
if uncommented? Does the plugin do anything not described in its README and
`pluginInfo.json` `description` — a version check that phones home, a bundled
binary nobody can read, a payment link for you rather than for the show owner
(guidelines §10–§12)? If your honest answer to "why is this here?" is "I
forgot to take it out," take it out.

## C. Testing an install for real, on a box you can re-image

The ten-minute install in §1 is enough for a simple plugin. If yours installs
packages, builds native code, or runs anything unusual at install time, test
the install itself on hardware you can afford to lose.

> This changes the box, and not every change reverses on uninstall — a
> boot-image rebuild or a removed package doesn't come back. Use a spare Pi or
> a throwaway SD card, on the FPP version you're targeting, and plan to
> re-image it afterwards. **Not the card your show runs from.** If you only
> have the one Pi, install through the Plugin Manager UI, use the plugin, and
> read the logs — skip the diffing below rather than risk your show box.

Snapshot what an install can change without telling you:

```bash
dpkg -l > /tmp/dpkg-before.txt
ls -la --time-style=full-iso /boot/firmware/ > /tmp/boot-before.txt
tail -1 /var/log/apt/history.log                 # note the last Start-Date
wc -l /home/fpp/media/logs/apache2-error.log
```

Install through the Plugin Manager UI (Content Setup → Plugin Manager). Use
the plugin for real — every button, every settings save, whatever it does when
fppd starts a playlist. Then diff:

```bash
dpkg -l | diff /tmp/dpkg-before.txt -                       # packages added/upgraded?
ls -la --time-style=full-iso /boot/firmware/ | diff /tmp/boot-before.txt -
awk '/^Start-Date/,/^End-Date/' /var/log/apt/history.log | tail -40   # apt's own record
grep -c '<repoName>' /home/fpp/media/logs/apache2-error.log
```

For each diff, ask whether you *meant* it. Packages upgraded that you didn't
declare (see §A on `apt-get install`). A changed `/boot/firmware` (a boot-image
rebuild — almost never something a plugin should cause). New
`apache2-error.log` lines naming your plugin (usually the `api.php` issue in
§A — a line per request is a line per second on the status page, forever, on
every box you're installed on). Then uninstall through the UI and confirm the
box is back to how you found it — packages, services, mounts, cron entries,
files under `/etc` — apart from the user's own data your plugin produced on
purpose.

## D. Two shell patterns that look right and aren't

**A validator called in `$(...)` can't stop the script.**

```bash
check_arg() { [ -n "$1" ] || { echo "missing arg" >&2; exit 1; }; echo "$1"; }
ARG=$(check_arg "$1")     # the exit 1 exits the subshell; the script keeps going with ARG=""
do_something "$ARG"       # runs, with an empty argument
```

Test the substitution instead — `ARG=$(check_arg "$1") || exit 1` — or call
the validator directly and let it `exit` in the script's own shell. (Under
`set -e` the assignment *does* abort, which is what makes this easy to get
wrong: it works until someone runs it without `set -e`.)

**A bounded wait is still a bounded wait, whatever it's spelled.** Any wait in
`preStop.sh`/`postStop.sh` delays fppd's stop for its full worst case. The
question is never whether the line contains the word `sleep`; it's what the
worst case is and whether the show waits for it. State the worst case for
every wait in a lifecycle hook, and exit early the moment the thing you're
waiting for happens.

## E. Native (C++) plugins

Skip this section unless you ship compiled code.

- **The shared-library filename is matched by string.** FPP opens
  `lib<repoName>.so` by default; if you build a different name you must
  declare it as `c++:<filename>` in your callbacks `--list` output, or the
  plugin silently never loads.
- **Register HTTP routes through `FPPPlugins::registerPluginApi()` /
  `unregisterPluginApi()`**, never `drogon::app().registerHandler()` directly.
  FPP deletes your plugin object on unload but Drogon keeps a directly-
  registered route, so the next request into it calls freed memory. (The
  automated check now flags a direct `registerHandler`.)
- **If you claim `FPP_PLUGIN_SUPPORTS_UNLOAD()`:** your `Makefile` must
  `include $(SRCDIR)/makefiles/common/setup.mk` (that's where the
  `-fno-gnu-unique` flag lives — without it the `.so` reports a clean unload
  but never actually frees its memory; `nm -D lib<repoName>.so | awk
  '$2=="u"'` must print nothing), and every `CommandManager::addCommand()`
  needs a matching `removeCommand()`+`delete` in `shutdown()`.
- **A plugin that provides a channel output can't be hot-unloaded** while that
  output is in use — FPP refuses the unload and it can only be removed by
  restarting. If that's your plugin, it genuinely needs a restart, and the
  "usually no `restartFlag`" note in §A doesn't apply to it.
- **Verify the load/unload cycle on the disposable box from §C** (never on a
  box running a show):

  ```bash
  curl -s -X POST http://<box>/api/fppd/plugin/<repoName>/unload
  curl -s http://<box>/api/plugin-apis/<the path you registered>   # 410 Gone once unloaded
  curl -s -X POST http://<box>/api/fppd/plugin/<repoName>/load
  curl -s http://<box>/api/plugin-apis/<the path you registered>   # 200 again
  grep -i '<repoName>' /home/fpp/media/logs/fppd.log | tail
  # ^ a "left N command(s) registered at unload" warning means shutdown()
  #   didn't withdraw its own commands
  ```

  (The route path is whatever string you passed to `registerPluginApi()` —
  there's no `<repoName>` segment. The 410 only applies to routes registered
  that way, not to a raw drogon handler.)

## F. Plugins that touch block devices

Skip this unless your plugin mounts, formats, or checks disks. Honestly, most
shouldn't: running `fsck`, mounting or unmounting devices, or writing under
`/boot` is the kind of thing that can brick a user's card. If you think you
need it, raise it in your listing issue first.

If you do: FPP's media directory may not be on the SD card — a user can put
`/home/fpp/media` on a USB drive (Settings → Storage). "Not the root device"
is not a sufficient guard. Resolve FPP's actual storage device and exclude its
whole disk and every partition on it, mounted or not:

```bash
findmnt -no SOURCE -T /home/fpp/media      # e.g. /dev/sda1 -> exclude /dev/sda entirely
```

Don't rely on a tool refusing a mounted filesystem, either: `e2fsck` does, but
`fsck.vfat -y` will happily run on a mounted vfat partition.

Don't kernel-mount a network share (`mount -t cifs`/`nfs`, an `/etc/fstab`
line, a systemd `.mount`) — especially anywhere under `media/`. It's a change
to the host's network exposure the installer isn't allowed to make
(guidelines §4.4), and a hard mount to a server that later goes away wedges
every process that walks the path — yours, plus FPP's file manager, backup,
and crash bundler — in an uninterruptible state. Use a userspace client
(`smbclient`, `rclone`, `curl`) so a dead server fails only your own request.

## G. Does the documentation describe the plugin that exists?

Read your README and `pluginInfo.json` `description` last, after everything
above, and check each claim against the code as it is today:

- A feature the README leads with — is it reachable from the UI, or only from
  a code path the UI never takes?
- "FPP restarts for you after install" — check what actually happens (§A).
- "Never writes to X" — trace every write.
- A `privacy` block entry for something the plugin no longer does, or a
  missing one for something it now does: a `systemChanges` entry for a
  service, mount, or core-settings write; a `sends` entry for *every* host it
  contacts — including the ones the operator types in (a stream URL, a NAS, an
  MQTT broker), which are the most commonly forgotten.
- Your own changelog or testing notes that say a path "isn't tested yet" —
  either test it or don't ship the feature that depends on it.

If your plugin has a test suite, run it. If it doesn't, the ten minutes of
real use in §1 is your test suite; make them count.

## What this doesn't replace

The automated check still runs on your listing issue and a maintainer still
reads the submission. If a finding looks wrong to you, comment `/submit` on the
issue to ask a maintainer to look; after pushing a fix, comment `/recheck` to
re-run the check. If you'd like a second pair of eyes on a plugin beyond that,
ask in the FPP Community group — it's informal and not something the project
can promise, and it's not a security sign-off. Responsibility for what your
plugin does on someone's box stays with you.
