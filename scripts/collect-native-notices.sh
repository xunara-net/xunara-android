#!/bin/sh
set -eu
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
temporary=$(mktemp -d)
cleanup() { find "$temporary" -type f -delete; rmdir "$temporary"; }
trap cleanup EXIT INT TERM
cd "$root/native"
cargo metadata --locked --format-version 1 --filter-platform aarch64-linux-android >"$temporary/metadata.json"
jq -r '[.resolve.nodes[].id] as $used | .packages[] | select(.id as $id | $used | index($id)) | select(.source != null and .name != "xunara-client") | [.name,.version,.manifest_path,.license] | @tsv' \
    "$temporary/metadata.json" >"$temporary/packages.tsv"
: >"$temporary/licenses.ndjson"
while IFS="$(printf '\t')" read -r package version manifest expression; do
    directory=$(dirname "$manifest")
    find "$directory" -maxdepth 2 -type f \( -iname 'license*' -o -iname 'licence*' -o -iname 'copyright*' -o -iname 'copying*' -o -iname 'notice*' \) | LC_ALL=C sort >"$temporary/files"
    : >"$temporary/notice.txt"
    while IFS= read -r file; do
        printf '\n--- %s ---\n\n' "${file#"$directory/"}" >>"$temporary/notice.txt"
        cat "$file" >>"$temporary/notice.txt"
    done <"$temporary/files"
    case "$package" in
        jni|jni-macros) if [ "$version" = 0.22.4 ]; then cat "$root/native/notices/jni-rs-0.22.4.txt" >>"$temporary/notice.txt"; fi;;
        ts_capabilityversion|ts_control_noise|ts_hexdump|ts_keys|ts_noise) cat "$root/native/notices/tailscale-rs-0.6.1.txt" >>"$temporary/notice.txt";;
        boringtun|jni-sys-macros|cesu8) cat "$root/native/notices/$package-$version.txt" >>"$temporary/notice.txt";;
    esac
    [ -s "$temporary/notice.txt" ] || { echo "缺少 $package $version 上游声明" >&2; exit 1; }
    jq -n --arg name "$package" --arg version "$version" --arg license "$expression" --rawfile text "$temporary/notice.txt" \
        '{name:$name,version:$version,license:$license,text:$text}' >>"$temporary/licenses.ndjson"
done <"$temporary/packages.tsv"
mkdir -p "$root/assets"
jq -s 'sort_by(.name,.version)' "$temporary/licenses.ndjson" >"$root/assets/native_licenses.json"
