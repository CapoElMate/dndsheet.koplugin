# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [Semantic Versioning](https://semver.org/).

## [0.9.0] - Unreleased (first public beta)

### Added
- Public packaging: `dndsheet-<version>.zip` with a `SHA256SUMS` file, `LICENSE` (AGPL-3.0-or-later), `NOTICE.md`
  with the SRD 5.2.1 attribution, English and Spanish READMEs, and the plugin version shown in *About*.

### Changed
- The product name is now **dndsheet** ("character sheet compatible with 5e, SRD 5.2.1"). The 5e trademarks are no longer part of the name.

### Includes everything from the development history below

#### Rules compendium (SRD 5.2.1, English)
- Data for 12 classes, 12 subclasses, 9 species, 17 feats, 339 spells and 38 weapons, with the SRD attribution and a coverage report (`COBERTURA.md`).
- In the app: browse and search the compendium, read a rule, **Add to my sheet** (features, spells and weapons as ready attacks), your own entries as JSON files.
- File format `schema` 3: `rasgos_ref` and optional `ref` on attacks and spells. Older files migrate automatically.

#### Quality of life
- Dice tray (d4–d100) on the attacks page, with a short animation and history.
- Coin editor and "Write value" for large numbers.
- More than one inspiration point (`schema` 2).
- Circular page navigation (page 7 → 1 and back).
- Languages: English and Spanish, automatic or manual; translating means adding one file.
- The sheet comes back on top after waking the device when a home-screen plugin (SimpleUI) covers it.

#### First version
- Opens `.dnd` (JSON) files from the KOReader file browser as a 7-page character sheet: combat, abilities and skills, attacks and gear, features and personality, spells, background, notes.
- Everything derived is calculated (modifiers, saves, skills, initiative, passive Perception, proficiency, spell DC and attack).
- Editors for every field, several characters (new, duplicate, open last), rests.
- Safe saving: atomic write, `.bak` copy of the original, read-only mode for files from a newer format.
- Layouts for several screen sizes and orientations.
