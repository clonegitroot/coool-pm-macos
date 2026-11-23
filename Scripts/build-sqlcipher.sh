#!/bin/sh
# Build the pinned upstream SQLCipher amalgamation against Apple's CommonCrypto.
set -eu
cd "$(dirname "$0")/.."
version=4.10.0
sha=676b636ff01fef2fa437b8749e73bd3bec4ba15041b7df9821a188ba52aab241
root="$PWD/.build/sqlcipher-$version-$(uname -m)"
if [ -f "$root/sqlcipher.o" ] && [ -f "$root/include/module.modulemap" ]; then
    exit 0
fi
mkdir -p "$root"
tmp=$(mktemp -d /tmp/coool-sqlcipher.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
archive="$root/source.tar.gz"
if [ ! -f "$archive" ]; then
    curl --fail --location --show-error --silent --retry 2 "https://codeload.github.com/sqlcipher/sqlcipher/tar.gz/refs/tags/v$version" -o "$tmp/source.tar.gz"
    echo "$sha  $tmp/source.tar.gz" | shasum -a 256 -c -
    mv "$tmp/source.tar.gz" "$archive"
fi
echo "$sha  $archive" | shasum -a 256 -c -
cd "$tmp"
tar -xzf "$archive" --strip-components=1
./configure --with-tempstore=yes --disable-shared >configure.log
make sqlite3.c >amalgamation.log
xcrun clang -O2 -fvisibility=hidden -mmacosx-version-min=14.0 -DSQLITE_HAS_CODEC \
    -DSQLCIPHER_CRYPTO_CC -DSQLITE_EXTRA_INIT=sqlcipher_extra_init \
    -DSQLITE_EXTRA_SHUTDOWN=sqlcipher_extra_shutdown -DSQLITE_TEMP_STORE=3 \
    -DSQLITE_THREADSAFE=1 -DSQLITE_DQS=0 -DSQLITE_OMIT_LOAD_EXTENSION \
    -c sqlite3.c -o sqlcipher.o
mkdir -p "$root/include"
cp sqlite3.h "$root/include/sqlite3.h"
echo 'module CooolSQLCipher { header "shim.h" export * }' > "$root/include/module.modulemap"
printf '#define SQLITE_HAS_CODEC 1\n#include "sqlite3.h"\n' > "$root/include/shim.h"
mv sqlcipher.o "$root/"
