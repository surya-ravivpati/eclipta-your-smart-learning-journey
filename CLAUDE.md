# Repo conventions for Claude

## Git workflow

- The user wants commits landed on `main`. Default workflow: commit on the
  designated feature branch, then fast-forward `main` to it and push, the
  same as `git checkout main && git merge --ff-only <branch> && git push
  origin main`. No PR / review gate.
- Keep the feature branch in sync with the rebased history (force-push with
  `--force-with-lease` after a rebase) so the branch ref doesn't drift
  behind `main`.
- Don't ask before pushing to `main` — it's pre-authorised for this repo.
  Still confirm before truly destructive ops (force-push to a branch other
  people work on, `git reset --hard` of someone else's commits, etc.).
