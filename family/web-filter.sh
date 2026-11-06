#!/bin/bash
# Closes gaps in a network DNS filter (e.g. Cloudflare for Families, 1.1.1.3) on this laptop,
# for every account:
#   1. Firefox's DNS over HTTPS, which skips the network's DNS: turned off and locked by a system policy
#   2. Ads: the same policy force-installs uBlock Origin in every Firefox profile, private windows
#      included; it can't be removed or disabled from Firefox. Its filter lists are set at every
#      Firefox start: uBO's defaults, plus Polish lists recommended at
#      https://majkiit.github.io/polish-ads-filter/ : Polish ads (POL-0), scam/phishing domains
#      (CERT.PL POL-3, KAD), and cookie banners (EasyList/uBO Cookie Notices + Polish RODO list)
#   3. YouTube, which DNS filters leave alone: Restricted Mode forced through /etc/hosts,
#      the DNS method Google documents
# Usage (as root):
#   sudo bash web-filter.sh             # install, YouTube strict
#   sudo bash web-filter.sh moderate    # install, YouTube moderate
#   sudo bash web-filter.sh remove      # undo all of it
# Restart Firefox afterwards. Check: about:policies, about:addons, and
# https://www.youtube.com/check_content_restrictions
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
    },
    "ExtensionSettings": {
      "uBlock0@raymondhill.net": {
        "installation_mode": "force_installed",
        "install_url": "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi",
        "private_browsing": true
      }
    },
    "3rdparty": {
      "Extensions": {
        "uBlock0@raymondhill.net": {
          "toOverwrite": {
            "filterLists": [
              "user-filters",
              "ublock-filters",
              "ublock-badware",
              "ublock-privacy",
              "ublock-unbreak",
              "ublock-quick-fixes",
              "easylist",
              "easyprivacy",
              "urlhaus-1",
              "plowe-0",
              "POL-0",
              "POL-3",
              "https://raw.githubusercontent.com/FiltersHeroes/KAD/master/KAD.txt",
              "fanboy-cookiemonster",
              "ublock-cookies-easylist",
              "https://raw.githubusercontent.com/MajkiIT/polish-ads-filter/master/cookies_filters/adblock_cookies.txt"
            ]
          }
        }
      }
    }
  }
}'
# What earlier versions of this script wrote, so a re-run can replace it
POLICY_JSON_V1='{
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

# Start clean: drop our hosts block, and the policy file only if this script wrote it
sed -i "/^$BEGIN/,/^$END/d" "$HOSTS"
if [ -f "$POLICY" ]; then
    current=$(cat "$POLICY")
    if [ "$current" = "$POLICY_JSON" ] || [ "$current" = "$POLICY_JSON_V1" ]; then
        rm -f "$POLICY"
    fi
fi
if [ "$MODE" = remove ]; then
    resolvectl flush-caches 2>/dev/null || true
    echo "Removed the YouTube hosts entries and the Firefox policy (DoH lock, uBlock Origin). Restart Firefox."
    echo "uBlock Origin stays in existing profiles as a normal add-on; remove it in about:addons if wanted."
    exit 0
fi

# 1+2. Firefox policy: no DNS over HTTPS (locked), uBlock Origin force-installed
if [ -f "$POLICY" ]; then
    echo "$POLICY exists and isn't ours; merge this into its \"policies\" object by hand:"
    printf '%s\n' "$POLICY_JSON"
else
    install -d -m755 "$(dirname "$POLICY")"
    printf '%s\n' "$POLICY_JSON" > "$POLICY"
    chmod 644 "$POLICY"
fi

# 3. YouTube Restricted Mode: the addresses of restrict.youtube.com (strict) or restrictmoderate.youtube.com
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
echo "Restart Firefox, then check about:policies, about:addons and https://www.youtube.com/check_content_restrictions"
