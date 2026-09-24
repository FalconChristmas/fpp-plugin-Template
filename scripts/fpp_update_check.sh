#!/bin/bash

# fpp-plugin-Template update check script
#
# DELETE THIS FILE if your plugin's updates are git commits. FPP already
# compares the installed clone with origin/<branch> on every update check;
# this script only adds something for a plugin whose real updates live
# outside git - a prebuilt binary or package attached to a GitHub Release,
# say - so the repo itself rarely changes. See PLUGININFO_FORMAT.md >
# Updates that aren't git commits.
#
# The contract with FPP:
#  - CHECK ONLY. Never download and install anything, replace code or
#    binaries, or otherwise change the plugin here. This runs unattended and
#    repeatedly (the background check runs it at nice 19, possibly during a
#    show) and outside the privacy review an Update goes through. Changing
#    the plugin is scripts/fpp_upgrade.sh's job, which runs only when the
#    user presses Update. Caching the new release's notes text for
#    fpp_releasenotes.sh is fine; replacing code is not.
#  - Runs after FPP fetches the plugin, whenever it checks for updates (the
#    background check, Check for Updates / Update All, the Check for Update
#    button, and after an install or update).
#  - Runs as the web user (fpp), NOT root, in the plugin's own directory, with
#    stdin closed and stderr discarded. The environment is minimal: FPPDIR,
#    SRCDIR, PATH, HOME, USER, LANG and LC_ALL, nothing else.
#  - The LAST non-empty line of stdout is the answer: "1" = an update is
#    available, "0" = none. Lines before it are ignored, so a short
#    explanation first is fine.
#  - Exit 0 = "the check ran". Any other exit = "could not check": FPP
#    records the reason (with the exit code) and keeps git's answer; with no
#    git answer either, the plugin shows as not checked, never as up to date.
#    So when you can't tell, exit non-zero - don't guess 0, and never print 1.
#  - After two minutes FPP kills the script and everything it started and
#    counts it as "could not check". That only catches a hung script; a
#    normal check takes a second or two, since someone may be waiting on the
#    button. Put a timeout on every network call.
#  - A "1" here means an update even when git sees none; a "0" never hides
#    new commits git has seen.
#  - Talking to GitHub needs no `sends` entry in pluginInfo.json's privacy
#    block. Any other host does.
#
# The pattern below: fpp_install.sh / fpp_upgrade.sh download the latest
# GitHub Release asset and write its tag to .installed-version in the plugin
# directory (world-readable - this script is not root; keep it out of git
# with .gitignore). This script compares that tag with the tag of the latest
# release of the repo named in pluginInfo.json's srcURL.

set -u -o pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The installed version, as fpp_install.sh left it.
INSTALLED="$(head -n 1 "${PLUGIN_DIR}/.installed-version" 2>/dev/null | tr -d '[:space:]')" || INSTALLED=""
if [ -z "${INSTALLED}" ]; then
    echo "No .installed-version file; cannot tell what is installed."
    exit 1
fi

# owner/repo from srcURL ("https://github.com/owner/repo.git" -> "owner/repo").
REPO="$(grep -o '"srcURL"[[:space:]]*:[[:space:]]*"[^"]*"' "${PLUGIN_DIR}/pluginInfo.json" 2>/dev/null \
    | sed -nE 's#.*github\.com[/:]([^/"]+/[^/"]+)"$#\1#p' | sed 's#\.git$##' | head -n 1)" || REPO=""
case "${REPO}" in
    */*) ;;
    *)
        echo "srcURL in pluginInfo.json is not a github.com repo."
        exit 1
        ;;
esac

# The latest release's tag. releases/latest skips drafts and pre-releases; for
# a rolling pre-release use releases/tags/<tag> instead. Unauthenticated
# GitHub API calls are rate-limited (60 an hour per address); a refusal is a
# curl failure, so it lands in "could not check" like any network error.
LATEST="$(curl -fsS --max-time 20 -H 'Accept: application/vnd.github+json' \
        "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null \
    | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -n 1 | sed -E 's/.*"([^"]*)"$/\1/')" || LATEST=""
if [ -z "${LATEST}" ]; then
    echo "Could not read the latest release of ${REPO}."
    exit 1
fi

echo "Installed ${INSTALLED}, latest release ${LATEST}."
if [ "${INSTALLED}" = "${LATEST}" ]; then
    echo "0"
else
    echo "1"
fi
exit 0
