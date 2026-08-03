#!/usr/bin/env bash
set -euo pipefail

missing=0

check() {
  local bin="$1" mac_hint="$2" linux_hint="$3"
  if ! command -v "$bin" >/dev/null 2>&1; then
    missing=1
    echo "MISSING: $bin"
    echo "  macOS:  $mac_hint"
    echo "  Linux:  $linux_hint"
    echo ""
  fi
}

check docker \
  "https://docs.docker.com/desktop/install/mac-install/" \
  "https://docs.docker.com/engine/install/"

check kind \
  "brew install kind" \
  "curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64 && chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind"

check kubectl \
  "brew install kubectl" \
  "curl -LO \"https://dl.k8s.io/release/\$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\" && chmod +x kubectl && sudo mv kubectl /usr/local/bin/"

check helm \
  "brew install helm" \
  "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"

if [ "$missing" -eq 1 ]; then
  echo "Install the missing tools above, then re-run 'make up'."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Docker is installed but the daemon isn't reachable (not running, or you lack permissions)."
  echo "  macOS: start Docker Desktop"
  echo "  Linux: sudo systemctl start docker  (and ensure your user is in the 'docker' group)"
  exit 1
fi

echo "All required tools are present and Docker is running."
