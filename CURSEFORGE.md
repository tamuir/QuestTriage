# Publishing Quest Triage on CurseForge

Everything for the CurseForge project page, in the order the form asks for it, written so players searching for a
leveling addon or quest helper find it. Search on CurseForge and Google weighs, in order: the **name**, the
**summary**, the **first lines of the description**, the **categories**, then the rest of the description and image
captions. Each field below puts the words players actually search for ("leveling", "quest helper", "guide",
"WoW Forever", "Questie", "arrow", "gear upgrade") where they count, without keyword stuffing.

## 1. Project fields

| Field | Value | Why |
| --- | --- | --- |
| Name | **Quest Triage - Leveling Guide & Quest Helper** | The brand plus the two phrases people search for. 44 characters, so it isn't cut off in search results. |
| Project URL (slug) | `quest-triage` | Short and readable. It can't easily be changed later. |
| Summary | **Leveling guide and quest helper for WoW Forever: your best next quest with a live arrow, nearby quests, gear upgrades and what to skip.** | Keywords first; 136 characters, so the whole line shows in search snippets. |
| Main category | Quests & Leveling | Where leveling players browse. |
| Extra categories | Map & Minimap · Bags & Inventory | Map pins and arrow; auto-sell grays and gear upgrades. Only add categories that honestly fit. |
| Game version | WoW Forever (the `.toc` says `## Interface: 16001`) | Only claim what's tested. |
| License | GNU General Public License version 3 (GPLv3) | Matches `LICENSE.md`. |
| Logo | `media/logo-400.png` (400 x 400) | Bright gold on dark reads well at thumbnail size. |
| Source | https://github.com/tamuir/QuestTriage | A visible source link builds trust. |
| Issues | https://github.com/tamuir/QuestTriage/issues | Bug reports go to GitHub. |
| Relations | Questie: **Optional dependency** | Shows on Questie's "dependents" list too, which brings in Questie users. |

## 2. Description (paste into the description editor, Markdown mode)

The first two sentences are what Google and CurseForge show as the preview, so they carry the main keywords.
Headings use the phrases players search for. Keep the FAQ: question-style headings match how people type searches.

The description is in its own file, ready to copy: **[CURSEFORGE-DESCRIPTION.md](CURSEFORGE-DESCRIPTION.md)**. Open it,
select all, and paste it into CurseForge's description editor in Markdown mode.

It's made from `README.md`, so the two always match (images load from GitHub). After changing the README, run
`sh tools/curseforge-description.sh --update` to refresh it, then paste it again.

### Image titles and descriptions

CurseForge lets you give every gallery image a title and description; both are indexed. Use these:

| File | Title | Description |
| --- | --- | --- |
| `next-step.jpg` | Leveling guide: your next quest with a live arrow | The Next card shows where to go, how far and how much XP it's worth. |
| `batch-hub.jpg` | Quest helper: clear a hub before you leave | Batch mode walks you through every hand-in and pick-up nearby first. |
| `pick-up.png` | Quest helper: never miss a quest nearby | Nearby quest givers worth your time, nearest first, with the next one on the card. |
| `pin-tooltip.jpg` | Map pins that explain themselves | Hover the pin for the step, what you need first, coordinates and distance, and where to go after. |
| `gear.png` | Gear upgrades for your class | Upgrades judged on real stats, one click to equip. |
| `settings.png` | Settings: batch or one at a time | Leveling style, auto-sell greys, size and combat fade. |

Set `next-step.jpg` as the **featured image**: it explains the addon in one look.

### After launch

- Post a short changelog with every release (the release workflow uploads `CHANGELOG.md` automatically); regular updates rank higher.
- Reply to comments; activity counts.
- Link the CurseForge page from the GitHub README once it exists.

## 3. Gallery images

Upload these from `docs/images/`, with the titles and descriptions from the table in section 2. Make `next-step.jpg`
the featured image.

`next-step.jpg` · `batch-hub.jpg` · `pick-up.png` · `pin-tooltip.jpg` · `gear.png` · `settings.png`

## 4. Automatic uploads (one-time setup)

1. Create the project on CurseForge with the fields above and note its **Project ID** (shown on the project page).
2. In `QuestTriage.toc`, replace the commented line with `## X-Curse-Project-ID: <your id>`.
3. On CurseForge, create an **API token** (your account settings, API tokens).
4. On GitHub, repo Settings > Secrets and variables > Actions, add a secret named `CF_API_KEY` with that token.
5. Commit and push step 2. From then on, **releasing is one step**: add a dated section to the top of `CHANGELOG.md`,
   such as `## [0.5.1] - 2026-11-10`, and push to main. GitHub runs the tests, tags `v0.5.1`, builds the zip (only what
   the game loads) and uploads it to GitHub Releases and CurseForge for WoW: Forever. The version in the `.toc` is
   stamped automatically.

The first release (0.5.0) is already in the changelog, so it goes out as soon as steps 1 to 4 are done: after pushing
the project ID, open GitHub > Actions > Release > **Run workflow**.

If CurseForge doesn't list WoW: Forever (game version 1.60.1), the release stops before publishing anything and says so.

## 5. Before you publish

- [ ] Play a session on the release build; run `/qt debug` once to check pins.
- [ ] Gallery images uploaded (section 3).
- [ ] Project ID in the `.toc`, `CF_API_KEY` secret set.
- [ ] Questie listed as an optional dependency on the project page.
