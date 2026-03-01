#!/bin/bash
# Build ts-auth-service from source and deploy to KIND so the cluster uses
# the fixed image (RestTemplate timeouts, no duplicate DB call, etc.) instead
# of the pre-built codewisdom/ts-auth-service:1.0.0.
# Run from repo root: bash hack/deploy/build-and-deploy-auth.sh

set -e
TT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$TT_ROOT"
NAMESPACE="${1:-train-ticket}"
KIND_NAME="${KIND_CLUSTER_NAME:-train-ticket}"
IMAGE_NAME="ts-auth-service:local"

echo "Building ts-auth-service JAR..."
mvn -pl ts-auth-service -am package -DskipTests -q

echo "Building Docker image $IMAGE_NAME..."
docker build -t "$IMAGE_NAME" -f ts-auth-service/Dockerfile ts-auth-service

echo "Loading image into KIND cluster ($KIND_NAME)..."
kind load docker-image "$IMAGE_NAME" --name "$KIND_NAME"

echo "Updating ts-auth-service deployment in namespace $NAMESPACE to use $IMAGE_NAME..."
kubectl set image deployment/ts-auth-service ts-auth-service="$IMAGE_NAME" -n "$NAMESPACE"
kubectl rollout restart deployment/ts-auth-service -n "$NAMESPACE"

echo "Waiting for rollout..."
kubectl rollout status deployment/ts-auth-service -n "$NAMESPACE" --timeout=120s

echo "Done. ts-auth-service is now running the image built from source (with performance fixes)."
