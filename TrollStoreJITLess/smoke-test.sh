#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
dependencies="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/lc-trollstore-dependencies"
mkdir -p "$dependencies"
if [ ! -d "$dependencies/TrollStore/.git" ]; then
    git clone --no-checkout https://github.com/opa334/TrollStore.git "$dependencies/TrollStore"
fi
git -C "$dependencies/TrollStore" checkout --detach 88424f683b2a08f34a3f88985f790f97d84ce1df
git -C "$dependencies/TrollStore" submodule update --init ChOma
source_dir="$dependencies/TrollStore/Exploits/fastPathSign/src"
choma="$dependencies/TrollStore/ChOma/src"
work="$dependencies/smoke"
framework_dir="$PWD/OpenSSL/Frameworks/OpenSSL.xcframework/macos-arm64_x86_64"
mkdir -p "$work/include" "$work/fixtures"
ln -sfn "$framework_dir/OpenSSL.framework/Headers" "$work/include/openssl"
common=(-arch arm64 -isysroot "$(xcrun --sdk macosx --show-sdk-path)" -I"$choma" -I"$source_dir" -I"$work/include" -IZSign -IZSign/common -F"$framework_dir" -Wno-deprecated-declarations)
for file in "$choma/"*.c "$source_dir/coretrust_bug.c" TrollStoreJITLess/Signer.m TrollStoreJITLess/smoke-main.m; do
    xcrun --sdk macosx clang "${common[@]}" -fobjc-arc -include libkern/OSByteOrder.h -c "$file" -o "$work/$(basename "$file").o"
done
xcrun --sdk macosx clang++ -IZSign -IZSign/common "${common[@]}" -std=c++17 -fobjc-arc \
    ZSign/zsign.mm ZSign/Utils.mm ZSign/*.cpp ZSign/common/*.cpp "$work/"*.o \
    -framework Foundation -framework Security -framework OpenSSL -lz \
    -Wl,-rpath,"$framework_dir" -o "$work/smoke"
printf 'int main(void) { return 0; }\n' > "$work/fixture.c"
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
    -miphoneos-version-min=15.0 -Wl,-no_adhoc_codesign "$work/fixture.c" -o "$work/fixtures/Guest"
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
    -miphoneos-version-min=15.0 -dynamiclib -Wl,-no_adhoc_codesign "$work/fixture.c" -o "$work/fixtures/Framework.dylib"
printf 'resource unchanged\n' > "$work/fixtures/resource.txt"
for attempt in 1 2; do
    "$work/smoke" "$work/fixtures"
    python3 TrollStoreJITLess/verify-signatures.py "$work/fixtures/Guest" "$work/fixtures/Framework.dylib"
done
test "$(cat "$work/fixtures/resource.txt")" = 'resource unchanged'
echo 'PASS: actual ZSign + CoreTrust pipeline on ARM64 iOS executable and dylib, including re-signing'
