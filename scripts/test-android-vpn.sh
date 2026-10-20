#!/bin/sh
set -eu
umask 077
root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
core=${XUNARA_CLIENT_SOURCE:-$root/../xunara-client}
sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}
adb=$sdk/platform-tools/adb
serial=${1:-emulator-5580}
public_dns=${XUNARA_TEST_PUBLIC_DNS:-false}
phone_router=${XUNARA_TEST_PHONE_ROUTER:-false}
sharing=${XUNARA_TEST_SHARING:-false}
pause_on_failure=${XUNARA_TEST_PAUSE_ON_FAILURE:-false}
release_apk=${XUNARA_TEST_RELEASE_APK:-}
release_smoke=false
if [ -n "$release_apk" ]; then
    [ -f "$release_apk" ] || { echo 'Release 安装包不存在' >&2; exit 1; }
    release_smoke=true
fi
case "$pause_on_failure" in true|false) :;; *) echo 'XUNARA_TEST_PAUSE_ON_FAILURE 只能为 true 或 false' >&2; exit 1;; esac
case "$sharing" in true|false) :;; *) echo 'XUNARA_TEST_SHARING 只能为 true 或 false' >&2; exit 1;; esac
case "$phone_router" in true|false) :;; *) echo 'XUNARA_TEST_PHONE_ROUTER 只能为 true 或 false' >&2; exit 1;; esac
case "$public_dns" in true|false) :;; *) echo 'XUNARA_TEST_PUBLIC_DNS 只能为 true 或 false' >&2; exit 1;; esac
case "$serial" in emulator-*) :;; *) echo '自动授权测试只允许专用模拟器，不能操作用户真机。' >&2; exit 1;; esac
[ "$("$adb" -s "$serial" shell id -u | tr -d '\r')" = 2000 ] || { echo 'VPN 业务探针必须使用普通 shell UID；请先对专用模拟器执行 adb unroot。' >&2; exit 1; }
for program in flutter socat unshare nsenter curl ip jq node ss; do command -v "$program" >/dev/null || { echo "缺少 $program" >&2; exit 1; }; done
if [ ! -x "$core/target/compat-fixture" ] || [ ! -x "$core/target/debug/xunara-client" ]; then
    echo '请先构建 xunara-client 与 tests/compat Go fixture。' >&2; exit 1;
fi
ports='18080 18081'
if [ "$sharing" = true ]; then ports="$ports 18082 18083"; fi
for port in $ports; do
    if "$adb" -s "$serial" reverse --list | grep -q "tcp:$port "; then echo "模拟器已有 $port 反向映射，拒绝覆盖。" >&2; exit 1; fi
    [ -z "$(ss -H -ltn "sport = :$port")" ] || { echo "宿主已有 $port 监听，拒绝覆盖。" >&2; exit 1; }
