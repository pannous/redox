#!/bin/bash
set -e

SRC="/opt/other/redox/rust/target/aarch64-unknown-redox-clif/release/deps"
SYSROOT="/opt/other/redox/share/sysroot"
LIBDIR="$SYSROOT/lib/rustlib/aarch64-unknown-redox/lib"

# Clean and create
rm -rf "$SYSROOT"
mkdir -p "$LIBDIR"

# Copy all Jan 15 12:47 rlibs (the most recent build set)
echo "Copying rlibs from rustc build..."
for f in $(ls -la "$SRC"/*.rlib 2>/dev/null | grep "Jan 15 12:47" | awk '{print $NF}'); do
    cp "$f" "$LIBDIR/"
done

echo "Copied $(ls "$LIBDIR"/*.rlib | wc -l) rlib files"
echo ""
echo "Key files:"
ls -la "$LIBDIR"/lib{core,alloc,std,compiler_builtins,panic_abort}*.rlib 2>/dev/null || echo "Some files missing"
echo ""
echo "Sysroot created at: $SYSROOT"
