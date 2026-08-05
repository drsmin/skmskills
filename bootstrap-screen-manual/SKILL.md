---
name: bootstrap-screen-manual
description: Install a screen-based user manual (docs/manual/ wiki — one page per screen) plus an automated drift guard that fails the test suite when screens, menus, or permissions change without a doc update. Use when the user asks for "사용 설명서/메뉴얼 만들어줘", "화면 기준 매뉴얼", "user manual for the app", "문서가 안 낡게 해줘", "keep the docs in sync with the UI", or wants to port this manual discipline to another project. Works with or without a permission system; adapts to the project's router and test runner.
---

# Screen-based manual + drift guard

Installs a user-facing manual into the **current** project and — the point of this skill — makes it
**impossible to change the UI and silently leave the manual stale**, because the test suite fails.

> A manual nobody is forced to update is a manual that lies within a month. So the structure is
> chosen for machine-checkability: **one page per screen**, each page declaring which screen it
> documents, and an index that must link them all.

Two audiences, kept apart: this manual is for people **using** the app. Design rationale belongs in
`docs/decisions.md` (see `bootstrap-docs-workflow`), not here.

---

## 0. Gather real material (never invent screens)

Collect these before writing. Each one you find becomes a check the guard can enforce; each one that
doesn't exist in this project is simply skipped (say so in your report).

| Material | How to find it | Used for |
| --- | --- | --- |
| **Screen list** | Next.js App Router: `find src/app -name page.tsx`. Pages Router: `src/pages/**`. React Router / Vue Router: the route table file (grep `path:`). Otherwise ask. | One doc per screen |
| **Menu/nav definition** | grep for the sidebar/header component (`NAV`, `menuItems`, `routes` array with labels) | Menu names, section grouping |
| **Permission/role catalog** | grep `permissions`, `roles`, `can(`, `ability` | Per-screen "required permission", role table |
| **Real UI strings** | Extract visible text from each screen's source (see below) | Button/tab/badge names that match reality |
| **Test runner** | `package.json` scripts (`vitest`, `jest`, `mocha`, none) | Where the guard lives |

Extract UI vocabulary per screen rather than guessing labels — a manual with invented button names is
worse than none:

```bash
# Visible strings per screen file (skip comment lines), deduped
python3 - <<'PY'
import re
for f in ["src/app/records/page.tsx"]:            # ← each screen file
    seen=[]
    for line in open(f,encoding="utf8"):
        if line.strip().startswith(("*","//","/*")): continue
        for m in re.findall(r"[가-힣A-Za-z][가-힣A-Za-z0-9 ·()\[\]/:%\-\.]{2,34}", line):
            m=m.strip()
            if m not in seen: seen.append(m)
    print(f, "|", " | ".join(seen[:80]))
PY
```

---

## 1. Structure — `docs/manual/`

```
docs/manual/
├── index.md          ← hub: screen table, reading order by role, glossary, update rules
├── <screen>.md       ← one page per screen, named after the MENU LABEL
└── <cross-cutting>.md ← e.g. roles-and-permissions, troubleshooting
```

**Name files after the menu label. Do not number them** (`01-`, `02-`): inserting a screen later
forces a rename of everything and breaks every link. Ordering is the index's job, not the
filesystem's. Use the project's existing path language convention (Korean paths are fine if the repo
already uses them).

### The contract line (this is what makes the guard possible)

Every screen page starts with one declaration line. The guard parses it, so it must be exact:

```markdown
[← manual index](./index.md)

# Records

> **Screen:** `/records` · **Menu:** Use › Records · **Permission:** `records:read`
```

Accepted markers: `**Screen:**` or `**화면 경로:**`. Everything else on the line is free text.

Because the mapping lives in the docs, **do not hardcode a screen→file table in the test** — that
table would itself go stale, which is the exact problem being solved.

### Page skeleton

Keep every page to the same shape so readers can skim across screens:

1. `# <screen name>` + contract line
2. **What this screen is for** — one or two sentences
3. **Layout** — what's where (left/right/top), only if non-obvious
4. **Steps** — numbered, imperative, using real button labels
5. **Things to know** — the surprising behaviors, each with the *user-visible* reason
6. Footer links: next page + troubleshooting

### index.md must contain

- A table: menu section · screen · route · permission · link (one row per screen page)
- Reading order per role ("I'm a first-time user / an admin / an operator")
- Glossary of domain terms the UI uses
- **"How to keep this current"** — the two mechanisms (guard + human judgment) and the checklist for
  adding a new screen

---

