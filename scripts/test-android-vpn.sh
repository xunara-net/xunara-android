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
wifi_before=$("$adb" -s "$serial" shell settings get global wifi_on | tr -d '\r')
data_before=$("$adb" -s "$serial" shell settings get global mobile_data | tr -d '\r')
case "$wifi_before:$data_before" in 0:0|0:1|1:0|1:1) :;; *) echo '无法读取模拟器网络开关，拒绝测试。' >&2; exit 1;; esac
cleanup() {
    for process in $pids; do kill "$process" 2>/dev/null || :; done
    wait 2>/dev/null || :
    for port in 18080 18081; do "$adb" -s "$serial" reverse --remove "tcp:$port" >/dev/null 2>&1 || :; done
    "$adb" -s "$serial" shell am force-stop net.xunara.android >/dev/null 2>&1 || :
    if [ "$wifi_before" = 1 ]; then "$adb" -s "$serial" shell svc wifi enable; else "$adb" -s "$serial" shell svc wifi disable; fi
    if [ "$data_before" = 1 ]; then "$adb" -s "$serial" shell svc data enable; else "$adb" -s "$serial" shell svc data disable; fi
    printf '私有测试日志：%s\n' "$directory"
}
trap cleanup EXIT INT TERM
"$adb" -s "$serial" shell 'svc wifi enable; svc data enable'
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
wait_marker() {
    attempt=0
    until "$adb" -s "$serial" shell run-as net.xunara.android cat "cache/integration-$1" >/dev/null 2>&1; do
        attempt=$((attempt+1)); [ "$attempt" -lt 300 ] || { cat "$directory/integration.log"; exit 1; }
        kill -0 "$integration" 2>/dev/null || { cat "$directory/integration.log"; exit 1; }
        if [ $((attempt % 10)) = 1 ]; then
            "$adb" -s "$serial" shell run-as net.xunara.android cat cache/integration-progress >"$directory/phase-$1-$attempt.json" 2>/dev/null || :
            "$adb" -s "$serial" shell dumpsys connectivity >"$directory/networks-$1-$attempt.log"
        fi
        sleep 0.2
    done
}
wait_marker ping-timeout-ready
# 仅在本轮新建的隔离网络 namespace 内暂停回包，绝不修改宿主机 sysctl。
nsenter -t "$namespace" -U -n --preserve-credentials sh -c 'echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_all'
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-ping-timeout-enabled
wait_marker ping-timeout-complete
nsenter -t "$namespace" -U -n --preserve-credentials sh -c 'echo 0 > /proc/sys/net/ipv4/icmp_echo_ignore_all'
wait_marker roaming-ready
printf 'PASS 内核 ICMP 诊断的真实 DERP 回包、RTT 与不可见 peer 拒绝\n'
printf 'PASS 对端忽略 ICMP 时真实超时，不伪报连通\n'
"$adb" -s "$serial" shell 'svc data disable; svc wifi disable'
wait_marker offline
attempt=0
while :; do
    "$adb" -s "$serial" shell dumpsys connectivity >"$directory/offline-connectivity.log"
    grep -q 'Current Networks:' "$directory/offline-connectivity.log" || { echo '无法读取 Android 网络状态' >&2; exit 1; }
    if ! grep -q '^[[:space:]]*NetworkAgentInfo.*ni{VPN' "$directory/offline-connectivity.log"; then break; fi
    attempt=$((attempt+1)); [ "$attempt" -lt 30 ] || { echo '断网后旧 VPN 网络未移除' >&2; exit 1; }
    sleep 0.2
done
printf 'PASS 断网进入等待状态且真实旧 TUN 已关闭\n'
"$adb" -s "$serial" shell svc wifi enable
wait_marker auto-connected
fetch "$router_ip" 8088 >"$directory/roaming-tcp.log"
grep -q xunara-core-ok "$directory/roaming-tcp.log"
fetch 192.168.90.2 8088 >"$directory/roaming-subnet.log"
grep -q xunara-core-ok "$directory/roaming-subnet.log"
printf 'PASS Wi-Fi 恢复自动重连，身份不变且真实 TCP / 子网恢复\n'
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-roaming-finish
wait_marker mobile-ready
"$adb" -s "$serial" shell 'svc data enable; svc wifi disable'
wait_marker mobile-connected
fetch "$router_ip" 8088 >"$directory/mobile-tcp.log"
grep -q xunara-core-ok "$directory/mobile-tcp.log"
printf 'PASS Wi-Fi → 模拟移动网络自动重连与真实 TCP\n'
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-mobile-finish
wait_marker cancel-ready
"$adb" -s "$serial" shell 'svc data disable; svc wifi disable'
wait_marker cancel-stopped
"$adb" -s "$serial" shell 'svc wifi enable; svc data enable'
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-network-restored
wait "$integration"
if grep -q 'DATA RACE' "$directory/fixture.log"; then echo 'fixture 检测到竞态' >&2; exit 1; fi
printf 'PASS 主动断开取消自动重连、流量计数与不再提供 Auth Key 的身份重连\n'
cat "$directory/integration.log"