done
directory=$(mktemp -d)
pids=''
wifi_before=$("$adb" -s "$serial" shell settings get global wifi_on | tr -d '\r')
data_before=$("$adb" -s "$serial" shell settings get global mobile_data | tr -d '\r')
case "$wifi_before:$data_before" in 0:0|0:1|1:0|1:1) :;; *) echo '无法读取模拟器网络开关，拒绝测试。' >&2; exit 1;; esac
cleanup() {
    outcome=$?
    restored=true
    if [ "$outcome" != 0 ] && [ "$outcome" != 130 ] && [ "$outcome" != 143 ] && [ "$pause_on_failure" = true ]; then
        printf '失败现场保留 45 秒用于本机诊断（不会将失败改判成功）：%s\n' "$directory"
        sleep 45
    fi
    "$adb" -s "$serial" exec-out run-as net.xunara.android cat cache/integration-runtime-snapshot >"$directory/final-status.json" 2>/dev/null || :
    for process in $pids; do kill "$process" 2>/dev/null || :; done
    wait 2>/dev/null || :
    for port in $ports; do "$adb" -s "$serial" reverse --remove "tcp:$port" >/dev/null 2>&1 || :; done
    "$adb" -s "$serial" shell am force-stop net.xunara.android >/dev/null 2>&1 || :
    if [ -f "$directory/release-installed" ]; then
        "$adb" -s "$serial" install -r -d "$directory/restore-debug.apk" >/dev/null 2>&1 || restored=false
        "$adb" -s "$serial" shell am force-stop net.xunara.android >/dev/null 2>&1 || :
    fi
    if [ -s "$directory/original-profile.xml" ]; then
        "$adb" -s "$serial" shell "run-as net.xunara.android sh -c 'cat > shared_prefs/profile.xml; if [ -f shared_prefs/profile.xml.bak ]; then rm shared_prefs/profile.xml.bak; fi'" <"$directory/original-profile.xml" >/dev/null 2>&1 || restored=false
    fi
    if [ -f "$directory/release-installed" ]; then "$adb" -s "$serial" install -r "$release_apk" >/dev/null 2>&1 || restored=false; fi
    if [ "$wifi_before" = 1 ]; then "$adb" -s "$serial" shell svc wifi enable; else "$adb" -s "$serial" shell svc wifi disable; fi
    if [ "$data_before" = 1 ]; then "$adb" -s "$serial" shell svc data enable; else "$adb" -s "$serial" shell svc data disable; fi
    printf '私有测试日志：%s\n' "$directory"
    if [ "$restored" != true ]; then echo '模拟器原偏好或安装包恢复失败，请查看私有测试目录。' >&2; outcome=1; fi
    exit "$outcome"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"$adb" -s "$serial" shell 'svc wifi enable; svc data enable'
unshare -Urn sh "$root/scripts/test-fixture-netns.sh" "$directory" "$core" >"$directory/namespace.log" 2>&1 & namespace=$!; pids="$pids $namespace"
attempt=0
until [ -f "$directory/namespace-ready" ]; do attempt=$((attempt+1)); [ "$attempt" -lt 100 ] || exit 1; sleep 0.2; done
for port in $ports; do
    case "$port" in 18080) target=8080;; 18081) target=8081;; 18082) target=8082;; 18083) target=8083;; esac
    socat "TCP4-LISTEN:$port,bind=127.0.0.1,reuseaddr,fork" "EXEC:sh '$root/scripts/test-proxy-connection.sh' $namespace $target" >"$directory/host-proxy-$port.log" 2>&1 & pids="$pids $!"
    "$adb" -s "$serial" reverse "tcp:$port" "tcp:$port" >/dev/null
done
curl --noproxy '*' --max-time 4 -fsS 'http://127.0.0.1:18080/_test/node?host=rust-router' >/dev/null
if [ "$phone_router" = true ]; then
    for port in 18088 18089 18090; do
        [ -z "$(ss -H -ltn "sport = :$port")" ] && [ -z "$(ss -H -lun "sport = :$port")" ] || { echo "已有 $port 测试端口，拒绝覆盖" >&2; exit 1; }
        case "$port" in 18088) target=8088;; 18089|18090) target=8089;; esac
        socat "TCP4-LISTEN:$port,bind=127.0.0.1,reuseaddr,fork" "EXEC:sh '$root/scripts/test-proxy-connection.sh' $namespace $target" >"$directory/phone-TCP4-LISTEN-$port.log" 2>&1 & pids="$pids $!"
    done
    socat -T 3 'UDP4-RECVFROM:18088,bind=127.0.0.1,reuseaddr,fork' "EXEC:sh '$root/scripts/test-proxy-connection.sh' $namespace 5353 udp" >"$directory/phone-UDP4-RECVFROM.log" 2>&1 & pids="$pids $!"
