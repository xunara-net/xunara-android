#!/bin/sh
set -eu
case "${3:-tcp}" in
    tcp) exec nsenter -t "$1" -U -n --preserve-credentials socat STDIO "TCP4:127.0.0.1:$2";;
    udp) exec nsenter -t "$1" -U -n --preserve-credentials socat -T 3 STDIO "UDP4:127.0.0.1:$2";;
    *) exit 1;;
esac
