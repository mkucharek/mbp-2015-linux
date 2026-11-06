#!/bin/bash
# Closes two gaps in a network DNS filter (e.g. Cloudflare for Families, 1.1.1.3) on this laptop:
#   1. Firefox's DNS over HTTPS, which skips the network's DNS: turned off and locked by a system policy
#   2. YouTube, which DNS filters leave alone: Restricted Mode forced through /etc/hosts,
#      the DNS method Google documents. Applies to every account on the laptop.
# Usage (as root):
#   sudo bash web-filter.sh             # install, YouTube strict
#   sudo bash web-filter.sh moderate    # install, YouTube moderate
#   sudo bash web-filter.sh remove      # undo both
# Restart Firefox afterwards. Check: about:policies, and https://www.youtube.com/check_content_restrictions
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo"; exit 1; }
MODE=${1:-strict}
[[ "$MODE" == strict || "$MODE" == moderate || "$MODE" == remove ]] || { echo "Usage: sudo bash $0 [strict|moderate|remove]"; exit 1; }

POLICY=/etc/firefox/policies/policies.json
POLICY_JSON='{
  "policies": {
    "DNSOverHTTPS": {
      "Enabled": false,
      "Locked": true
    }
  }
}'
HOSTS=/etc/hosts
BEGIN='# BEGIN web-filter.sh: YouTube Restricted Mode'
END='# END web-filter.sh'
# The domains Google lists for enforcing Restricted Mode through DNS
YT_DOMAINS="www.youtube.com m.youtube.com youtubei.googleapis.com youtube.googleapis.com www.youtube-nocookie.com"

# Start clean: drop our hosts block, and the policy file only if it's exactly ours
sed -i "/^$BEGIN/,/^$END/d" "$HOSTS"
if [ -f "$POLICY" ] && [ "$(cat "$POLICY")" = "$POLICY_JSON" ]; then
    rm -f "$POLICY"
fi
if [ "$MODE" = remove ]; then
    resolvectl flush-caches 2>/dev/null || true
    echo "Removed the YouTube hosts entries and the Firefox DoH policy. Restart Firefox."
    exit 0
fi

# 1. Firefox: no DNS over HTTPS, and the setting is locked
if [ -f "$POLICY" ]; then
    echo "$POLICY exists and isn't ours; add this to its \"policies\" object by hand:"
    echo '  "DNSOverHTTPS": { "Enabled": false, "Locked": true }'
else
    install -d -m755 "$(dirname "$POLICY")"
    printf '%s\n' "$POLICY_JSON" > "$POLICY"
    chmod 644 "$POLICY"
fi

# 2. YouTube Restricted Mode: the addresses of restrict.youtube.com (strict) or restrictmoderate.youtube.com
if [ "$MODE" = strict ]; then V4=216.239.38.120; V6=2001:4860:4802:32::78
else                         V4=216.239.38.119; V6=2001:4860:4802:32::77; fi
{
    echo "$BEGIN ($MODE)"
    echo "$V4 $YT_DOMAINS"
    echo "$V6 $YT_DOMAINS"
    echo "$END"
} >> "$HOSTS"
resolvectl flush-caches 2>/dev/null || true

echo "== Firefox policy"; cat "$POLICY"
echo "== YouTube ($MODE)"; getent ahostsv4 www.youtube.com | head -1
echo "Restart Firefox, then check about:policies and https://www.youtube.com/check_content_restrictions"
