---
name: fork-sync
description: Sync the alemaxdesign/photocraft fork with storytold/photocraft - main mirrors upstream (fast-forward only), alemax-main merges upstream in and receives our work only through squash-merged PRs, and PR branches claude/<topic> are rebased onto alemax-main. Claude sits on alemax-main and creates one PR branch per requested change. Use when the user asks to sync, update or rebase the fork, pull upstream changes, check whether upstream moved, or open/merge a PR of our work.
---

# fork-sync

Three layers (rules in `CLAUDE.local.md`):

| Branch | Role | Moves by |
|---|---|---|
| `main` | exact mirror of `upstream/main` (storytold) | fast-forward only |
| `alemax-main` | the fork's integrated version: upstream + our accepted work | squash-merged PRs on GitHub; `upstream/main` merged in (never rebased, never force-pushed) |
| `claude/<topic>` | one PR branch per requested change | commits by Claude; rebased onto `alemax-main`; deleted once merged |

Script: `claude-plugins/slg-ptc/skills/fork-sync/fork-sync.sh` (inside the plugin: `${CLAUDE_PLUGIN_ROOT}/skills/fork-sync/fork-sync.sh`), run from the repository root. Tests:
`claude-plugins/slg-ptc/skills/fork-sync/test-fork-sync.sh` (throwaway repos in `/Volumes/PhotoEditing/photocraft-work`).

## Sync

1. Preview: `fork-sync.sh --dry-run --push`.
2. If it **refuses to sync main** (origin/main or local main has commits upstream lacks) or **refuses to sync
   alemax-main** (local commits that did not come through a PR), show the user the list and stop. Fixing it means
   moving commits to a `claude/<topic>` branch and resetting a branch: ask first.
3. Otherwise `fork-sync.sh --push` (pushing is outward-facing: run it when the user asked to sync or push).
4. A **CONFLICT merging upstream into alemax-main** or **rebasing a PR branch** is aborted with nothing changed:
   report it; resolve by hand only with the user.
5. Report: commits main gained, whether alemax-main merged upstream, how many own commits each PR branch carries,
   and any branch reported **LANDED** (its PR merged): offer to delete it (`git branch -d <b> && git push origin --delete <b>`)
   and switch back to alemax-main.
6. To pick up changes in the running app, rebuild (`cargo build -p photocraft -p photocraft-cli --features heif`)
   and offer to restart it. If PhotoCraft is running, quit it first and relaunch it detached (see `/slg-ptc:photo-retouch`).

## A requested change = one PR (claude/<topic> into alemax-main)

0. Default state: on `alemax-main`, clean, synced. Never commit on it.
1. Sync (`fork-sync.sh --push`), then `git switch -c claude/<topic> alemax-main`; commit; `git push -u origin claude/<topic>`.
2. `gh pr create --repo alemaxdesign/photocraft --base alemax-main --head claude/<topic> --title "<type>(<scope>): …" --body …`
   (always pass `--repo` and `--base`: the fork's default branch is main, and a PR must never target main or upstream).
3. The user reviews; merge only when they say so: `gh pr merge <n> --repo alemaxdesign/photocraft --squash`
   (never `--merge`/`--rebase`; keep the branch, no `--delete-branch`).
4. Sync again: the script sees the squash commit and reports the branch LANDED. Delete it (local + origin) and
   `git switch alemax-main`.

Something for storytold goes on a separate branch cut from `upstream/main` with only those commits, never from
alemax-main or a claude/<topic> branch (they carry fork-only changes); PR to storytold only when the user decides.

## Options

- `BRANCH...`: only these working branches (default: every local branch but main and alemax-main)
- `--push`: push main and alemax-main (plain push, a non-fast-forward is refused) and the rebased working
  branches that exist on origin (`--force-with-lease`)
- `--dry-run`: fetch, then only describe
- env `FORK_SYNC_INTEGRATION`: integration branch name (default `alemax-main`)

## Guarantees

- main is never merged into, rebased or force-pushed; alemax-main is never rebased or force-pushed.
- Local commits on alemax-main that did not come from a PR or upstream stop the script.
- Conflicts are aborted at once; nothing is left half-merged or half-rebased; the starting branch is restored.
- Every push's exit status is checked.
- The tree must have no uncommitted changes to tracked files.
