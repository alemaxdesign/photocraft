#!/usr/bin/env bash
# test-fork-sync.sh: end-to-end test of fork-sync.sh on throwaway repos (bare "upstream" and "fork", a working clone,
# and a second clone standing in for GitHub's squash-merge). Usage: test-fork-sync.sh [WORKDIR]
set -uo pipefail
S="$(cd "$(dirname "$0")" && pwd)/fork-sync.sh"
T=${1:-/Volumes/PhotoEditing/photocraft-work/forksync-test}
rm -rf "$T"; mkdir -p "$T"; cd "$T" || exit 1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
pass=0 fail=0
check() { if eval "$2"; then echo "  ok   $1"; ((pass++)); else echo "  FAIL $1"; ((fail++)); fi; }
sync() { "$S" "$@" > "$T/out" 2>&1; echo $? > "$T/rc"; }
rc() { cat "$T/rc"; }
out() { grep -q "$1" "$T/out"; }
same() { [[ "$(git rev-parse "$1")" == "$(git rev-parse "$2")" ]]; }

git init -q --bare -b main up.git; git init -q --bare -b main fork.git
git clone -q up.git upw 2>/dev/null; (cd upw && echo a > f && git add f && git commit -qm u1 && git push -q origin main)
git -C fork.git fetch -q ../up.git main:main
git clone -q fork.git me; cd me
git remote add upstream ../up.git; git fetch -q upstream
git push -q origin upstream/main:refs/heads/alemax-main
git switch -q -c claude/work origin/main
echo w1 > w; git add w; git commit -qm w1; echo w2 >> w; git commit -qam w2; git push -q -u origin claude/work
upmove() { (cd ../upw && echo "$1" >> f && git commit -qam "$1" && git push -q); }
squash_pr() { (cd .. && rm -rf gh && git clone -q fork.git gh && cd gh && git switch -q alemax-main &&
  git merge -q --squash origin/claude/work 2>/dev/null && git commit -qm "$1" && git push -q origin alemax-main); }

echo "T1 first sync"; sync --push
check "exit 0" '[[ $(rc) == 0 ]]'
check "work already on top" 'out "already on top"'

echo "T2 upstream moved"; upmove u2; sync --push
check "exit 0" '[[ $(rc) == 0 ]]'
check "origin/main == upstream/main" 'git fetch -q origin && same origin/main upstream/main'
check "alemax-main got a merge commit" '[[ $(git rev-list --merges --count upstream/main..origin/alemax-main) == 1 ]]'
check "work on top of alemax-main with 2 commits" '[[ $(git rev-list --count alemax-main..claude/work) == 2 ]] && git merge-base --is-ancestor alemax-main claude/work'
check "origin/claude/work pushed" 'same claude/work origin/claude/work'

echo "T3 squash PR merged, new commit on work"; squash_pr PR1; echo w3 > w3; git add w3; git commit -qm w3; sync --push
check "exit 0" '[[ $(rc) == 0 ]]'
check "landed commits dropped" 'out "already landed"'
check "only w3 left" '[[ $(git log --format=%s alemax-main..claude/work) == w3 ]]'

echo "T4 upstream moved and PR2 merged"; upmove u3; squash_pr PR2; sync --push
check "exit 0" '[[ $(rc) == 0 ]]'
check "work equals alemax-main" 'same claude/work alemax-main'
check "reported as LANDED, not pushed" 'out "LANDED: claude/work"'
check "alemax-main contains upstream" 'git merge-base --is-ancestor upstream/main alemax-main'

echo "T5 upstream conflicts with alemax-main"; echo mine > w; git commit -qam mine
(cd ../upw && echo theirs > w && git add w && git commit -qm "upstream w" && git push -q)
before=$(git rev-parse alemax-main); sync --push
check "exit non-zero" '[[ $(rc) != 0 ]]'
check "conflict reported" 'out "CONFLICT merging upstream"'
check "alemax-main unchanged" '[[ $(git rev-parse alemax-main) == "$before" ]]'
check "no merge in progress, tree clean" '[[ -z $(git status --porcelain --untracked-files=no) ]] && ! git rev-parse -q --verify MERGE_HEAD >/dev/null'
check "back on claude/work" '[[ $(git branch --show-current) == claude/work ]]'
(cd ../upw && git reset -q --hard HEAD~1 && git push -q -f); git fetch -q upstream
git push -q -f origin upstream/main:main; git branch -f main upstream/main

echo "T6 commit made directly on local alemax-main"; git switch -q alemax-main; echo z > z; git add z; git commit -qm local-only; git switch -q claude/work
sync --push
check "exit non-zero" '[[ $(rc) != 0 ]]'
check "refused" 'out "did not come through a PR"'
check "not pushed" '! git branch -r --contains alemax-main | grep -q alemax-main'
git branch -f alemax-main origin/alemax-main

echo "T7 sync without --push, then with --push"; upmove u4; sync
check "exit 0 (local only)" '[[ $(rc) == 0 ]]'
check "origin/alemax-main not pushed" '! same alemax-main origin/alemax-main'
sync --push
check "exit 0 (accepts earlier upstream merge)" '[[ $(rc) == 0 ]]'
check "origin/alemax-main now pushed" 'same alemax-main origin/alemax-main'

echo "T8 dry run when nothing to do"; sync --dry-run --push
check "exit 0" '[[ $(rc) == 0 ]]'
check "no push announced" '! out "would run: git push"'

echo; echo "$pass passed, $fail failed"; (( fail == 0 ))
