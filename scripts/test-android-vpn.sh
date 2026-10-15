#!/bin/sh
set -eu
umask 077
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
core=${XUNARA_CLIENT_SOURCE:-$root/../xunara-client}
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
adb=$sdk/platform-tools/adb
serial=${1:-emulator-5580}
case "$serial" in emulator-*) :;; *) echo '自动授权测试只允许专用模拟器，不能操作用户真机。' >&2; exit 1;; esac
for program in flutter socat unshare nsenter curl ip jq; do command -v "$program" >/dev/null || { echo "缺少 $program" >&2; exit 1; }; done
if [ ! -x "$core/target/compat-fixture" ] || [ ! -x "$core/target/debug/xunara-client" ]; then
    echo '请先构建 xunara-client 与 tests/compat Go fixture。' >&2; exit 1;
fi
for port in 18080 18081; do
    if "$adb" -s "$serial" reverse --list | grep -q "tcp:$port "; then echo "模拟器已有 $port 反向映射，拒绝覆盖。" >&2; exit 1; fi
done
directory=$(mktemp -d)
pids=''
cleanup() {
    for process in $pids; do kill "$process" 2>/dev/null || :; done
    wait 2>/dev/null || :
    for port in 18080 18081; do "$adb" -s "$serial" reverse --remove "tcp:$port" >/dev/null 2>&1 || :; done
    printf '私有测试日志：%s\n' "$directory"
}
trap cleanup EXIT INT TERM
unshare -Urn sh "$root/scripts/test-fixture-netns.sh" "$directory" "$core" >"$directory/namespace.log" 2>&1 & namespace=$!; pids="$pids $namespace"
attempt=0
until [ -f "$directory/namespace-ready" ]; do attempt=$((attempt+1)); [ "$attempt" -lt 100 ] || exit 1; sleep 0.2; done
for port in 18080 18081; do
    case "$port" in 18080) target=8080;; 18081) target=8081;; esac
    socat "TCP4-LISTEN:$port,bind=127.0.0.1,reuseaddr,fork" "EXEC:sh '$root/scripts/test-proxy-connection.sh' $namespace $target" >"$directory/host-proxy-$port.log" 2>&1 & pids="$pids $!"
    "$adb" -s "$serial" reverse "tcp:$port" "tcp:$port" >/dev/null
done
curl --noproxy '*' --max-time 4 -fsS 'http://127.0.0.1:18080/_test/node?host=rust-router' >/dev/null
cd "$root"
flutter build apk --debug --target integration_test/vpn_test.dart --target-platform android-x64 >"$directory/build.log" 2>&1
"$adb" -s "$serial" install -r build/app/outputs/flutter-apk/app-debug.apk >/dev/null
# 密钥只从 stdin 写入测试应用私有缓存，既不出现在 argv，也不编译进 APK。
"$adb" -s "$serial" shell "run-as net.xunara.android sh -c 'umask 077; cat > cache/integration-auth-key'" <"$directory/auth-key"
flutter test integration_test/vpn_test.dart -d "$serial" --timeout 6m >"$directory/integration.log" 2>&1 & integration=$!; pids="$pids $integration"
attempt=0
until "$adb" -s "$serial" shell run-as net.xunara.android cat cache/integration-connected >"$directory/android-connected.json" 2>/dev/null; do
    attempt=$((attempt+1)); [ "$attempt" -lt 100 ] || { cat "$directory/integration.log"; exit 1; }
    kill -0 "$integration" 2>/dev/null || { cat "$directory/integration.log"; exit 1; }
    # 只点专用模拟器中系统 VPN 授权框的正向按钮，不对任意窗口盲点。
    window=$("$adb" -s "$serial" shell 'uiautomator dump /data/local/tmp/xunara-window.xml >/dev/null 2>&1; cat /data/local/tmp/xunara-window.xml' 2>/dev/null || :)
    if printf '%s' "$window" | grep -q 'package="com.android.vpndialogs"'; then
        bounds=$(printf '%s' "$window" | sed -n 's/.*resource-id="android:id\/button1"[^>]*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\]".*/\1 \2 \3 \4/p')
        if [ -n "$bounds" ]; then
            horizontal=$(printf '%s' "$bounds" | awk '{printf "%d", ($1+$3)/2}')
            vertical=$(printf '%s' "$bounds" | awk '{printf "%d", ($2+$4)/2}')
            "$adb" -s "$serial" shell input tap "$horizontal" "$vertical"
        fi
    fi
    sleep 0.5
done
printf 'PASS Android VpnService + TS2021 / Noise 注册与真实 TUN\n'
router_ip=$(curl --noproxy '*' --max-time 3 -fsS 'http://127.0.0.1:18080/_test/node?host=rust-router' | jq -r .ipv4)
"$adb" -s "$serial" shell ping -c 2 -W 4 "$router_ip" >"$directory/ping.log"
printf 'PASS Android 其他 UID 的加密 ICMP 经真实 TUN\n'
fetch() { "$adb" -s "$serial" shell "printf 'GET / HTTP/1.0\r\n\r\n' | nc -w 8 $1 $2"; }
fetch "$router_ip" 8088 >"$directory/tcp.log"
grep -q xunara-core-ok "$directory/tcp.log"
printf 'PASS Android ↔ Rust TCP 经证书指纹校验的 DERP\n'
if fetch "$router_ip" 8089 2>/dev/null | grep -q xunara-core-ok; then echo 'ACL 意外放行禁止端口' >&2; exit 1; fi
printf 'PASS 拒绝的 ACL 端口\n'
fetch 192.168.90.2 8088 >"$directory/subnet.log"
grep -q xunara-core-ok "$directory/subnet.log"
printf 'PASS Android 访问已审批远程子网\n'
sleep 2
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-finish
wait "$integration"
if grep -q 'DATA RACE' "$directory/fixture.log"; then echo 'fixture 检测到竞态' >&2; exit 1; fi
printf 'PASS 流量计数、断开与不再提供 Auth Key 的身份重连\n'
cat "$directory/integration.log"
