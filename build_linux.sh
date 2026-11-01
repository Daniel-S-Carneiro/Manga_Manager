#!/usr/bin/env bash
# ==============================================================================
# Script: build_linux.sh
# Objetivo: Compilar o pacote Linux no clone Git do WSL, no MESMO commit do
#           repositório do Windows (chamado pelo build_installer.cmd)
# Uso: bash build_linux.sh <commit> <branch> <pasta_destino_do_pacote>
# ==============================================================================
set -euo pipefail

erro() {
  echo "ERRO: $*" >&2
  exit 1
}

[ $# -eq 3 ] || erro "uso: bash build_linux.sh <commit> <branch> <pasta_destino>"

COMMIT="$1"
BRANCH="$2"
DESTINO="$3"

CLONE="$HOME/StudioProjects/manga_manager"
FLUTTER="$HOME/flutter/bin/flutter"
PACOTE="MangaManager_Linux_x64.tar.gz"
# Pasta deste script = repositório do Windows (/mnt/c/...)
WIN_REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[ -d "$CLONE/.git" ] || erro "clone Git não encontrado em $CLONE"
[ -x "$FLUTTER" ] || erro "Flutter do Linux não encontrado em $FLUTTER"

cd "$CLONE"

# Remote 'win' aponta para o repositório do Windows (não passa pelo GitHub)
if ! git remote get-url win >/dev/null 2>&1; then
  git remote add win "$WIN_REPO"
fi

[ -z "$(git status --porcelain)" ] ||
  erro "o clone do WSL tem alterações não commitadas ($CLONE)"

echo "Sincronizando o clone do WSL com o Windows (branch $BRANCH)..."
git fetch -q win
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git switch -q "$BRANCH"
else
  git switch -q -c "$BRANCH" --track "win/$BRANCH"
fi
git merge -q --ff-only "win/$BRANCH" ||
  erro "a branch $BRANCH do WSL tem commits que o Windows não tem"

# Se o WSL tiver commits a mais, o merge acima não falha: esta checagem pega
[ "$(git rev-parse HEAD)" = "$COMMIT" ] ||
  erro "o WSL ficou em $(git rev-parse --short HEAD), mas o Windows está em ${COMMIT:0:7}"

echo "Compilando o commit ${COMMIT:0:7}..."
"$FLUTTER" build linux --release

mkdir -p "$DESTINO"
tar -czf "$DESTINO/$PACOTE" -C build/linux/x64/release bundle
echo "Pacote gerado: $DESTINO/$PACOTE"
