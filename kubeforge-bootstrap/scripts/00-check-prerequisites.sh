#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/_common.sh"

log 'Checking Git Bash / Windows prerequisites...'
case "$(uname -s)" in
  MINGW*|MSYS*) ;;
  *) fail 'This starter kit targets Windows Git Bash (MINGW/MSYS).';;
esac

for program in docker kind kubectl curl sha256sum cygpath powershell.exe; do
  require "$program"
done

docker info >/dev/null 2>&1 || fail 'Docker is not running. Start Docker Desktop with Linux containers.'

docker --version
kind --version
kubectl version --client
log 'Docker is running and prerequisites are available.'
log 'Tip: allocate at least ~8 GB RAM to Docker/WSL if possible (12+ GB preferable).'
