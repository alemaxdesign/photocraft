#!/usr/bin/env bash
# fork-sync.sh: keep the fork's three layers in step with upstream.
#
#   fork-sync.sh [--push] [--dry-run] [BRANCH...]
#
#   origin = the fork (alemaxdesign/photocraft), upstream = canonical (storytold/photocraft).
#
#   main         pure mirror of upstream/main: fast-forward only. If local main or origin/main has a commit upstream
#                lacks, the script lists it and stops.
#   alemax-main  the fork's integration branch: upstream plus our accepted work, which arrives only through PRs
#                (squash-merged on GitHub). origin/alemax-main is the source of truth: local alemax-main is
#                fast-forwarded to it, then upstream/main is MERGED in (never rebased, so merged PRs are never
#                rewritten and it is never force-pushed). A merge conflict is aborted and reported.
#   BRANCH       each PR branch (default: every local branch but main and alemax-main, e.g. claude/<topic>) is
#                rebased onto alemax-main. Commits whose changes already landed (a squash-merged PR) become empty and
#                are dropped; a branch with nothing left (its PR merged) is reported as LANDED, not pushed. A conflicting rebase is
#                aborted and reported; the branch stays as it was.
#   --push       push main and alemax-main (plain push: a non-fast-forward is refused) and each rebased branch that
#                exists on origin (--force-with-lease).
#   --dry-run    fetch, then only say what would happen.
#
# Env: FORK_SYNC_INTEGRATION (default alemax-main).
# Adapted from LightCraft's fork-sync.sh (itself from claude-meta's meta/scripts/fork-sync.sh). Every push's exit
# status is checked, because a push under `|| true` once reported a rejected push as done.
set -euo pipefail

INTEG=${FORK_SYNC_INTEGRATION:-alemax-main}
push=0 dry=0 branches=()
for a in "$@"; do
  case "$a" in
    --push) push=1 ;;
    --dry-run) dry=1 ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    -*) echo "unknown option $a" >&2; exit 2 ;;
    *) branches+=("$a") ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() { printf 'fork-sync: %s\n' "$*" >&2; exit 1; }
run() { if (( dry )); then say "  would run: $*"; else "$@"; fi; }
has() { git show-ref --verify --quiet "$1"; }

git rev-parse --git-dir >/dev/null 2>&1 || die "not in a git repository"
git remote get-url upstream >/dev/null 2>&1 || die "no 'upstream' remote"
git remote get-url origin >/dev/null 2>&1 || die "no 'origin' remote"
[[ "$(git remote get-url origin)" != "$(git remote get-url upstream)" ]] || die "origin and upstream are the same repository"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || die "uncommitted changes to tracked files: commit or stash them first"

say "fetching upstream and origin…"
git fetch --prune upstream
git fetch --prune origin
start=$(git symbolic-ref --quiet --short HEAD || git rev-parse HEAD)
restore() { [[ "$(git symbolic-ref --quiet --short HEAD || git rev-parse HEAD)" == "$start" ]] || git checkout --quiet "$start"; }
trap restore EXIT

# a branch checked out in another worktree can't be checked out here
other_worktree() {
  git worktree list --porcelain | awk -v here="$(git rev-parse --show-toplevel)" -v b="refs/heads/$1" \
    '/^worktree /{wt=substr($0,10)} $0=="branch " b && wt!=here {print wt}'
}
failed=() landed_branches=()

# ---- main: fast-forward only
say ""
say "== main"
if ! git merge-base --is-ancestor origin/main upstream/main; then
  say "origin/main has commits upstream/main lacks:"
  git log --oneline upstream/main..origin/main
  die "refusing to sync main: move those commits to a branch, then reset origin/main to upstream/main (ask first: it is a force push)"
fi
if has refs/heads/main && ! git merge-base --is-ancestor main upstream/main; then
  say "local main has commits upstream/main lacks:"
  git log --oneline upstream/main..main
  die "refusing to sync main: move those commits to a branch first"
fi
behind=$(git rev-list --count origin/main..upstream/main)
say "origin/main is $behind commit(s) behind upstream/main"
if (( behind > 0 )); then
  if (( push )); then run git push origin upstream/main:main || die "push of main to origin was refused"
  else say "  (origin/main not pushed: rerun with --push)"; fi
fi
if has refs/heads/main; then
  wt=$(other_worktree main)
  if [[ "$start" == main ]]; then run git merge --ff-only upstream/main
  elif [[ -n "$wt" ]]; then say "  local main is checked out in $wt: run 'git merge --ff-only upstream/main' there"
  else run git branch -f main upstream/main; fi
fi

# ---- integration branch: follow origin, then merge upstream/main in
say ""
say "== $INTEG"
has "refs/remotes/origin/$INTEG" || die "no origin/$INTEG: create it once with 'git push origin upstream/main:refs/heads/$INTEG'"
[[ -z "$(other_worktree "$INTEG")" ]] || die "$INTEG is checked out in another worktree: sync it there"
if ! has "refs/heads/$INTEG"; then
  run git branch --track "$INTEG" "origin/$INTEG"
elif git merge-base --is-ancestor "$INTEG" "origin/$INTEG"; then
  ahead=$(git rev-list --count "$INTEG..origin/$INTEG")
  if (( ahead > 0 )); then
    say "  $ahead commit(s) merged on origin (PRs): fast-forwarding local $INTEG"
    if [[ "$start" == "$INTEG" ]]; then run git merge --ff-only "origin/$INTEG"; else run git branch -f "$INTEG" "origin/$INTEG"; fi
  fi
