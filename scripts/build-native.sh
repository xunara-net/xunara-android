#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
ndk=${ANDROID_NDK_HOME:-$sdk/ndk/29.0.14206865}
toolchain=$ndk/toolchains/llvm/prebuilt/linux-x86_64/bin
[ -x "$toolchain/aarch64-linux-android26-clang" ] || { echo '需要 Linux x86_64 Android NDK 29.0.14206865；可通过 ANDROID_NDK_HOME 指定。' >&2; exit 1; }
cd "$root/native"
for abi in ${XUNARA_ANDROID_ABIS:-arm64-v8a x86_64}; do
    case "$abi" in
        arm64-v8a) target=aarch64-linux-android; compiler=aarch64-linux-android26-clang;;
        x86_64) target=x86_64-linux-android; compiler=x86_64-linux-android26-clang;;
        *) echo "不支持的 ABI: $abi" >&2; exit 1;;
    esac
    upper=$(printf '%s' "$target" | tr '[:lower:]-' '[:upper:]_')
    env "CC_$target=$toolchain/$compiler" "AR_$target=$toolchain/llvm-ar" \
        "CARGO_TARGET_${upper}_LINKER=$toolchain/$compiler" \
        cargo build --locked --release --lib --target "$target"
    mkdir -p "$root/android/app/src/main/jniLibs/$abi"
    cp "target/$target/release/libxunara_android.so" "$root/android/app/src/main/jniLibs/$abi/"
done
sh "$root/scripts/collect-native-notices.sh"
