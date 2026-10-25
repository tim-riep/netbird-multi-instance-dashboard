#!/usr/bin/env bash
#
# Merge netbirdio/dashboard into this fork's main branch.
#
# Every upstream release tag (vX.Y.Z) the fork doesn't have yet is merged on
# its own and tagged with the same name, so the fork's vX.Y.Z is exactly that
# upstream release plus this fork's changes. Then upstream main is merged.
# Pushing main and the new tags starts fork-image.yml for each of them.
#
# Stops without pushing anything when a merge conflicts; resolve it by hand:
#   git fetch upstream && git merge upstream/main
#
# Usage: sync-upstream.sh [upstream-url] [remote]
set -euo pipefail

UPSTREAM=${1:-https://github.com/netbirdio/dashboard.git}
REMOTE=${2:-origin}

git fetch --no-tags "$UPSTREAM" \
    "+refs/heads/main:refs/upstream/main" \
    "+refs/tags/*:refs/upstream-tags/*"
git fetch --tags "$REMOTE"

merge() {
    if ! git merge --no-ff --no-edit -m "$2" "$1"; then
        git merge --abort
        echo "::error::Merging $1 conflicts with this fork's changes. Merge it by hand." >&2
        exit 1
    fi
}

new_tags=()
for tag in $(git for-each-ref --format='%(refname:strip=2)' refs/upstream-tags |
    grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V); do
    if ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
        new_tags+=("$tag")
    fi
done

for tag in ${new_tags[@]+"${new_tags[@]}"}; do
    echo "New upstream release $tag"
    merge "refs/upstream-tags/$tag" "Merge upstream release $tag"
    git tag -a "$tag" -m "netbirdio/dashboard $tag with this fork's changes"
done

merge refs/upstream/main "Merge upstream main"

git push --atomic "$REMOTE" HEAD:refs/heads/main ${new_tags[@]+"${new_tags[@]/#/refs/tags/}"}
