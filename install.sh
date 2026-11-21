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
fi
mkdir -p "$prefix/bin"
sed "s/^ADE_VERSION=\"\"/ADE_VERSION=\"$version\"/" "$script" > "$prefix/bin/ade.tmp"
chmod +x "$prefix/bin/ade.tmp" && mv "$prefix/bin/ade.tmp" "$prefix/bin/ade"
echo "installed ade $version to $prefix/bin/ade"
case ":$PATH:" in *":$prefix/bin:"*) ;; *) echo "add $prefix/bin to your PATH (in ~/.zshrc or ~/.bashrc: export PATH=\"$prefix/bin:\$PATH\")" ;; esac