fi
cd "$root"
flutter build apk --debug --target integration_test/vpn_test.dart --target-platform android-x64 >"$directory/build.log" 2>&1
# 专用模拟器可能已装 split-per-ABI 预览包；只允许本轮 Debug 测试包降级，保留身份用于升级迁移验收。
"$adb" -s "$serial" install -r -d build/app/outputs/flutter-apk/app-debug.apk >/dev/null
if [ "$release_smoke" = true ]; then cp build/app/outputs/flutter-apk/app-debug.apk "$directory/restore-debug.apk"; fi
"$adb" -s "$serial" shell am force-stop net.xunara.android
"$adb" -s "$serial" shell run-as net.xunara.android test ! -e shared_prefs/profile.xml.bak
"$adb" -s "$serial" exec-out run-as net.xunara.android cat shared_prefs/profile.xml >"$directory/original-profile.xml"
# 崩溃重跑只清理测试缓存，不清除账号配置或机器私钥，也不能误读上次留下的完成标记。
"$adb" -s "$serial" shell "run-as net.xunara.android sh -c 'for file in cache/integration-*; do if [ -f \"\$file\" ]; then rm \"\$file\"; fi; done'"
# 密钥只从 stdin 写入测试应用私有缓存，既不出现在 argv，也不编译进 APK。
"$adb" -s "$serial" shell "run-as net.xunara.android sh -c 'umask 077; cat > cache/integration-auth-key'" <"$directory/auth-key"
"$adb" -s "$serial" shell "run-as net.xunara.android sh -c 'umask 077; cat > cache/integration-second-auth-key'" <"$directory/second-auth-key"
if [ "$sharing" = true ]; then
    for account in recipient outsider same-subject; do
        "$adb" -s "$serial" shell "run-as net.xunara.android sh -c 'umask 077; cat > cache/integration-share-$account-auth-key'" <"$directory/share-$account-auth-key"
    done
fi
flutter test integration_test/vpn_test.dart -d "$serial" --dart-define="XUNARA_TEST_PUBLIC_DNS=$public_dns" --dart-define="XUNARA_TEST_PHONE_ROUTER=$phone_router" --dart-define="XUNARA_TEST_SHARING=$sharing" --dart-define="XUNARA_TEST_RELEASE_SMOKE=$release_smoke" --no-uninstall --timeout 10m >"$directory/integration.log" 2>&1 & integration=$!; pids="$pids $integration"
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
router_ipv6=$(curl --noproxy '*' --max-time 3 -fsS 'http://127.0.0.1:18080/_test/node?host=rust-router' | jq -r .ipv6)
attempt=0
until "$adb" -s "$serial" shell ping -c 2 -W 3 "$router_ip" >"$directory/ping.log"; do
    attempt=$((attempt+1)); [ "$attempt" -lt 4 ] || { cat "$directory/integration.log"; exit 1; }
