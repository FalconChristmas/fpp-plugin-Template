# fpp-plugin-Template
Template plugin for FPP Plugin developers

Ships with `LICENSE` defaulted to GPLv2 (the convention most FPP plugins use).
Replace it with a license of your own choosing if you'd prefer — just keep
*some* `LICENSE`/`COPYING` file in the repo root for redistribution clarity.

## Building a plugin

- [`PLUGIN_GUIDELINES.md`](PLUGIN_GUIDELINES.md) - rules and conventions for a
  well-behaved plugin, including §14 on privacy and personal data (what must
  be disclosed, and how FPP colours the install dialog from your `privacy`
  block). Read this (or point your AI assistant at it) before you
  start, and again whenever you add a feature.
- [`PLUGININFO_FORMAT.md`](PLUGININFO_FORMAT.md) - the `pluginInfo.json`
  metadata format reference, including the `privacy` block.

Two browser tools on fpp-data's site help with `pluginInfo.json` (nothing
leaves your browser except reads of your own public repo):

- [**Privacy disclosure builder**](https://falconchristmas.github.io/fpp-data/plugin_privacy_builder/) -
  writes the `privacy` block for you, one key at a time, with the same rules
  the listing check applies. Pre-fills from your repo
  (`?repo=owner/repo`) or from pasted JSON, and edits a block you already have.
- [**Plugin preview**](https://falconchristmas.github.io/fpp-data/plugin_preview/) -
  renders your `pluginInfo.json` as FPP's Plugin Manager will show it (card,
  six privacy dots, install dialog) using FPP's own renderer. Check it before
  you submit, and again whenever you change the block.

**These two files document how to build a plugin in general - they aren't part
of your plugin.** Once you've forked this template, delete
`PLUGIN_GUIDELINES.md` and `PLUGININFO_FORMAT.md` from your own repo; they
should only ever live here, in fpp-plugin-Template.

## Getting your plugin listed

Once it's built, submit it via
[fpp-data](https://github.com/FalconChristmas/fpp-data) - see that repo's
`README.md` for the submission form and `PLUGINS.md` for the rules.