## 2. Write the pages

- Use the **real strings** collected in step 0. If a label is ambiguous in source, open the file.
- Explain *why* only where the user needs it to act (e.g. "changing the mapping clears the result —
  so you never save XML that doesn't match its inputs"). No architecture talk.
- Cross-link screens instead of repeating: mention of another screen → link to its page.
- A troubleshooting page pays for itself: symptom → cause → what to do, one row each. Harvest rows
  from the error/toast strings in the source.

---

## 3. Install the drift guard

Put it where the project's tests already live (`test/manual.test.ts`, `__tests__/manual.test.js`, …).
If there is **no** test runner, write `scripts/check-manual.mjs` with the same logic, add
`"docs:check": "node scripts/check-manual.mjs"` to `package.json`, and wire it into CI.

Enable only the checks whose material exists in this project:

| Check | Requires | Catches |
| --- | --- | --- |
| every screen is declared in some page | screen list | new screen, no doc |
| each screen declared **exactly once** | screen list | explanation split across pages |
| menu label + route + permission present in that page | nav source | renamed menu |
| permission IDs + labels + roles present | permission catalog | new permission, stale table |
| role→permission table matches the code | role definitions | hand-written table drifting |
| index links every page (no orphans) | — | page nobody can reach |
| every relative link resolves | — | broken links |
| no page declares a screen that no longer exists | screen list | stale page left behind |

Reference implementation (vitest + Next.js App Router; adapt the two source-scanning helpers for
other stacks — everything else is portable as-is):

```ts
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { describe, expect, it } from "vitest";
// If the project has one, import the permission/role catalog here.

const ROOT = process.cwd();
const MANUAL_DIR = path.join(ROOT, "docs", "manual");
const INDEX = "index.md";
/** Contract line: **Screen:** `/x` (or the localized marker). */
const ROUTE_DECL = /\*\*(?:Screen|화면 경로):\*\*\s*`([^`]+)`/g;

async function manualDocs() {
  const files = (await readdir(MANUAL_DIR)).filter((f) => f.endsWith(".md")).sort();
  return Promise.all(files.map(async (file) => {
    const text = await readFile(path.join(MANUAL_DIR, file), "utf8");
    return { file, text, routes: [...text.matchAll(ROUTE_DECL)].map((m) => m[1]) };
  }));
}

// ── ADAPT: how this project defines screens ────────────────────────────────
async function screenRoutes(dir = path.join(ROOT, "src", "app"), base = ""): Promise<string[]> {
  const out: string[] = [];
  for (const e of await readdir(dir, { withFileTypes: true })) {
    if (e.isDirectory()) {
      if (e.name.startsWith("_") || e.name === "api") continue;      // not screens
      const seg = /^\(.*\)$|^@/.test(e.name) ? "" : `/${e.name}`;    // route groups don't add a segment
      out.push(...(await screenRoutes(path.join(dir, e.name), base + seg)));
    } else if (e.name === "page.tsx") out.push(base === "" ? "/" : base);
  }
  return out.sort();
}
// For a route-table project instead:
//   const src = await readFile("src/routes.tsx", "utf8");
//   return [...src.matchAll(/path:\s*"([^"]+)"/g)].map((m) => m[1]);

// ── ADAPT: how this project defines the menu ───────────────────────────────
async function navItems() {
  const src = await readFile(path.join(ROOT, "src/components/app-shell.tsx"), "utf8");
  const start = src.indexOf("const NAV");
  const nav = src.slice(start, src.indexOf("\n];", start));
  return [...nav.matchAll(/path:\s*"([^"]+)",\s*\n\s*label:\s*"([^"]+)"/g)].map((m) => ({
    path: m[1], label: m[2],
    permission: /permission:\s*"([^"]+)"/.exec(nav.slice(m.index!, m.index! + 400).split(/\n\s*\{/)[0])?.[1],
  }));
}

describe("user manual stays in sync", () => {
  it("every screen is documented exactly once", async () => {
    const docs = await manualDocs();
    const routes = await screenRoutes();
    expect(routes.length).toBeGreaterThan(1);            // scan didn't silently return nothing

    const declared = new Map<string, string[]>();
    for (const d of docs) for (const r of d.routes) declared.set(r, [...(declared.get(r) ?? []), d.file]);

    expect(routes.filter((r) => !declared.has(r)), "undocumented screens").toEqual([]);
    expect([...declared].filter(([, f]) => f.length > 1).map(([r, f]) => `${r} → ${f}`), "documented twice").toEqual([]);
  });

  it("no page documents a screen that no longer exists", async () => {
    const routes = new Set(await screenRoutes());
    const stale = (await manualDocs()).flatMap((d) => d.routes.filter((r) => !routes.has(r)).map((r) => `${d.file} → ${r}`));
    expect(stale, "stale pages").toEqual([]);
  });

  it("menu labels, routes and permissions appear in their page", async () => {
    const docs = await manualDocs();
    const problems: string[] = [];
    for (const item of await navItems()) {
      const doc = docs.find((d) => d.routes.includes(item.path));
      if (!doc) { problems.push(`${item.label} (${item.path}): no page`); continue; }
      if (!doc.text.includes(item.label)) problems.push(`${doc.file}: menu name "${item.label}" missing`);
      if (item.permission && !doc.text.includes(`\`${item.permission}\``)) problems.push(`${doc.file}: ${item.permission} missing`);
    }
    expect(problems).toEqual([]);
  });

  it("index links every page and links resolve", async () => {
    const docs = await manualDocs();
    const index = docs.find((d) => d.file === INDEX)!;
    expect(index, "docs/manual/index.md missing").toBeDefined();

    const orphans = docs.filter((d) => d.file !== INDEX && !index.text.includes(`(./${d.file})`)).map((d) => d.file);
    expect(orphans, "not linked from index").toEqual([]);

    const files = new Set(docs.map((d) => d.file));
    const broken: string[] = [];
    for (const d of docs) {
      for (const m of d.text.matchAll(/\]\((\.?\.?\/[^)#]+\.md)(#[^)]*)?\)/g)) {
        const t = m[1];
        if (t.startsWith("../")) await readFile(path.join(MANUAL_DIR, t), "utf8").catch(() => broken.push(`${d.file} → ${t}`));
        else if (!files.has(t.replace("./", ""))) broken.push(`${d.file} → ${t}`);
      }
    }
    expect(broken, "broken links").toEqual([]);
  });
});
```

If the project has a permission catalog, add the two checks that compare the doc's tables against it
(IDs present, and each role's row containing exactly its granted permissions). **Find role rows by
role ID, not by label** — labels like "Admin" also appear in the menu table and you'll match the
wrong row.

### What the guard must NOT check

Button wording, step order, warning phrasing, screenshots. Pinning those means duplicating UI strings
into the docs; then every copy tweak turns the test red and the team's fix will be to weaken the
guard. Draw the line at structure, and say so in `index.md` under "what a human must check".

---

## 4. Wire the rule in

Add to `CLAUDE.md` (the rule hub — see `bootstrap-docs-workflow`):

- Working rules: **"If you changed a screen, menu, or permission, fix `docs/manual/` in the same
  commit"**, with the note that the guard catches routes/menus/permissions but **not** wording.
- Location index: a row pointing at `docs/manual/` and the guard's path.

---

## 5. Prove the guard fails (do not skip)

A docs test that cannot fail is decoration. Inject each drift, confirm the expected failure, revert:

| Injection | Expected failure |
| --- | --- |
| add a new screen file | `undocumented screens: ['/new']` |
| rename a menu label in the nav source (or in the doc) | `menu name "…" missing` |
| point an index link at a non-existent file | `broken links` **and** `not linked from index` |
| copy a screen page (two pages declaring one screen) | `documented twice` |
| add a permission (if applicable) | missing permission ID |

Back up the files you touch **before** injecting (`cp -r docs/manual /tmp/manual.bak`) and verify the
revert with `git status` — a half-reverted injection is a real bug you just wrote.

---

## 6. Record and report

Under the Markdown-first methodology: `docs/session-log.md` entry, a `D-NNN` in `docs/decisions.md`
for the structure choice (one page per screen, contract line, what is deliberately not checked), and
`docs/todo.md` follow-ups. Then `wrap-up-docs-commit` to commit and push.

Report to the user: pages created, checks enabled **and which were skipped for lack of material**,
and the drift-injection results.

---

## Anti-patterns (each one was learned the hard way)

- **Numbered filenames** — renumbering on every insertion, broken links.
- **A screen→file table inside the test** — the table goes stale, defeating the purpose.
- **Checking UI wording** — red tests on copy edits; the team weakens the guard.
- **One giant `manual.md`** — grows without bound; nobody can read just their screen.
- **Screenshots added casually** — they rot faster than prose. Add them only with a stated rule for
  when they get retaken.
- **Writing the manual from the code's data model** — users navigate by screen and menu, not by
  module. If a section has no screen, it belongs in `decisions.md`.
