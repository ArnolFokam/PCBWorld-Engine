#!/usr/bin/env bash
# Content hash of the C++ patch tree — the one implementation every consumer calls.
#
#   bash engine/tools/cpp_content_hash.sh [patches-dir]     # 8 hex chars on stdout
#
# The hash covers the SOURCE files under engine/kicad-patches/ EXCEPT ENGINE_VERSION (that file
# carries the version, which a bump rewrites without touching a line of C++). It is what
# "the built router matches this source" means:
#
#   * build_rl_router.sh writes it next to the freshly built .so (ENGINE_CPP_HASH),
#   * pcb_world/engine/provenance.py compares the two right before a router is loaded (and
#     tests/test_engine_api/test_engine_build_version.py in the suite), so a C++ edit refuses
#     the old router until it is rebuilt — independent of any version bump, and correct in a
#     tree that points at a build made elsewhere (content, not mtime: a fresh worktree stamps
#     checkout time on every file).
#
# Which files are "the sources": in a git checkout, what git sees — tracked files plus untracked
# files that are not ignored (`git ls-files --cached --others --exclude-standard`), so a NEW
# uncommitted .cpp counts. Outside a checkout (a tarball, or a copy under an ignored dir) every
# regular file under the tree. Either way editor/merge leftovers are dropped — dotfiles, *.swp,
# *.orig, *.rej, *~ — so a vim swap file cannot make every engine construction refuse the router.
# The two listings agree on a clean tree; a copy that holds files git would ignore (*.o, tags,
# a global excludes match) or symlinked sources would hash differently — kicad-patches/ has neither.
#
# Hash = sha256 over, per file in C-locale path order: relative path, NUL, bytes, NUL.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PATCHES_DIR="${1:-$HERE/../kicad-patches}"
[ -d "$PATCHES_DIR" ] || { echo "cpp_content_hash: no patch tree at $PATCHES_DIR" >&2; exit 1; }

cd "$PATCHES_DIR"

# NUL-separated relative paths (git prints them without "./"; find with — stripped below).
list_files() {
    if command -v git >/dev/null 2>&1 \
       && [ "$(git ls-files --cached -z -- . 2>/dev/null | wc -c)" -gt 0 ]; then
        git ls-files -z --cached --others --exclude-standard -- .
    else
        find . -type f -print0
    fi
}

list_files \
  | LC_ALL=C sort -z \
  | while IFS= read -r -d '' f; do
        f="${f#./}"
        case "$f" in
            ENGINE_VERSION|*/ENGINE_VERSION) continue ;;          # the version, not C++
            .*|*/.*|*.swp|*.orig|*.rej|*~) continue ;;            # editor / merge leftovers
        esac
        [ -f "$f" ] || continue                                   # in the index but deleted
        printf '%s\0' "$f"
        cat "$f"
        printf '\0'
    done \
  | { command -v sha256sum >/dev/null && sha256sum || shasum -a 256; } \
  | cut -c1-8
