#!/bin/bash
# install.sh [PREFIX]: installs ade into PREFIX/bin (default ~/.local/bin), with VERSION stamped in
set -eu
here="$(cd "$(dirname "$0")" && pwd)"; prefix="${1:-${PREFIX:-$HOME/.local}}"
version="$(cat "$here/VERSION")"
mkdir -p "$prefix/bin"
sed "s/^ADE_VERSION=\"\"/ADE_VERSION=\"$version\"/" "$here/ade" > "$prefix/bin/ade.tmp"
chmod +x "$prefix/bin/ade.tmp" && mv "$prefix/bin/ade.tmp" "$prefix/bin/ade"
echo "installed ade $version to $prefix/bin/ade"
case ":$PATH:" in *":$prefix/bin:"*) ;; *) echo "add $prefix/bin to your PATH" ;; esac
