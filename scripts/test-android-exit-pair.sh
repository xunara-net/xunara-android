#!/bin/sh
set -eu
umask 077
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
core=${XUNARA_CLIENT_SOURCE:-$root/../xunara-client}
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
adb=$sdk/platform-tools/adb

if [ "${1:-}" = --fixture ]; then
    directory=$2
    [ "$(readlink /proc/self/ns/user)" != "$(readlink /proc/1/ns/user)" ] || exit 1
    ip link set lo up
    pids=''
    cleanup_fixture() { for process in $pids; do kill "$process" 2>/dev/null || :; done; wait 2>/dev/null || :; }
    trap cleanup_fixture EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    XUNARA_TEST_ANDROID_PAIR=true "$core/target/compat-fixture" -mode fixture -dir "$directory" >"$directory/fixture.log" 2>&1 & pids="$pids $!"
    for port in 18080 18081; do
        case "$port" in 18080) target=8080;; 18081) target=8081;; esac
        "$core/target/compat-fixture" -mode proxy -listen "127.0.0.1:$port" -target "127.0.0.1:$target" >"$directory/proxy-$port.log" 2>&1 & pids="$pids $!"
    done
    attempt=0
    until [ -s "$directory/auth-key" ]; do attempt=$((attempt+1)); [ "$attempt" -lt 100 ] || exit 1; sleep 0.1; done
    touch "$directory/fixture-ready"
    wait
fi

exit_serial=${1:-emulator-5580}
client_serial=${2:-emulator-5582}
[ "$exit_serial" != "$client_serial" ] || { echo '需要两个不同的专用模拟器。' >&2; exit 1; }
for serial in "$exit_serial" "$client_serial"; do
    case "$serial" in emulator-*) :;; *) echo '不得操作物理手机。' >&2; exit 1;; esac
    [ "$("$adb" -s "$serial" get-state)" = device ] || exit 1
    [ "$("$adb" -s "$serial" shell id -u | tr -d '\r')" = 2000 ] || { echo '出口业务探针必须使用普通 shell UID；请先对专用模拟器执行 adb unroot。' >&2; exit 1; }
    [ "$("$adb" -s "$serial" shell getprop ro.product.cpu.abi | tr -d '\r')" = x86_64 ] || { echo '本专项探针只用于 x86_64 模拟器。' >&2; exit 1; }
    for port in 18080 18081; do
        if "$adb" -s "$serial" reverse --list | grep -q "tcp:$port "; then echo '已有反向端口映射，拒绝覆盖。' >&2; exit 1; fi
    done
done
for program in flutter socat unshare nsenter curl ip jq node ss; do command -v "$program" >/dev/null || { echo "缺少 $program" >&2; exit 1; }; done
[ -x "$core/target/compat-web-probe" ] || { echo '请先用 CGO_ENABLED=0 构建 tests/compat 到 target/compat-web-probe。' >&2; exit 1; }
for port in 18080 18081; do [ -z "$(ss -H -ltn "sport = :$port")" ] || { echo '测试端口已占用。' >&2; exit 1; }; done
directory=$(mktemp -d)
pids=''
cleanup() {
    outcome=$?
    for serial in "$exit_serial" "$client_serial"; do
        "$adb" -s "$serial" exec-out run-as net.xunara.android cat cache/exit-pair-status >"$directory/$serial-final.json" 2>/dev/null || :
        if [ -f "$directory/$serial-installed" ]; then
            "$adb" -s "$serial" shell am force-stop net.xunara.android >/dev/null 2>&1 || :
            "$adb" -s "$serial" shell "run-as net.xunara.android sh -c 'for file in cache/exit-pair-*; do if [ -f \"\$file\" ]; then rm \"\$file\"; fi; done'" >/dev/null 2>&1 || outcome=1
        fi
        if [ -f "$directory/$serial-probe-installed" ]; then "$adb" -s "$serial" shell rm /data/local/tmp/xunara-exit-pair-probe >/dev/null 2>&1 || outcome=1; fi
        if [ -s "$directory/$serial-profile.xml" ]; then
            "$adb" -s "$serial" shell "run-as net.xunara.android sh -c 'cat > shared_prefs/profile.xml; if [ -f shared_prefs/profile.xml.bak ]; then rm shared_prefs/profile.xml.bak; fi'" <"$directory/$serial-profile.xml" >/dev/null 2>&1 || outcome=1
        fi
        if [ -f "$directory/$serial-installed" ]; then "$adb" -s "$serial" install -r -d "$directory/$serial-original.apk" >/dev/null 2>&1 || outcome=1; fi
        for port in 18080 18081; do "$adb" -s "$serial" reverse --remove "tcp:$port" >/dev/null 2>&1 || :; done
    done
    for process in $pids; do kill "$process" 2>/dev/null || :; done
    wait 2>/dev/null || :
    printf '双安卓私有测试记录：%s\n' "$directory"
    exit "$outcome"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cd "$root"
flutter build apk --debug --target integration_test/exit_pair_test.dart --target-platform android-x64 >"$directory/build.log" 2>&1
certificate() { "$sdk/build-tools/36.0.0/apksigner" verify --print-certs "$1" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p'; }
expected_certificate=$(certificate build/app/outputs/flutter-apk/app-debug.apk)
[ -n "$expected_certificate" ] || exit 1
for serial in "$exit_serial" "$client_serial"; do
    original=$("$adb" -s "$serial" shell pm path net.xunara.android | sed -n 's/^package://p' | tr -d '\r')
    [ -n "$original" ] || { echo '需要已安装应用的专用模拟器以验证无损升级。' >&2; exit 1; }
    "$adb" -s "$serial" pull "$original" "$directory/$serial-original.apk" >/dev/null
    [ "$(certificate "$directory/$serial-original.apk")" = "$expected_certificate" ] || {
        echo '原应用签名不同，请新建专用模拟器；不得卸载或清除原账号数据。' >&2; exit 1;
    }
done
unshare -Urn sh "$root/scripts/test-android-exit-pair.sh" --fixture "$directory" >"$directory/namespace.log" 2>&1 & namespace=$!; pids="$pids $namespace"
attempt=0
until [ -f "$directory/fixture-ready" ]; do attempt=$((attempt+1)); [ "$attempt" -lt 100 ] || exit 1; sleep 0.2; done
for port in 18080 18081; do
    case "$port" in 18080) target=8080;; 18081) target=8081;; esac
    socat "TCP4-LISTEN:$port,bind=127.0.0.1,reuseaddr,fork" "EXEC:sh '$root/scripts/test-proxy-connection.sh' $namespace $target" >"$directory/host-$port.log" 2>&1 & pids="$pids $!"
