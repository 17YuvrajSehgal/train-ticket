#!/bin/bash
# Build ts-verification-code-service from source and deploy to KIND so the cluster
# uses the fixed image (cached font, ThreadLocalRandom, fewer draw calls, correct
# verify return value, RestTemplate timeouts) instead of pre-built
# codewisdom/ts-verification-code-service:1.0.0.
# Run from repo root: bash hack/deploy/build-and-deploy-verifycode.sh

set -e
TT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$TT_ROOT"
NAMESPACE="${1:-train-ticket}"
KIND_NAME="${KIND_CLUSTER_NAME:-train-ticket}"
IMAGE_NAME="ts-verification-code-service:local"

echo "Building ts-verification-code-service JAR..."
mvn -pl ts-verification-code-service -am package -DskipTests -q

echo "Building Docker image $IMAGE_NAME..."
docker build -t "$IMAGE_NAME" -f ts-verification-code-service/Dockerfile ts-verification-code-service

echo "Loading image into KIND cluster ($KIND_NAME)..."
kind load docker-image "$IMAGE_NAME" --name "$KIND_NAME"

echo "Updating ts-verification-code-service deployment in namespace $NAMESPACE to use $IMAGE_NAME..."
kubectl set image deployment/ts-verification-code-service ts-verification-code-service="$IMAGE_NAME" -n "$NAMESPACE"
kubectl rollout restart deployment/ts-verification-code-service -n "$NAMESPACE"

echo "Waiting for rollout..."
kubectl rollout status deployment/ts-verification-code-service -n "$NAMESPACE" --timeout=120s

echo "Done. ts-verification-code-service is now running the image built from source (with performance fixes)."
