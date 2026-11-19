#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
: "${LOGGING_DEPLOY_HOST:?Set the SSH destination user@host}"
: "${LOGGING_DEPLOY_DIR:?Set the remote installation directory}"
[[ $LOGGING_DEPLOY_HOST =~ ^[A-Za-z0-9_.@-]+$ ]] || {
  echo 'Invalid LOGGING_DEPLOY_HOST' >&2; exit 2;
}
[[ $LOGGING_DEPLOY_DIR =~ ^/?[A-Za-z0-9_./-]+$ && $LOGGING_DEPLOY_DIR != *..* &&
   $LOGGING_DEPLOY_DIR != / && $LOGGING_DEPLOY_DIR != . ]] || {
  echo 'Invalid LOGGING_DEPLOY_DIR' >&2; exit 2;
}
rsync -av --exclude='.git/' --exclude='generated/' "$ROOT/" "$LOGGING_DEPLOY_HOST:$LOGGING_DEPLOY_DIR/"
echo "Sources synced; deploy from $LOGGING_DEPLOY_DIR on the Docker host."
