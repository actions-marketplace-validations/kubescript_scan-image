#!/usr/bin/env bash
# Runs Trivy through Docker (no install on the runner), scanning the image from
# the local Docker daemon. Inputs come as environment variables from action.yml.
set -euo pipefail

fail() { echo "::error::$1"; exit 1; }

command -v docker >/dev/null || fail "Docker not found on the runner"
[ -n "$IMAGE" ] || fail "image is required"
command -v jq >/dev/null || fail "jq not found on the runner"

if [ -n "$REGISTRY_USERNAME" ]; then
  [ -n "$REGISTRY_PASSWORD" ] || fail "registry-username requires registry-password"
  # Registry = first path segment when it looks like a host; otherwise Docker Hub
  registry="docker.io"
  first="${IMAGE%%/*}"
  if [ "$first" != "$IMAGE" ]; then
    case "$first" in *.*|*:*|localhost) registry="$first" ;; esac
  fi
  echo "$REGISTRY_PASSWORD" | docker login "$registry" -u "$REGISTRY_USERNAME" --password-stdin >/dev/null
fi

if [ "$PULL" == "true" ]; then
  docker pull --quiet "$IMAGE" >/dev/null
fi

work=$(mktemp -d "$RUNNER_TEMP/scan-image.XXXXXX")
cache="$RUNNER_TEMP/scan-image-cache"
mkdir -p "$cache"

trivy() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$cache:/root/.cache/trivy" \
    -v "$work:/out" \
    -v "$GITHUB_WORKSPACE:/workspace:ro" \
    "aquasec/trivy:$TRIVY_VERSION" "$@"
}

args=(image --quiet --scanners "$SCANNERS" --severity "$SEVERITY" --format json --output /out/report.json)
[ "$IGNORE_UNFIXED" == "true" ] && args+=(--ignore-unfixed)
if [ -n "$IGNORE_FILE" ]; then
  [ -f "$GITHUB_WORKSPACE/$IGNORE_FILE" ] || fail "ignore-file '$IGNORE_FILE' not found"
  args+=(--ignorefile "/workspace/$IGNORE_FILE")
fi

trivy "${args[@]}" "$IMAGE"

count() {
  jq "[.Results[]? | (.Vulnerabilities // [])[], (.Secrets // [])[] | select($1)] | length" "$work/report.json"
}
total=$(count 'true')
critical=$(count '.Severity == "CRITICAL"')
high=$(count '.Severity == "HIGH"')

{
  echo "findings=$total"
  echo "critical=$critical"
  echo "high=$high"
} >> "$GITHUB_OUTPUT"

if [ -n "$OUTPUT" ]; then
  mkdir -p "$(dirname "$GITHUB_WORKSPACE/$OUTPUT")"
  cp "$work/report.json" "$GITHUB_WORKSPACE/$OUTPUT"
  echo "report=$OUTPUT" >> "$GITHUB_OUTPUT"
fi

if [ "$SUMMARY" == "true" ]; then
  {
    echo "### Image scan: \`$IMAGE\`"
    echo
    if [ "$total" -eq 0 ]; then
      echo "No findings ($SEVERITY$([ "$IGNORE_UNFIXED" == "true" ] && echo ", with fix available"))."
    else
      echo "**$total** finding(s): CRITICAL $critical, HIGH $high ($SEVERITY$([ "$IGNORE_UNFIXED" == "true" ] && echo ", with fix available"))."
      echo
      trivy convert --quiet --format table --table-mode detailed /out/report.json > "$work/table.txt"
      echo '```'
      # The job summary accepts up to 1 MiB per step
      if [ "$(wc -c < "$work/table.txt")" -gt 900000 ]; then
        head -c 900000 "$work/table.txt"
        echo
        echo "... truncated: set output to keep the full JSON report"
      else
        cat "$work/table.txt"
      fi
      echo '```'
    fi
  } >> "$GITHUB_STEP_SUMMARY"
fi

rm -rf "$work"

if [ "$total" -gt 0 ]; then
  msg="$total finding(s) in $IMAGE (CRITICAL $critical, HIGH $high). See the job summary."
  if [ "$FAIL_ON_FINDINGS" == "true" ]; then
    echo "::error title=Image scan::$msg"
    exit 1
  fi
  echo "::warning title=Image scan::$msg"
fi
