#!/bin/bash
# install.sh [PREFIX]: installs ade into PREFIX/bin (default ~/.local/bin), with its version stamped in. Re-running
# upgrades in place; a failed download keeps the installed ade.
#   From a checkout: installs the checkout's ade and VERSION.
#   Piped (curl -fsSL https://raw.githubusercontent.com/better-ade/ade-cli/main/install.sh | bash): downloads the tagged
#   release that main's VERSION names (v<VERSION>), never main itself. ADE_CLI_REF=v1.2.3 picks another release tag.
set -eu
base="${ADE_CLI_BASE:-https://raw.githubusercontent.com/better-ade/ade-cli}"
prefix="${1:-${PREFIX:-$HOME/.local}}"
die() { echo "install: $*" >&2; exit 1; }
src="${BASH_SOURCE[0]:-}"; here=""
if [ -n "$src" ] && [ -f "$src" ]; then here="$(cd "$(dirname "$src")" && pwd)"; fi
tmp=""; trap '[ -z "$tmp" ] || rm -rf "$tmp"' EXIT
if [ -z "${ADE_CLI_REF:-}" ] && [ -n "$here" ] && [ -f "$here/ade" ] && [ -f "$here/VERSION" ]; then
  version="$(tr -d ' \n' < "$here/VERSION")"; script="$here/ade"
else
  command -v curl > /dev/null 2>&1 || die "needs curl"
  ref="${ADE_CLI_REF:-}"
  if [ -z "$ref" ]; then v="$(curl -fsSL "$base/main/VERSION")" || die "could not read the release version"; ref="v$(printf '%s' "$v" | tr -d ' \n')"; fi
  version="${ref#v}"
  echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || die "not a release tag: $ref"
  tmp="$(mktemp -d)"; script="$tmp/ade"
  curl -fsSL "$base/$ref/ade" -o "$script" || die "could not download ade $ref"
  [ "$(head -1 "$script")" = "#!/bin/bash" ] || die "the download of ade $ref is not the ade script"
  # release.json (A12): every release from MANIFEST_SINCE on has one; it must be ade-cli's, for exactly this version,
  # and name the sha256 of ade (a url in it is ignored: the file comes from its tag). Anything short of a match installs
  # nothing. ADE_RELEASES_BASE (tests) points at another release folder.
  MANIFEST_SINCE=0.2.0
  if [ "$(printf '%s\n%s\n' "$MANIFEST_SINCE" "$version" | sort -t. -k1,1n -k2,2n -k3,3n | head -1)" = "$MANIFEST_SINCE" ]; then
    rbase="${ADE_RELEASES_BASE:-https://github.com}"
    curl -fsSL --max-time 20 "$rbase/better-ade/ade-cli/releases/download/$ref/release.json" -o "$tmp/release.json" 2> /dev/null ||
      die "there is no release.json for ade $ref (every release from $MANIFEST_SINCE on has one); nothing installed"
    want="$(python3 -c 'import json, re, sys
try:
    d = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    print("!it is not valid JSON"); sys.exit()
if not isinstance(d, dict) or d.get("component") != "ade-cli" or d.get("version") != sys.argv[2]:
    print("!it is not the manifest of ade-cli %s" % sys.argv[2]); sys.exit()
for f in d.get("files") if isinstance(d.get("files"), list) else []:
    if isinstance(f, dict) and f.get("name") == "ade" and isinstance(f.get("sha256"), str) and re.fullmatch(r"[0-9a-f]{64}", f["sha256"]):
        print(f["sha256"]); sys.exit()
print("!it names no sha256 for ade")' "$tmp/release.json" "$version" 2> /dev/null || true)"
    case "$want" in "!"*|"") die "the release.json of ade $ref is not valid (${want#!}); nothing installed" ;; esac
    got="$( (shasum -a 256 "$script" 2> /dev/null || sha256sum "$script") | cut -d' ' -f1)"
    [ "$got" = "$want" ] || die "the download of ade $ref does not match its sha256 in release.json; nothing installed"
  fi
fi
mkdir -p "$prefix/bin"
sed "s/^ADE_VERSION=\"\"/ADE_VERSION=\"$version\"/" "$script" > "$prefix/bin/ade.tmp"
chmod +x "$prefix/bin/ade.tmp" && mv "$prefix/bin/ade.tmp" "$prefix/bin/ade"
echo "installed ade $version to $prefix/bin/ade"
case ":$PATH:" in *":$prefix/bin:"*) ;; *) echo "add $prefix/bin to your PATH (in ~/.zshrc or ~/.bashrc: export PATH=\"$prefix/bin:\$PATH\")" ;; esac
# A15: the tools ade needs (git, python3, tmux, gh, gitleaks, bun). The new ade checks them; a missing one is installed
# (Homebrew or apt; bun from its own release, sha256 checked) only after a yes typed at this terminal; piped or without a
# terminal it only names them.
if [ -t 1 ] && { : < /dev/tty; } 2> /dev/null; then ADE_NO_UPDATE_CHECK=1 "$prefix/bin/ade" setup --tools required < /dev/tty || true
else ADE_NO_UPDATE_CHECK=1 "$prefix/bin/ade" setup --tools required < /dev/null | grep -v '^tools: everything' || true; fi
