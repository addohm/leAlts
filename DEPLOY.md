# Deploying leAlts

leAlts is a World of Warcraft addon. It runs inside the game client (WoW: Forever,
Interface 16001), and there's no server.

## First-time setup

1. Find the client's addon folder. For Forever it's `<WoW install>/_forever_/Interface/AddOns`.
2. Copy the `leAlts` folder into it. Don't copy the repository root.
3. Start the game, or type `/reload` if you're already in. Check that leAlts is enabled under
   AddOns on the character-select screen.

## Shipping a change

1. Run the tests: `python3 tests/run_tests.py`.
2. Bump `## Version` in `leAlts/leAlts.toc`. It's the only version source.
3. Move the CHANGELOG's Unreleased entries under the new version.
4. Commit, then build the zip with `python3 tools/make_release.py` (it writes
   `release/leAlts-<version>.zip` from the committed files) and commit that too.
5. Tag the release (`git tag v1.1.2`) and push the tag (`git push origin v1.1.2`).
6. To try it locally, run `tools\install_forever.cmd` (see below) and `/reload`.

## Installing your own build on Windows

`tools\install_forever.cmd` pulls the repo from GitHub (`git pull --ff-only`), mirrors
`leAlts/` into `<WOW>\Interface\AddOns\leAlts`, and writes the commit into the
installed `Build.lua`. It also packs `leAlts-<version>.zip` on your desktop (the version
from the `.toc`), ready to upload to CurseForge or Wago: `git archive` of the committed
`leAlts/` folder, without the build stamp. `WOW` at the top of the script is the client folder, by default
`C:\Program Files (x86)\World of Warcraft\_forever_` (the live game). Change it to
`_classic_beta_` for the beta client.

- On the first run it creates the addon folder (and `Interface\AddOns` if the client has none yet).
  If `WOW` itself doesn't exist it stops instead, since the path is probably wrong.
- `/lealts help` then shows `v<version> build <commit>`; "-dirty" means the copy included uncommitted changes.
- The pull can update the script itself, so a copy in `%TEMP%` does the pull and then hands over
  to the script just pulled. A change to the script applies on the same run.
- WoW reads the addon's file list only when the game starts. When files were added, renamed or
  removed, the script says so: fully restart the game instead of using `/reload`.
- It only gets what's pushed, so push first. If creating or copying fails, the WoW folder may need
  the script to run as administrator.

## Releasing on CurseForge and Wago

`.pkgmeta` configures the BigWigs packager, which CurseForge and Wago both use. It packages only
the `leAlts/` folder and fills in translations from CurseForge's localization tool.

First time only:

1. Create the projects on CurseForge and Wago. `LISTING.md` has the page text, categories and
   screenshot list; `art/` has the icon (`lealts-icon-400.png` for the avatar) and banner.
2. Add their IDs to the `.toc` as `## X-Curse-Project-ID: <id>` and `## X-Wago-ID: <id>`.
3. Set up the packager: either a GitHub Action (`BigWigsMods/packager`) with `CF_API_KEY` and
   `WAGO_API_TOKEN` as repository secrets, or the sites' own webhooks. Keep the keys out of the repo.

Then each pushed tag builds and uploads a release.

## Translations

Translators add strings on the CurseForge project's localization page. The English text is the key
(see `leAlts/Locales/enUS.lua`). The packager writes the translations into the `Locales/`
files at build time, so the copies in the repository stay empty.

## Rolling back

Copy an older version's `leAlts` folder from git history (`git checkout <tag> -- leAlts`;
up to 1.1.2 it was the `NothingWasted` folder) over the installed copy.

## Configuration

There are no secrets or environment settings in the addon. In-game settings are saved in
`WTF/Account/<account>/SavedVariables/leAlts.lua`. Up to 1.1.2 the addon was called Nothing Wasted
and the file was `NothingWasted.lua`; the data inside is the same (`NothingWastedDB`), so copying
that file to `leAlts.lua` carries everything over. `tools\install_forever.cmd` does that once, and
removes the old `NothingWasted` folder from AddOns so the two don't both load.

## Troubleshooting

- **Nothing happens on `/lealts`:** the addon isn't loaded. Check the AddOns list. If the game says the
  addon is out of date, the client's Interface number differs from 16001: update the `.toc` or enable
  "Load out of date AddOns". Try `/nw` in case another addon took `/lealts`.
- **Lua errors:** turn on `/console scriptErrors 1` to see them, then report them along with the
  addon version.
- **Well Rested isn't picked up:** run `/lealts perks` and check the perk's spell ID against `Data.lua`.
