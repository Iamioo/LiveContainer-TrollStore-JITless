#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
destination="${1:?Pass the destination Frameworks directory}"
dependencies="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/lc-trollstore-dependencies"
mkdir -p "$dependencies" "$destination"
if [ ! -d "$dependencies/TrollStore/.git" ]; then
    git clone --no-checkout https://github.com/opa334/TrollStore.git "$dependencies/TrollStore"
fi
git -C "$dependencies/TrollStore" checkout --detach 88424f683b2a08f34a3f88985f790f97d84ce1df
git -C "$dependencies/TrollStore" submodule update --init ChOma
source_dir="$dependencies/TrollStore/Exploits/fastPathSign/src"
choma="$dependencies/TrollStore/ChOma/src"
framework_dir="$PWD/OpenSSL/Frameworks/OpenSSL.xcframework/ios-arm64"
mkdir -p "$dependencies/include"
ln -sfn "$framework_dir/OpenSSL.framework/Headers" "$dependencies/include/openssl"
xcrun --sdk iphoneos clang -dynamiclib -arch arm64 -miphoneos-version-min=15.0 \
    -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
    -fobjc-arc -fvisibility=hidden -Wno-deprecated-declarations \
    -include libkern/OSByteOrder.h -I"$choma" -I"$source_dir" -I"$dependencies/include" \
    -F"$framework_dir" -framework Foundation -framework Security -framework OpenSSL \
    -Wl,-install_name,@rpath/LCTrollStoreSigner.dylib \
    TrollStoreJITLess/Signer.m "$source_dir/coretrust_bug.c" "$choma/"*.c \
    -o "$destination/LCTrollStoreSigner.dylib"
# Include the exact upstream sources and licenses with every build artifact.
mkdir -p "$destination/../TrollStoreSignerSources"
cp -R "$dependencies/TrollStore/Exploits/fastPathSign" "$destination/../TrollStoreSignerSources/"
cp -R "$dependencies/TrollStore/ChOma/src" "$destination/../TrollStoreSignerSources/ChOma"
cp "$dependencies/TrollStore/LICENSE" "$destination/../TrollStoreSignerSources/TrollStore-LICENSE"
cp "$dependencies/TrollStore/ChOma/LICENSE" "$destination/../TrollStoreSignerSources/ChOma-LICENSE"
