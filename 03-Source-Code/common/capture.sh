#!/bin/bash
# Task G / demo step 6: capture ONE complete request (DNS -> TCP -> TLS -> HTTP) into a .pcap
# that you open in Wireshark.  Run on Mac 4 (client): its DNS query travels over Wi-Fi to Mac 1,
# so the DNS packets are visible. (On Mac 1 the DNS query stays inside the Mac, on loopback.)
#   ./common/capture.sh          -> TLS 1.2 (Certificate message visible in plain text)
#   ./common/capture.sh tls13    -> TLS 1.3 (for comparison: certificate is encrypted)
source "$(dirname "$0")/../lib.sh"

MODE="${1:-tls12}"
PCAP="$EVIDENCE/taskG-flow-$MODE-$(date +%H%M%S).pcap"
TLSOPT=(--tls-max 1.2); [ "$MODE" = tls13 ] && TLSOPT=(--tlsv1.3)

sudo -v || exit 1   # ask for the password now, not while tcpdump is in the background
say "Starting tcpdump on $IFACE (DNS to team servers + HTTPS to the edge)"
sudo tcpdump -i "$IFACE" -n -s 0 -w "$PCAP" \
  "(udp port 53 and host $MAC1_IP) or (tcp port 443 and host $MAC2_IP)" &
sleep 2

say "Flushing DNS cache so a real DNS query is sent"
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder; sleep 1

say "curl -v https://app.$DOMAIN/api/status  (${TLSOPT[*]})"
curl -v "${TLSOPT[@]}" --http1.1 "https://app.$DOMAIN/api/status" 2>&1 | tee "$EVIDENCE/taskG-curl-verbose-$MODE.txt"

sleep 2
sudo pkill -INT -x tcpdump
sleep 1
echo
echo "Saved: $PCAP"
echo "Open it:  open -a Wireshark \"$PCAP\""
echo "Useful Wireshark display filters:"
echo "  dns                       -> query for app.$DOMAIN + answer with Mac 2's IP"
echo "  tcp.flags.syn==1          -> SYN and SYN-ACK of the 3-way handshake"
echo "  tls.handshake             -> ClientHello, ServerHello, Certificate, ..."
echo "  tls.record.content_type==23 -> Application Data (the encrypted HTTP)"