done
for serial in "$exit_serial" "$client_serial"; do
    "$adb" -s "$serial" shell am force-stop net.xunara.android
    "$adb" -s "$serial" install -r -d build/app/outputs/flutter-apk/app-debug.apk >/dev/null
    touch "$directory/$serial-installed"
    "$adb" -s "$serial" exec-out run-as net.xunara.android cat shared_prefs/profile.xml >"$directory/$serial-profile.xml"
    "$adb" -s "$serial" shell "run-as net.xunara.android sh -c 'for file in cache/exit-pair-*; do if [ -f \"\$file\" ]; then rm \"\$file\"; fi; done'"
    if [ "$serial" = "$exit_serial" ]; then role=exit; else role=client; fi
    printf '{"role":"%s"}' "$role" | "$adb" -s "$serial" shell "run-as net.xunara.android sh -c 'umask 077; cat > cache/exit-pair-settings'"
    "$adb" -s "$serial" shell "run-as net.xunara.android sh -c 'umask 077; cat > cache/exit-pair-auth-key'" <"$directory/auth-key"
    for port in 18080 18081; do "$adb" -s "$serial" reverse "tcp:$port" "tcp:$port" >/dev/null; done
    flutter test integration_test/exit_pair_test.dart -d "$serial" --no-uninstall --timeout 10m >"$directory/$serial-integration.log" 2>&1 & pids="$pids $!"
