# kant-cli skill

Agent skill for the Kant protocol CLIs. See [SKILL.md](SKILL.md).

Install for an agent session:

```bash
ln -s ~/projects/pastebin/skills/kant-cli ~/.agents/skills/kant-cli
```

or with the skills CLI:

```bash
npx skills add ~/projects/pastebin --skill kant-cli --yes
```

The bundled CLI itself needs no install: `dist/kant-cli.mjs` is one
self-contained file — download it from the site (`/kant-cli.mjs`) or from a
GitHub Release, `chmod +x`, and run with Node ≥ 18.
