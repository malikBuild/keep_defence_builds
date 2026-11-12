#!/usr/bin/env bash
# Publish a web build to this repo's GitHub Pages site. A game's CI runs it
# from a clone of this repo:
#   publish.sh <web_dir> <slot> "<title>" [source] [sha]   add/replace a build
#   publish.sh --remove <slot>                             drop a build
# main is always ONE commit holding the newest $MAX_BUILDS (default 6) builds.
# Every attempt starts from the current main and pushes with a lease, so two
# parallel publishes retry instead of dropping each other's build.
# Push access comes from the caller: a deploy key in GIT_SSH_COMMAND, or a
# token in the clone's https remote.
set -euo pipefail

usage() {
  sed -n 4,5p "$0" >&2
  exit 2
}

here=$(cd "$(dirname "$0")" && pwd)
remote=$(git -C "$here" remote get-url origin)
max=${MAX_BUILDS:-6}
if [ "${1:-}" = --remove ]; then
  [ $# -eq 2 ] || usage
  web="" slot=$2 title="" msg="Remove $2"
else
  [ $# -ge 3 ] && [ $# -le 5 ] && [ -n "$3" ] || usage
  [ -f "$1/index.html" ] || {
    echo "no index.html in $1" >&2
    exit 1
  }
  web=$(cd "$1" && pwd) slot=$2 title=$3 msg="Publish $2: $3"
fi
src=${4:-} sha=${5:-}
case "$slot" in "" | .* | *[!A-Za-z0-9._-]*)
  echo "bad slot: $slot (use letters, digits, . _ -)" >&2
  exit 2
  ;;
esac
case "$max" in "" | 0* | *[!0-9]*)
  echo "bad MAX_BUILDS: $max" >&2
  exit 2
  ;;
esac

# Rewrites builds/ and builds.json in the current dir: drops $slot, adds the
# new build first, keeps the newest $max, deletes every unlisted folder.
update_list() {
  python3 -I - "$slot" "$title" "$src" "$sha" "$max" <<'PY'
import json, os, shutil, sys, time
slot, title, src, sha, keep = sys.argv[1:6]
builds = [b for b in json.load(open("builds.json")) if b["slot"] != slot]
if title:
    built = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    new = dict(slot=slot, title=title, source=src, sha=sha, built=built)
    builds.insert(0, new)
builds = builds[: int(keep)]
listed = {b["slot"] for b in builds}
for d in os.listdir("builds"):
    if d not in listed and os.path.isdir(os.path.join("builds", d)):
        shutil.rmtree(os.path.join("builds", d))
json.dump(builds, open("builds.json", "w"), indent=1)
print("builds:", " ".join(b["slot"] for b in builds) or "none")
PY
}

# One try in a fresh dir $1: fetch main, apply the change, push one parentless
# commit with a lease on the main we started from.
attempt() {
  mkdir -p "$1"
  cd "$1"
  git init -q
  git fetch -q --depth 1 "$remote" main
  local base
  base=$(git rev-parse FETCH_HEAD)
  git checkout -q FETCH_HEAD
  rm -rf "builds/$slot"
  if [ -n "$web" ]; then
    mkdir -p "builds/$slot"
    cp -R "$web/." "builds/$slot/"
  fi
  update_list
  git add -A
  if git diff --cached --quiet; then
    echo "nothing to change"
    return 0
  fi
  local commit
  commit=$(git -c user.name="${GIT_AUTHOR_NAME:-builds-ci}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-builds-ci@users.noreply.github.com}" \
    commit-tree "$(git write-tree)" -m "$msg")
  git push -q --force-with-lease="refs/heads/main:$base" \
    "$remote" "$commit:refs/heads/main"
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
for try in 1 2 3 4 5; do
  # errexit is off inside `if`, so run the attempt in a subshell with it on.
  set +e
  (
    set -e
    attempt "$tmp/$try"
  )
  rc=$?
  set -e
  if [ "$rc" = 0 ]; then
    echo "$msg"
    exit 0
  fi
  echo "main moved or the push failed (try $try), retrying" >&2
  sleep $((try * 3))
done
echo "could not publish: $msg" >&2
exit 1