done
wait_marker() {
    serial=$1
    marker=$2
    attempt=0
    until "$adb" -s "$serial" shell run-as net.xunara.android test -s "cache/exit-pair-$marker" >/dev/null 2>&1; do
        attempt=$((attempt+1)); [ "$attempt" -lt 180 ] || { echo "阶段超时：$serial $marker" >&2; exit 1; }
        window=$("$adb" -s "$serial" shell 'uiautomator dump /data/local/tmp/xunara-pair-window.xml >/dev/null 2>&1; cat /data/local/tmp/xunara-pair-window.xml' 2>/dev/null || :)
        if printf '%s' "$window" | grep -q 'package="com.android.vpndialogs"'; then
            point=$(printf '%s' "$window" | sed -n 's/.*resource-id="android:id\/button1"[^>]*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p')
            if [ -n "$point" ]; then
                horizontal=$(printf '%s' "$point" | awk '{printf "%d", ($1+$3)/2}')
                vertical=$(printf '%s' "$point" | awk '{printf "%d", ($2+$4)/2}')
                "$adb" -s "$serial" shell input tap "$horizontal" "$vertical"
            fi
        fi
        sleep 0.3
    done
}
wait_marker "$exit_serial" registered
curl --noproxy '*' --max-time 5 -fsS -X POST 'http://127.0.0.1:18080/_test/exit?host=android-pair-exit' >"$directory/approved.json"
wait_marker "$exit_serial" ready
wait_marker "$client_serial" ready
printf 'PASS 两台独立安卓身份、真实 TUN、批准出口与出口 DNS 就绪\n'
snapshot() { "$adb" -s "$1" exec-out run-as net.xunara.android cat cache/exit-pair-status; }
snapshot "$client_serial" >"$directory/client-ready.json"
dns_ip=$(jq -er '.status.dns.address' "$directory/client-ready.json")
http_probe() { "$adb" -s "$client_serial" shell "printf 'GET /cdn-cgi/trace HTTP/1.1\r\nHost: one.one.one.one\r\nConnection: close\r\n\r\n' | nc -w 12 -q 3 1.1.1.1 80"; }
http_probe >"$directory/public-ip-http.log"
grep -q '^HTTP/1.[01] ' "$directory/public-ip-http.log"
printf 'PASS 普通 UID 经安卓出口直接访问公网 IPv4 / HTTP\n'
dns_query() {
    protocol=$1
    expected=$2
    wire=$(node -e 'const labels="cloudflare.com".split(".").flatMap(label=>[Buffer.from([label.length]),Buffer.from(label)]);const wire=Buffer.concat([Buffer.from("123401000001000000000000","hex"),...labels,Buffer.from([0,0,1,0,1])]);const length=Buffer.alloc(2);length.writeUInt16BE(wire.length);process.stdout.write((process.argv[1]==="tcp"?Buffer.concat([length,wire]):wire).toString("base64"));' "$protocol")
    if [ "$protocol" = udp ]; then mode=-u; else mode=''; fi
    "$adb" -s "$client_serial" shell "printf '%s' '$wire' | base64 -d | nc $mode -w 12 -W 12 -q 12 '$dns_ip' 53" >"$directory/dns-$expected-$protocol.bin"
    node "$root/scripts/check-dns-response.cjs" "$directory/dns-$expected-$protocol.bin" "$protocol" "$expected"
}
dns_query udp ANSWER
dns_query tcp ANSWER
printf 'PASS 普通 UID 的公网 DNS UDP/TCP 经 WireGuard peerapi 与安卓出口解析\n'
"$adb" -s "$client_serial" shell test ! -e /data/local/tmp/xunara-exit-pair-probe
touch "$directory/$client_serial-probe-installed"
"$adb" -s "$client_serial" push "$core/target/compat-web-probe" /data/local/tmp/xunara-exit-pair-probe >/dev/null
"$adb" -s "$client_serial" shell chmod 700 /data/local/tmp/xunara-exit-pair-probe
"$adb" -s "$client_serial" shell "SSL_CERT_DIR=/apex/com.android.conscrypt/cacerts:/system/etc/security/cacerts /data/local/tmp/xunara-exit-pair-probe -mode web-probe -listen '$dns_ip:53'" >"$directory/public-https.log"
grep -q '^PASS verified HTTPS status=200 bytes=' "$directory/public-https.log"
printf 'PASS 普通 UID 经安卓出口解析域名并取得真实 HTTPS 页面，证书链与主机名校验通过\n'
snapshot "$exit_serial" >"$directory/exit-forwarded.json"
jq -e '.status.forwarding.active and .status.receive_stats.decoded_packets > 0 and .status.bytes_sent > 0' "$directory/exit-forwarded.json" >/dev/null
curl --noproxy '*' --max-time 5 -fsS -X POST 'http://127.0.0.1:18080/_test/exit?host=android-pair-exit&revoke=1' >"$directory/revoked.json"
attempt=0
while :; do
    snapshot "$client_serial" >"$directory/client-revoked.json"
    jq -e '.status.exit_node.available == false and .phase == "connected"' "$directory/client-revoked.json" >/dev/null && break
    attempt=$((attempt+1)); [ "$attempt" -lt 150 ] || exit 1; sleep 0.2
done
dns_query udp SERVFAIL
http_probe >"$directory/revoked-http.log" || :
if grep -q '^HTTP/1.[01] ' "$directory/revoked-http.log"; then echo '出口撤销后泄露公网请求。' >&2; exit 1; fi
snapshot "$client_serial" >"$directory/client-final.json"
[ "$(jq -r .generation "$directory/client-ready.json")" = "$(jq -r .generation "$directory/client-final.json")" ] || { echo '出口撤销触发了错误的物理切网。' >&2; exit 1; }
printf 'PASS 出口撤销后 DNS 失败关闭、公网不直连且没有错误重建 VPN\n'
for serial in "$exit_serial" "$client_serial"; do "$adb" -s "$serial" shell run-as net.xunara.android touch cache/exit-pair-finish; done
for serial in "$exit_serial" "$client_serial"; do
    attempt=0
    until grep -q 'All tests passed!' "$directory/$serial-integration.log"; do attempt=$((attempt+1)); [ "$attempt" -lt 60 ] || exit 1; sleep 0.5; done
done
