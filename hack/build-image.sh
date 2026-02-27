#!/usr/bin/env bash
set -eux

echo
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <repo> <tag>"
  echo "Example: $0 local lttng"
  exit 2
fi

repo="$1"
tag="$2"

echo "Start build images, Repo: ${repo}, Tag: ${tag}"
echo
for dir in ts-*; do
    # The avatar service is Python (not JVM) and frequently breaks due to upstream
    # base image / wheel availability changes (e.g., python:3 moving to 3.14).
    # For LTTng JVM tracing, it is safe to skip.
    if [[ "$tag" == "lttng" && "$dir" == "ts-avatar-service" ]]; then
        echo "skip ${dir} (non-JVM service, not needed for LTTng)"
        continue
    fi
    if [[ -d $dir ]]; then
        if [[ -f "$dir/Dockerfile" ]]; then
            echo "build ${dir}"
            docker build -t "${repo}"/"${dir}" "$dir"
            docker tag "${repo}"/"${dir}":latest "${repo}"/"${dir}":"${tag}"
        fi
    fi
done
