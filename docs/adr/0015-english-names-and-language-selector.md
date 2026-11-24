# 0015. English names and a language selector

- Status: Accepted
- Date: 2026-11-24

## Context and problem statement

The kit was written in Spanish. After version 2.7.0 the interface, the comments and the documentation were translated to
English, but the identifiers stayed Spanish: 41 commands and three hooks (`tmux-nivel`, `ws-telemetria`,
`ws-trazas.sh`), subcommands and options (`ws-telemetria abrir`, `--todas`), environment variables (`WS_TETOCA`), tmux
options (`@cfase`), configuration and state folders (`~/.config/ws-ruteo`), stored values (`completo`, `puro`,
`trabajo`) and the field names of the telemetry files (`herramienta`, `entrada`). A reader who does not know Spanish
could use the menus but could not read a command line, a script or a log.

Spanish also sat inside the logic. Regular expressions and word lists that match prompts typed in Spanish, and
answers Claude writes in Spanish, were hard-coded next to the English ones in the routing rules, the subagent hint,
the "waiting for you" detector, the notification filter, the Telegram command extractor, the audit and the report.
A user who works only in English carried patterns that can only misfire; a user who works in Spanish must not lose
them.

The owner's installation has run for months: 13 months of telemetry retention, personal settings, an encrypted cloud
backup, a private configuration repository and a live tmux session. A rename must not lose or silently orphan any of
it. The question is how far the rename goes, what happens to existing installations, and where language-dependent
behavior lives.

## Decision drivers

- One language for everything a contributor reads: interface, identifiers, comments, documentation.
- No data loss on upgrade, and no file of the user overwritten.
- A tab opened before the upgrade must keep working until it is restarted.
- Spanish prompts must stay recognized for the users who type them, and must not affect the others.
- The cost must fit a kit of about 150 scripts maintained by one person, with no translators.

## Considered options

- **A. Keep the Spanish identifiers.** No migration and no breaking change. The repository stays half translated:
  the documentation has to explain Spanish words on every page, and new contributors keep meeting them.
- **B. Rename with a hard break and no migration.** The smallest change to the code. Every existing installation
  loses its telemetry history, settings and backups under the new names unless the user moves them by hand, and
  every open tab breaks at once.
- **C. Rename, migrate in the installer, and read both names where the installer cannot reach.** More code to write
  and to remove later. Existing installations keep their data and keep working during the change.
- **D. Full internationalization of the interface with message catalogues.** Menus and messages in the user's
  language. It means extracting every string of about 150 scripts into catalogues and keeping two translations in
  step with no translators, and it does not answer the request: the users asked which language the kit *recognizes*
  in their prompts, not which language the menus are in.

## Decision

Option **C**, with the interface in English only.

1. **The repository is English only**: interface, messages, comments, documentation and every identifier (command and
   file names, subcommands, options, environment variables, tmux options, folders, configuration keys, stored values,
   JSON and CSV field names). Version 3.0.0 carries the rename.
2. **Language-dependent matching lives in language packs**, selected with `ws-lang`:
   - `en` (the default) activates the English pack, and Claude is asked to write reports and handoffs in English;
   - `es` activates the English **and** the Spanish pack, because prompts mix both, and Claude is asked to write in
     Spanish.

   The packs are `~/.local/lib/ws-lang/en.conf` and `es.conf` (`key=value`, one consumer and one regular-expression
   dialect per key) plus `rules.es.conf` next to the routing rules. The setting is one word in
   `~/.config/tmux-claude/lang`; `WS_LANG` overrides it; consumers read it on every use. The Spanish in a pack is
   data, not interface text.
3. **The installer migrates existing installations** (`migrate.sh`, driven by `renames.tsv`), before it copies the
   new files:
   - the user's data and settings are **moved** to the new names and never overwritten: when both names exist, both
     are left and a warning is printed;
   - each old command and hook is replaced by a **wrapper** that prints the new name and runs it, so tabs opened
     before the upgrade keep working; `install.sh --remove-shims` deletes the wrappers;
   - old kit files that nothing calls are **set aside** in `~/.local/share/ws-kit/pre-english.<date>/`; nothing is
     deleted;
   - a migrated installation is set to `es`, so its behavior does not change.
4. **What the installer cannot reach is read under both names** by the code that uses it:
   - the Windows Credential Manager entry `age-respaldo` (new setups write `age-backup`);
   - the OneDrive folder `Respaldos\estacion-wsl` (the default is now `Backups\workstation-wsl`);
   - the personal repository `~/code/estacion-personal` with its `incluir.txt`;
   - backup archives that carry `inventario/` instead of `inventory/`;
   - the telemetry history: records with Spanish field names and values are normalized when they are read, by one
     mapping table per script, and the files are never rewritten;
   - keys and values in files the user edits (`tema=`, `grupos=`, `bajar_max_ctx=`, saved scene and theme names,
     the Telegram settings).
5. **tmux live state gets no compatibility code.** The installer tells the user to restart the tmux server.

## Consequences

- Positive: a reader needs one language for the interface, the commands, the code and the logs.
- Positive: an existing installation keeps its history, settings and backups, and the upgrade can be previewed
  (`install.sh --dry-run`) and undone from the set-aside folder and the `*.bak.<date>` files.
- Positive: Spanish matching is opt-in and lives in one place per language; another language is one more pack, with
  no change to the scripts.
- Negative: **breaking change.** Scripts, aliases, scheduled jobs and personal tmux configuration that call the old
  subcommands, options, variables or tmux options must be updated: the wrappers pass arguments through unchanged.
  Spreadsheets and queries that read the old CSV columns or JSON keys (`ws-telemetry export`,
  `ws-telemetry estimate --csv` and `--json`, `ws-report --json`) must be updated too.
- Negative: compatibility code to maintain and then remove in the next major version: the wrappers, the
  `claude-trabajo` alias, the mapping tables that read old records and old keys, the fallbacks for the credential, the
  OneDrive folder and the personal repository, and the sandbox deny rules for the old credential paths.
- Negative: a running tmux server must be restarted after the upgrade. The Windows notification handler is patched in
  place by the migration; if it cannot be reached, the installer says so and it must be edited by hand.
- Negative: the interface is not translated. A user who wants menus in another language is not served by this
  decision.
- Negative: a language pack is a list of regular expressions that has to be maintained, and a key is tied to the
  dialect of its one consumer.
