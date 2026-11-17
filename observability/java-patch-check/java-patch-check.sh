#!/usr/bin/env bash
# Daily check for Java builds newer than the ones that were current when
# Oracle's 2026-11-17 Java SE patch (and CVE-2026-114938) landed. Ubuntu,
# Temurin and Red Hat ship their own fixes later, on their own schedules.
#
# Writes node_exporter textfile metrics; JavaPatchAvailable in
# kube-prometheus-stack-values.yaml posts to Slack when any source has a
# newer build. Baselines live in /etc/java-patch-check.env: after rolling a
# patched build out, set its baseline to the new version to clear the alert.
# Ubuntu packages clear on their own once upgraded.
set -uo pipefail

OUT_DIR=/var/lib/node_exporter/textfile
# shellcheck source=java-patch-check.env
. /etc/java-patch-check.env

ok=1
metrics=()

emit() { # source component current latest
  local v=1
  [ "$3" = "$4" ] && v=0
  metrics+=("java_patch_available{source=\"$1\",component=\"$2\",current=\"$3\",latest=\"$4\"} $v")
}

json_field() { # python expression over d, reads JSON on stdin
  python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"
}

# Ubuntu: newer candidate than installed. Refresh the lists first so a
# release from today is seen.
apt-get update -qq >/dev/null 2>&1 || ok=0
for pkg in $UBUNTU_PACKAGES; do
  pol=$(apt-cache policy "$pkg" 2>/dev/null)
  cur=$(awk '/Installed:/ {print $2}' <<<"$pol")
  new=$(awk '/Candidate:/ {print $2}' <<<"$pol")
  if [ -n "$cur" ] && [ "$cur" != "(none)" ] && [ -n "$new" ]; then
    emit ubuntu "$pkg" "$cur" "$new"
  else
    ok=0
  fi
done

# Temurin: the latest GA build of each feature release vs. the baseline.
for pair in $TEMURIN_BASELINES; do
  feature=${pair%%=*} base=${pair#*=}
  latest=$(curl -fsS --max-time 30 \
    "https://api.adoptium.net/v3/assets/latest/${feature}/hotspot?architecture=x64&image_type=jre&os=linux" |
    json_field "d[0]['version']['openjdk_version']") && [ -n "$latest" ] &&
    emit temurin "jdk${feature}" "$base" "$latest" || ok=0
done

# Keycloak: a new release is the only way its Red Hat JDK gets patched.
latest=$(curl -fsS --max-time 30 -H 'Accept: application/vnd.github+json' \
  https://api.github.com/repos/keycloak/keycloak/releases/latest |
  json_field "d['tag_name']") && [ -n "$latest" ] &&
  emit keycloak keycloak "$KEYCLOAK_BASELINE" "$latest" || ok=0

tmp=$(mktemp "$OUT_DIR/.java_patch.XXXXXX")
{
  echo "# HELP java_patch_available 1 when a Java build newer than the baseline is published."
  echo "# TYPE java_patch_available gauge"
  printf '%s\n' "${metrics[@]}"
  echo "# HELP java_patch_check_success 1 when every lookup in the last run succeeded."
  echo "# TYPE java_patch_check_success gauge"
  echo "java_patch_check_success $ok"
  echo "# HELP java_patch_check_last_run_timestamp_seconds When the check last ran."
  echo "# TYPE java_patch_check_last_run_timestamp_seconds gauge"
  echo "java_patch_check_last_run_timestamp_seconds $(date +%s)"
} >"$tmp"
chmod 0644 "$tmp"
mv "$tmp" "$OUT_DIR/java_patch.prom"

printf '%s\n' "${metrics[@]}" "success=$ok"