else
  # Local may only be ahead by upstream merges an earlier run made without --push; anything else is work that
  # bypassed a PR.
  own=$(git rev-list --no-merges "origin/$INTEG..$INTEG" ^upstream/main)
  if ! git merge-base --is-ancestor "origin/$INTEG" "$INTEG" || [[ -n "$own" ]]; then
    say "local $INTEG has commits that did not come through a PR or upstream:"
    git log --oneline --no-merges "origin/$INTEG..$INTEG" ^upstream/main
    die "refusing to sync $INTEG: work reaches it only through PRs; move those commits to a working branch, then 'git branch -f $INTEG origin/$INTEG'"
  fi
fi
ref=$INTEG; (( dry )) && ! has "refs/heads/$INTEG" && ref="origin/$INTEG"
missing=$(git rev-list --count "$ref..upstream/main")
say "  $INTEG lacks $missing upstream commit(s)"
if (( missing > 0 )); then
  if (( dry )); then
    say "  would run: git merge --no-ff upstream/main into $INTEG"
  else
    git checkout --quiet "$INTEG"
    if ! git merge --no-ff --no-edit -m "Merge upstream/main into $INTEG" upstream/main; then
      git merge --abort || true
      restore
      die "CONFLICT merging upstream/main into $INTEG: merge aborted, nothing changed; resolve by hand"
    fi
    restore
  fi
fi
if (( push )) && { (( dry && missing > 0 )) || [[ "$(git rev-parse "$ref")" != "$(git rev-parse "origin/$INTEG")" ]]; }; then
  run git push origin "$INTEG" || die "push of $INTEG to origin was refused"
fi

# ---- working branches: rebase onto the integration branch
if (( ${#branches[@]} == 0 )); then
  while IFS= read -r b; do [[ "$b" != main && "$b" != "$INTEG" ]] && branches+=("$b"); done \
    < <(git for-each-ref --format='%(refname:short)' refs/heads)
fi
for b in ${branches[@]+"${branches[@]}"}; do
  say ""
  say "== $b (onto $INTEG)"
  has "refs/heads/$b" || { say "  no local branch $b: skipped"; continue; }
  moved=0
  if git merge-base --is-ancestor "$INTEG" "$b"; then
    say "  already on top of $INTEG ($(git rev-list --count "$INTEG..$b") own commit(s))"
  else
    wt=$(other_worktree "$b")
    if [[ -n "$wt" ]]; then say "  checked out in $wt: rebase it there"; failed+=("$b"); continue; fi
    # A squash-merged PR lands as one commit whose diff equals the branch's diff from its previous cut point to the
    # PR head. Find the newest such cut point; only the commits after it still need moving.
    mb=$(git merge-base "$INTEG" "$b")
    pids=$(git log --no-merges --format=%H "$mb..$INTEG" | while read -r h; do git show "$h" | git patch-id --stable | cut -d' ' -f1; done)
    from=$mb cut=
    for c in $(git rev-list --reverse "$mb..$b"); do
      pid=$(git diff "$from" "$c" | git patch-id --stable | cut -d' ' -f1)
      if [[ -n "$pid" ]] && grep -qx "$pid" <<<"$pids"; then cut=$c from=$c; fi
    done
    upstream_of_b=${cut:-$mb}
    if [[ -n "$cut" ]]; then
      say "  $(git rev-list --count "$mb..$cut") commit(s) already landed in $INTEG (squash-merged PR): dropped"
    fi
    say "  moving $(git rev-list --count "$upstream_of_b..$b") commit(s) onto $INTEG"
    moved=1
    if (( dry )); then
      say "  would run: git rebase --onto $INTEG $upstream_of_b $b"
    elif ! git rebase --onto "$INTEG" "$upstream_of_b" "$b"; then
      git rebase --abort || true
      say "  CONFLICT: rebase aborted, $b unchanged; resolve by hand (git rebase $INTEG $b)"
      failed+=("$b")
      continue
    fi
    (( dry )) || say "  now $(git rev-list --count "$INTEG..$b") own commit(s) on top of $INTEG$( [[ "$(git rev-parse "$b")" == "$(git rev-parse "$INTEG")" ]] && echo ' (everything landed: branch equals '"$INTEG"')')"
  fi
  if (( ! dry )) && [[ "$(git rev-parse "$b")" == "$(git rev-parse "$INTEG")" ]]; then
    say "  LANDED: $b has no changes beyond $INTEG (its PR was merged): delete it with"
    say "    git branch -D $b && git push origin --delete $b   (-D: the branch equals $INTEG; -d refuses because origin still has the pre-squash commit)"
    landed_branches+=("$b")
    continue
  fi
  if (( push )) && has "refs/remotes/origin/$b"; then
    if (( ! moved )) && [[ "$(git rev-parse "$b")" == "$(git rev-parse "origin/$b")" ]]; then
      say "  origin/$b already up to date"
    else
      run git push --force-with-lease="$b:origin/$b" origin "$b" || { say "  push of $b refused"; failed+=("$b"); }
    fi
  fi
done

if (( ${#landed_branches[@]} )); then say ""; say "landed (delete when convenient): ${landed_branches[*]}"; fi
say ""
if (( ${#failed[@]} )); then die "needs attention: ${failed[*]}"; fi
say "done$( (( dry )) && echo ' (dry run: nothing changed)')"