done
printf 'PASS Android 其他 UID 的加密 ICMP 经真实 TUN\n'
fetch() { "$adb" -s "$serial" shell "printf 'GET / HTTP/1.0\r\n\r\n' | nc -w 8 $1 $2"; }
fetch "$router_ip" 8088 >"$directory/tcp.log"
grep -q xunara-core-ok "$directory/tcp.log"
printf 'PASS Android ↔ Rust TCP 经证书指纹校验的 DERP\n'
"$adb" -s "$serial" shell "printf 'GET / HTTP/1.0\r\n\r\n' | nc -6 -w 8 $router_ipv6 8088" >"$directory/tcp-ipv6.log"
grep -q xunara-core-ok "$directory/tcp-ipv6.log"
printf 'PASS Android 其他 UID 的 IPv6 TCP 经真实 TUN / DERP\n'
if fetch "$router_ip" 8089 2>/dev/null | grep -q xunara-core-ok; then echo 'ACL 意外放行禁止端口' >&2; exit 1; fi
printf 'PASS 拒绝的 ACL 端口\n'
fetch 192.168.90.2 8088 >"$directory/subnet.log"
grep -q xunara-core-ok "$directory/subnet.log"
printf 'PASS Android 访问已审批远程子网\n'
sleep 2
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-finish
wait_marker() {
    attempt=0
    until "$adb" -s "$serial" shell run-as net.xunara.android test -s "cache/integration-$1" >/dev/null 2>&1; do
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
wait_marker routing-only
fetch "$router_ip" 8088 >"$directory/only-tcp.log"
grep -q xunara-core-ok "$directory/only-tcp.log"
printf 'PASS 仅选中 shell UID 的真实 TUN / TCP，原机器身份不变\n'
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-routing-only-verified
wait_marker routing-excluded
if fetch "$router_ip" 8088 2>/dev/null | grep -q xunara-core-ok; then echo '排除应用仍被 VPN 接管' >&2; exit 1; fi
printf 'PASS 排除 shell UID 后无法通过 VPN 访问私有设备\n'
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-routing-excluded-verified
wait_marker routing-restored
fetch "$router_ip" 8088 >"$directory/restored-tcp.log"
grep -q xunara-core-ok "$directory/restored-tcp.log"
fetch 192.168.90.2 8088 >"$directory/restored-subnet.log"
grep -q xunara-core-ok "$directory/restored-subnet.log"
printf 'PASS 所选应用消失时失败关闭，恢复全部应用后 TCP / 子网恢复\n'
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-routing-restored-verified
wait_marker dns-ready
dns_ip=$("$adb" -s "$serial" shell run-as net.xunara.android cat cache/integration-dns-ready | jq -r .dns)
"$adb" -s "$serial" shell ping -c 1 -W 4 rust-router.core.test >"$directory/magicdns-system.log"
grep -F "$router_ip" "$directory/magicdns-system.log" >/dev/null
printf 'PASS Android 系统解析器通过 VPN MagicDNS 解析设备域名\n'
dns_query() {
    encoded=$(node -e 'const name=process.argv[1]; const labels=name.split(".").filter(Boolean).flatMap(label=>[Buffer.from([label.length]),Buffer.from(label)]); const query=Buffer.concat([Buffer.from("123401000001000000000000","hex"),...labels,Buffer.from([0,0,1,0,1])]); if(process.argv[3]==="SECURE")query[3]|=0x20; const prefix=Buffer.alloc(2); prefix.writeUInt16BE(query.length); process.stdout.write((process.argv[2]==="tcp"?Buffer.concat([prefix,query]):query).toString("base64"));' "$1" "$2" "$3")
    case "$2" in udp) mode='-u';; tcp) mode='';; *) exit 1;; esac
    deadline=${XUNARA_DNS_TIMEOUT:-3}
    case "$deadline" in ''|*[!0-9]*) echo 'DNS 超时必须为整数' >&2; exit 1;; esac
    [ "$deadline" -ge 1 ] && [ "$deadline" -le 30 ] || exit 1
    "$adb" -s "$serial" shell "printf '%s' '$encoded' | base64 -d | nc $mode -w "$deadline" -W "$deadline" -q "$deadline" '$dns_ip' 53" >"$directory/dns-$1-$2.bin"
    node "$root/scripts/check-dns-response.cjs" "$directory/dns-$1-$2.bin" "$2" "$3"
}
dns_query rust-router.core.test udp "$router_ip"
dns_query rust-router.core.test tcp "$router_ip"
dns_query external.public.test udp 203.0.113.77
dns_query external.public.test tcp 203.0.113.77
dns_query missing.core.test udp NXDOMAIN
printf 'PASS MagicDNS UDP/TCP、本地域 NXDOMAIN 与经 ACL 子网 DNS 转发\n'
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-dns-verified
if [ "$public_dns" = true ]; then
    wait_marker doh-ready
    dns_ip=$("$adb" -s "$serial" shell run-as net.xunara.android cat cache/integration-doh-ready | jq -r .dns)
    XUNARA_DNS_TIMEOUT=12 dns_query cloudflare.com udp SECURE
    XUNARA_DNS_TIMEOUT=12 dns_query dnssec-failed.org tcp SERVFAIL
    "$adb" -s "$serial" shell ping -c 2 -W 4 rust-router.core.test >"$directory/doh-local-magicdns.log"
    grep -F "$router_ip" "$directory/doh-local-magicdns.log" >/dev/null
    printf 'PASS Android 受保护 socket 的真实 DoH、公网 DNSSEC 信任链、错误签名拒绝与 MagicDNS 保留\n'
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-doh-verified
    wait_marker dot-ready
    dns_ip=$("$adb" -s "$serial" shell run-as net.xunara.android cat cache/integration-dot-ready | jq -r .dns)
    XUNARA_DNS_TIMEOUT=12 dns_query cloudflare.com udp SECURE
    XUNARA_DNS_TIMEOUT=12 dns_query dnssec-failed.org tcp SERVFAIL
    printf 'PASS Android 真实 DoT、完整 DNSSEC 信任链和错误签名拒绝，机器身份不变\n'
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-dot-verified
fi
wait_marker exit-ready
dns_ip=$("$adb" -s "$serial" shell run-as net.xunara.android cat cache/integration-exit-ready | jq -r .dns)
fetch 203.0.113.77 8088 >"$directory/exit-tcp.log"
grep -q xunara-core-ok "$directory/exit-tcp.log"
"$adb" -s "$serial" shell "printf 'GET / HTTP/1.0\r\n\r\n' | nc -6 -w 8 2001:db8::77 8088" >"$directory/exit-ipv6.log"
grep -q xunara-core-ok "$directory/exit-ipv6.log"
dns_query external.public.test udp 203.0.113.77
dns_query external.public.test tcp 203.0.113.77
printf 'PASS 指定官方 tsnet 出口的 IPv4/IPv6 TCP 与 peerapi DNS-over-WireGuard\n'
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-exit-verified
wait_marker exit-revocation-ready
curl --noproxy '*' --max-time 4 -fsS -X POST 'http://127.0.0.1:18080/_test/exit?revoke=1' >"$directory/exit-revoke.json"
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-exit-revocation-sent
wait_marker exit-revoked
"$adb" -s "$serial" shell run-as net.xunara.android cat cache/integration-exit-revoked >"$directory/android-exit-revoked.json"
"$adb" -s "$serial" shell run-as net.xunara.android cat cache/integration-exit-revoked-status >"$directory/exit-revoked-status.json"
if fetch 203.0.113.77 8088 2>/dev/null | grep -q xunara-core-ok; then echo '撤销出口后仍在转发' >&2; exit 1; fi
dns_query external.public.test udp SERVFAIL
fetch "$router_ip" 8088 >"$directory/exit-revoked-private.log"
grep -q xunara-core-ok "$directory/exit-revoked-private.log"
printf 'PASS 出口撤销后保留 VPN、阻止公网与 DNS 回退，私网仍可访问\n'
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-exit-revoked-verified
if [ "$phone_router" = true ]; then
    phone_probe() {
        nsenter -t "$namespace" -U -n --preserve-credentials curl --noproxy '*' --max-time 30 -fsSG --data-urlencode "step=$1" --data-urlencode "ipv6=$phone_ipv6" 'http://127.0.0.1:8099/' >"$directory/phone-$1.json"
    }
    phone_flag() {
        phone_probe "$1"
        jq -e --arg field "$2" '.[$field] == true' "$directory/phone-$1.json" >/dev/null || { cat "$directory/phone-$1.json"; exit 1; }
    }
    wait_marker phone-subnet-ready
    phone_ipv6=$("$adb" -s "$serial" shell ip -6 -o address show dev wlan0 | awk '$3 == "inet6" && $4 ~ /^fec0:/ {split($4, address, "/"); print address[1]; exit}')
    [ -n "$phone_ipv6" ] || { echo '专用模拟器没有 LAN IPv6，不能冒充双栈验收' >&2; exit 1; }
    phone_flag blocked blocked
    printf 'PASS 手机仅广播但尚未批准时，不转发其他设备的流量\n'
    curl --noproxy '*' --max-time 4 -fsS -X POST 'http://127.0.0.1:18080/_test/approve?host=android-integration' >"$directory/phone-subnet-approved.json"
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-phone-approval-sent
    wait_marker phone-subnet-active
    attempt=0
    until phone_probe status && jq -e '.route_all == true and any(.peers[]; .host == "android-integration" and (.allowed | index("10.0.2.0/24")) != null and (.allowed | index("fec0::/64")) != null)' "$directory/phone-status.json" >/dev/null; do
        attempt=$((attempt+1)); [ "$attempt" -lt 80 ] || { cat "$directory/phone-status.json"; exit 1; }; sleep 0.2
    done
    phone_probe subnet
    jq -e '[.tcp4,.tcp6,.udp4,.udp6,.icmp4,.icmp6] | all(. == true)' "$directory/phone-subnet.json" >/dev/null || { cat "$directory/phone-subnet.json"; exit 1; }
    phone_flag denied-port blocked
    printf 'PASS 官方 tsnet 经手机免 Root 转发双栈 TCP / UDP / 真实 ICMP，ACL 禁止端口仍拒绝\n'
    phone_flag hold held
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-phone-hold-sent
    wait_marker phone-hold-visible
    curl --noproxy '*' --max-time 4 -fsS -X POST 'http://127.0.0.1:18080/_test/phone-policy?deny=1' >/dev/null
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-phone-policy-sent
    wait_marker phone-policy-reset
    phone_flag hold-blocked blocked
    phone_flag blocked blocked
    printf 'PASS ACL 撤销后手机关闭原有 TCP 流，新连接也不放行\n'
    curl --noproxy '*' --max-time 4 -fsS -X POST 'http://127.0.0.1:18080/_test/phone-policy' >/dev/null
    sleep 3
    phone_flag hold held
    curl --noproxy '*' --max-time 4 -fsS -X POST 'http://127.0.0.1:18080/_test/approve?host=android-integration&revoke=1' >"$directory/phone-subnet-revoked.json"
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-phone-revocation-sent
    wait_marker phone-subnet-stopped
    phone_flag hold-blocked blocked
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-phone-subnet-verified
    wait_marker phone-exit-ready
    curl --noproxy '*' --max-time 4 -fsS -X POST 'http://127.0.0.1:18080/_test/exit?host=android-integration' >"$directory/phone-exit-approved.json"
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-phone-exit-approval-sent
    wait_marker phone-exit-active
    phone_flag select-exit selected
    phone_probe exit
    jq -e '[.tcp4,.tcp6,.udp4,.udp6,.icmp4,.icmp6] | all(. == true)' "$directory/phone-exit.json" >/dev/null || { cat "$directory/phone-exit.json"; exit 1; }
    phone_flag dns dns
    if "$adb" -s "$serial" shell "nc -6 -z -w 3 $phone_ipv6 18090" >"$directory/phone-physical-refused.log" 2>&1; then
        echo 'IPv6 基线端口已被监听，不能用于验证拨号失败。' >&2; exit 1
    fi
    grep -Fq 'Connection refused' "$directory/phone-physical-refused.log" || { cat "$directory/phone-physical-refused.log"; exit 1; }
    phone_probe family-fallback
    jq -e '.ipv6_rejected == true and .fallback == true' "$directory/phone-family-fallback.json" >/dev/null || { cat "$directory/phone-family-fallback.json"; exit 1; }
    printf 'PASS 不可达 IPv6 不伪报 TCP 成功，真实域名连接自动回退可用 IPv4 出口\n'
    phone_flag hold held
    curl --noproxy '*' --max-time 4 -fsS -X POST 'http://127.0.0.1:18080/_test/exit?host=android-integration&revoke=1' >"$directory/phone-exit-revoked.json"
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-phone-exit-revocation-sent
    wait_marker phone-exit-stopped
    phone_flag hold-blocked blocked
    phone_flag blocked blocked
    printf 'PASS 手机作为双栈出口及 peerapi DNS；撤销默认路由后旧 TCP 被关闭\n'
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-phone-exit-verified
fi
wait_marker second-ready
curl --noproxy '*' --max-time 4 -fsS 'http://127.0.0.1:18080/_test/node?host=android-integration' >"$directory/first-account.json"
curl --noproxy '*' --max-time 4 -fsS 'http://127.0.0.1:18080/_test/node?host=android-second-account' >"$directory/second-account.json"
[ "$(jq -r .id "$directory/first-account.json")" != "$(jq -r .id "$directory/second-account.json")" ]
[ "$(jq -r .user "$directory/first-account.json")" != "$(jq -r .user "$directory/second-account.json")" ]
fetch "$router_ip" 8088 >"$directory/second-account-tcp.log"
grep -q xunara-core-ok "$directory/second-account-tcp.log"
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-second-verified
wait_marker first-restored
fetch "$router_ip" 8088 >"$directory/first-restored-tcp.log"
grep -q xunara-core-ok "$directory/first-restored-tcp.log"
"$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-first-restored-verified
printf 'PASS 同控制器不同账号独立设备与归属，切回原账号无密钥恢复原身份\n'
if [ "$sharing" = true ]; then
    wait_marker share-pending-ready
    curl --noproxy '*' --max-time 4 -fsS -X POST 'http://127.0.0.1:18080/_test/share?step=create' >"$directory/share-created.json"
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-share-created
    wait_marker share-pending-verified
    curl --noproxy '*' --max-time 4 -fsS -X POST 'http://127.0.0.1:18080/_test/share?step=accept' >"$directory/share-accepted.json"
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-share-accepted
    wait_marker share-active
    "$adb" -s "$serial" shell run-as net.xunara.android cat cache/integration-share-active >"$directory/share-active.json"
    shared_ipv4=$(jq -er '.addresses[] | select(contains(":") | not) | split("/")[0]' "$directory/share-active.json")
    shared_ipv6=$(jq -er '.addresses[] | select(contains(":")) | split("/")[0]' "$directory/share-active.json")
    [ "$shared_ipv4" != "$router_ip" ] && [ "$shared_ipv6" != "$router_ipv6" ]
    fetch "$shared_ipv4" 8088 >"$directory/share-tcp4.log"
    grep -q xunara-core-ok "$directory/share-tcp4.log"
    "$adb" -s "$serial" shell "printf 'GET / HTTP/1.0\r\n\r\n' | nc -6 -w 8 $shared_ipv6 8088" >"$directory/share-tcp6.log"
    grep -q xunara-core-ok "$directory/share-tcp6.log"
    if fetch "$shared_ipv4" 8089 2>/dev/null | grep -q xunara-core-ok; then echo '共享越过了源网络 ACL' >&2; exit 1; fi
    if fetch 192.168.90.2 8088 2>/dev/null | grep -q xunara-core-ok; then echo '共享泄露了源网络子网路由' >&2; exit 1; fi
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-share-verified
    printf 'PASS 相同原地址的跨租户设备经双栈 masquerade 通信，ACL 与子网隔离仍生效\n'
    for account in outsider third; do
        wait_marker "share-$account-ready"
        if fetch "$shared_ipv4" 8088 2>/dev/null | grep -q xunara-core-ok; then echo '其他用户或租户访问了未分享的机器' >&2; exit 1; fi
        "$adb" -s "$serial" shell run-as net.xunara.android touch "cache/integration-share-$account-verified"
    done
    wait_marker share-restored
    fetch "$shared_ipv4" 8088 >"$directory/share-restored.log"
    grep -q xunara-core-ok "$directory/share-restored.log"
    curl --noproxy '*' --max-time 4 -fsS -X POST 'http://127.0.0.1:18080/_test/share?step=revoke' >"$directory/share-revoked.json"
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-share-revocation-sent
    wait_marker share-revoked
    if fetch "$shared_ipv4" 8088 2>/dev/null | grep -q xunara-core-ok; then echo '共享撤销后仍能访问机器' >&2; exit 1; fi
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-share-revoked-verified
    wait_marker share-original-restored
    fetch "$router_ip" 8088 >"$directory/share-original.log"
    grep -q xunara-core-ok "$directory/share-original.log"
    "$adb" -s "$serial" shell run-as net.xunara.android touch cache/integration-share-original-verified
    printf 'PASS 待接受不可见、错误用户 / 租户不可接受和访问，撤销生效，多控制器无密钥切回\n'
fi
wait "$integration"
if [ "$release_smoke" = true ]; then
    "$adb" -s "$serial" shell run-as net.xunara.android test -s cache/integration-release-upgrade-ready
    sh "$root/scripts/test-release-upgrade.sh" "$serial" "$release_apk" "$directory" "$router_ip" "$router_ipv6"
fi
for logfile in "$directory"/*.log; do
    if grep -q 'DATA RACE' "$logfile"; then echo 'fixture 检测到竞态' >&2; exit 1; fi
done
printf 'PASS 主动断开取消自动重连、流量计数与不再提供 Auth Key 的身份重连\n'
cat "$directory/integration.log"
