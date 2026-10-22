#!/bin/sh
# Lädt die FairPlay-Implementierung (playfair, GPL-3) aus UxPlay in das Projekt.
# Ohne diese Dateien können iPads den AirPlay-Schlüsselaustausch nicht abschließen.
#
# Fester Commit, damit der Build reproduzierbar bleibt.
set -eu

UXPLAY_REPO="https://github.com/FDH2/UxPlay.git"
UXPLAY_COMMIT="b29411ffe30eb6b62b755af5ce6a03b2a25c2371"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Totalreflexion/FairPlay"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

git -C "$TMP" init -q
git -C "$TMP" remote add origin "$UXPLAY_REPO"
git -C "$TMP" fetch -q --depth 1 origin "$UXPLAY_COMMIT"
git -C "$TMP" checkout -q FETCH_HEAD

mkdir -p "$DEST/playfair"
cp "$TMP/lib/fairplay_playfair.c" "$DEST/"
for f in hand_garble.c modified_md5.c omg_hax.c omg_hax.h playfair.c playfair.h sap_hash.c LICENSE.md; do
    cp "$TMP/lib/playfair/$f" "$DEST/playfair/"
done

echo "FairPlay-Quellen nach $DEST kopiert (UxPlay $UXPLAY_COMMIT)."
