# Battle loading screen — original backup (2026-06-29)

Captured before the cinematic battle-intro redesign, so the old
"Finding an opponent…" loader is always recoverable.

## What's here
- `KnowledgeBattles.tsx` — full, byte-identical copy of the file at backup time
  (SHA256 verified equal to the live file before any edits).
- `Battles.css` — the related stylesheet at backup time.
- `SearchingScreen.original.tsx` — just the original `phase === "searching"`
  JSX block, for a surgical restore.

## How to restore

### Option A — full restore (simplest)
Copy the two files back over the working tree:
```
cp backup/battle-loading-original-2026-06-29/KnowledgeBattles.tsx src/components/KnowledgeBattles.tsx
cp backup/battle-loading-original-2026-06-29/Battles.css           src/components/Battles.css
```
Then delete the new intro files if you want a clean revert:
```
rm src/components/battles/BattleIntro.tsx src/components/battles/BattleIntro.css
```

### Option B — git
The redesign lands in its own commit, so:
```
git revert <redesign-commit-sha>
```
or check out the original file from this backup's commit.

### Option C — surgical
Paste the block from `SearchingScreen.original.tsx` back into the
`phase === "searching"` branch of `KnowledgeBattles.tsx`, replacing the
`<BattleIntro …/>` render.
