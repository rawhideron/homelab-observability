#!/usr/bin/env bash
# Daily check that the Java this host actually runs is the newest patch
# release of its line. Three sources:
#   ubuntu  installed openjdk packages vs. apt's candidate
#   pod     every JVM running in a Kubernetes pod on this host vs. the latest
#           Temurin GA build of the same feature release
#   kind    the kind CLI and the kindnetd image the Kind cluster runs vs. the
#           latest kind release and kindnetd tag (goodman_reunion #887)
#
# Writes node_exporter textfile metrics; JavaPatchAvailable in
# kube-prometheus-stack-values.yaml posts to Slack while anything is behind.
# Each series clears on its own once the patched package or image is running.
set -uo pipefail

OUT_DIR=/var/lib/node_exporter/textfile
# shellcheck source=java-patch-check.env
. /etc/java-patch-check.env

ok=1
metrics=()
declare -A seen latest_for

emit() { # source component current latest is_behind
  metrics+=("java_patch_available{source=\"$1\",component=\"$2\",current=\"$3\",latest=\"$4\"} $5")
}

# Ubuntu: newer candidate than installed. Refresh the lists first so a
# release from today is seen.
apt-get update -qq >/dev/null 2>&1 || ok=0
for pkg in $UBUNTU_PACKAGES; do
  pol=$(apt-cache policy "$pkg" 2>/dev/null)
  cur=$(awk '/Installed:/ {print $2}' <<<"$pol")
  new=$(awk '/Candidate:/ {print $2}' <<<"$pol")
  if [ -n "$cur" ] && [ "$cur" != "(none)" ] && [ -n "$new" ]; then
    emit ubuntu "$pkg" "$cur" "$new" "$([ "$cur" = "$new" ] && echo 0 || echo 1)"
  else
    ok=0
  fi
done

# Latest Temurin GA version of a feature release, e.g. 21 -> 21.0.13.1.
temurin_latest() {
  curl -fsS --max-time 30 \
    "https://api.adoptium.net/v3/assets/latest/$1/hotspot?architecture=x64&image_type=jre&os=linux" |
    python3 -c "import json,sys; print(json.load(sys.stdin)[0]['version']['openjdk_version'].split('+')[0])"
}

# Pods: find JVMs by executable, keep those in a kubepods cgroup, and read
# the JDK's release file through the process's root. No kubectl exec, so
# images without a shell work too.
hash='[bcdfghjklmnpqrstvwxz2456789]'
for p in /proc/[0-9]*; do
  exe=$(readlink "$p/exe" 2>/dev/null) || continue
  [[ $exe == */bin/java ]] || continue
  grep -q kubepods "$p/cgroup" 2>/dev/null || continue

  ver=$(sed -n 's/^JAVA_VERSION="\(.*\)"/\1/p' "$p/root${exe%/bin/java}/release" 2>/dev/null)
  pod=$(cat "$p/root/etc/hostname" 2>/dev/null)
  if [ -z "$ver" ] || [ -z "$pod" ]; then ok=0; continue; fi
  ns=
  for d in run var/run; do # /var/run is a symlink to /run in most images
    f="$p/root/$d/secrets/kubernetes.io/serviceaccount/namespace"
    [ -r "$f" ] && { ns=$(<"$f"); break; }
  done

  # Name the workload, not the pod, so a Deployment rollout keeps its series:
  # drop the ReplicaSet/DaemonSet suffixes. StatefulSet pods (kafka-0) stay.
  if [[ $pod =~ ^(.+)-${hash}{6,10}-${hash}{5}$ ]] || [[ $pod =~ ^(.+)-${hash}{5}$ ]]; then
    pod=${BASH_REMATCH[1]}
  fi
  component="${ns:-?}/$pod"

  feature=${ver%%.*}
  if [ -z "${latest_for[$feature]+x}" ]; then
    latest_for[$feature]=$(temurin_latest "$feature") || { ok=0; latest_for[$feature]=""; }
  fi
  latest=${latest_for[$feature]}
  [ -n "$latest" ] || { ok=0; continue; }

  # Replicas on the same version share one series.
  [ -n "${seen[$component $ver]+x}" ] && continue
  seen[$component $ver]=1
  behind=0
  [ "$ver" != "$latest" ] && [ "$(printf '%s\n%s\n' "$ver" "$latest" | sort -V | head -1)" = "$ver" ] && behind=1
  emit pod "$component" "$ver" "$latest" "$behind"
done

# kind: kindnetd's critical CVEs (goodman_reunion #887) are suppressed by a
# Trivy ignore until kind ships a fixed image. A newer kind release or
# kindnetd tag means the cluster can be rebuilt onto it and the ignore
# dropped. Each series clears once the host runs the newest of each.
newer() { # current latest -> 1 if latest sorts after current
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$1" ] && echo 1 || echo 0
}
cur=$(kind version 2>/dev/null | awk '{print $2}')
latest=$(curl -fsS --max-time 30 https://api.github.com/repos/kubernetes-sigs/kind/releases/latest |
  python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])")
if [ -n "$cur" ] && [ -n "$latest" ]; then
  emit kind kind "$cur" "$latest" "$(newer "$cur" "$latest")"
else
  ok=0
fi
cur=$(docker exec "$KIND_NODE" crictl ps --name kindnet-cni -o json 2>/dev/null |
  python3 -c "import json,sys; print(json.load(sys.stdin)['containers'][0]['image']['userSpecifiedImage'].rsplit(':', 1)[1])")
latest=$(curl -fsS --max-time 30 'https://hub.docker.com/v2/repositories/kindest/kindnetd/tags?page_size=100' |
  python3 -c "import json,re,sys; print(max(t['name'] for t in json.load(sys.stdin)['results'] if re.fullmatch(r'v[0-9]{8}-[0-9a-f]+', t['name'])))")
if [ -n "$cur" ] && [ -n "$latest" ]; then
  emit kind kube-system/kindnet "$cur" "$latest" "$(newer "$cur" "$latest")"
else
  ok=0
fi

tmp=$(mktemp "$OUT_DIR/.java_patch.XXXXXX")
{
  echo "# HELP java_patch_available 1 when a running/installed Java is older than the latest patch release of its line."
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
