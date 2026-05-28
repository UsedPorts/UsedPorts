#!/usr/bin/env bash
set -euo pipefail

# Prepare a release: bump the version + build number in project.yml, insert a
# new CHANGELOG entry for the version with the supplied notes, and regenerate
# Info.plist. The notes are also normalized into RELEASE_NOTES.md for the
# GitHub release body.
#
# Usage: cut-release.sh X.Y.Z [NOTES_FILE]
#   NOTES_FILE  optional path to a file holding the release-notes body
#               (Markdown). If omitted/empty the entry has only a heading.
#
# Does NOT commit, tag, or push — the caller does that. The build number is the
# UTC date (YYYYMMDD).

cd "$(git rev-parse --show-toplevel)"

VERSION="${1:-}"
NOTES_FILE="${2:-}"
REPO="UsedPorts/UsedPorts"

if ! printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "usage: cut-release.sh X.Y.Z [NOTES_FILE] (got '${VERSION}')" >&2
  exit 1
fi

BUILD="$(date -u +%Y%m%d)"
DATE="$(date -u +%Y-%m-%d)"

# --- normalize the notes body (blank-trimmed) into RELEASE_NOTES.md ----------
: > RELEASE_NOTES.md
if [ -n "$NOTES_FILE" ] && [ -s "$NOTES_FILE" ]; then
  awk '
    { buf[n++] = $0 }
    END {
      s = 0;     while (s < n  && buf[s] ~ /^[[:space:]]*$/) s++
      e = n - 1; while (e >= s && buf[e] ~ /^[[:space:]]*$/) e--
      for (i = s; i <= e; i++) print buf[i]
    }
  ' "$NOTES_FILE" > RELEASE_NOTES.md
fi

# --- project.yml: version + build number -------------------------------------
sed -i.bak -E "s/(CFBundleShortVersionString: )\"[^\"]*\"/\1\"${VERSION}\"/" project.yml
sed -i.bak -E "s/(CFBundleVersion: )\"[^\"]*\"/\1\"${BUILD}\"/" project.yml
rm -f project.yml.bak

# --- CHANGELOG: insert "## [VERSION] - DATE" + notes above the newest entry --
{
  echo "## [${VERSION}] - ${DATE}"
  echo
  if [ -s RELEASE_NOTES.md ]; then
    cat RELEASE_NOTES.md
    echo
  fi
} > .changelog-section.tmp

awk -v sf=".changelog-section.tmp" '
  /^## \[/ && !done {
    while ((getline line < sf) > 0) print line
    close(sf)
    done = 1
  }
  { print }
' CHANGELOG.md > CHANGELOG.tmp && mv CHANGELOG.tmp CHANGELOG.md
rm -f .changelog-section.tmp

# Link reference, inserted above the topmost existing version link.
awk -v ver="$VERSION" -v repo="$REPO" '
  /^\[[0-9]+\.[0-9]+\.[0-9]+\]: / && !added {
    print "[" ver "]: https://github.com/" repo "/releases/tag/v" ver
    added = 1
  }
  { print }
' CHANGELOG.md > CHANGELOG.tmp && mv CHANGELOG.tmp CHANGELOG.md

# --- regenerate Info.plist from the bumped project.yml -----------------------
if command -v xcodegen >/dev/null; then
  xcodegen generate >/dev/null
else
  echo "warning: xcodegen not found; App/Info.plist not regenerated" >&2
fi

echo ">> prepared v${VERSION} (build ${BUILD})"
echo ">> release notes:"
sed 's/^/   /' RELEASE_NOTES.md
