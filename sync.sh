#!/bin/sh
# Refresh the repo's copies from the working folders, then review with `git status` and commit.
# The working folders stay where the tools expect them: OIP keeps its project open from its own folder,
# and `naut run` runs in the Nautilus project folder.
set -e
cd "$(dirname "$0")"
NAUT="${NAUT_SRC:-$HOME/PLC/MyNautilus/Projects/FinalPracticumOIP}"
OIP="${OIP_SRC:-$HOME/Documents/Open Industry Project/Spring2026_Final_Practicum_Modbus}"
rsync -a --delete --exclude .git --exclude .DS_Store --exclude __pycache__ "$NAUT/" nautilus/
rsync -a --delete --exclude .git --exclude .DS_Store "$OIP/" oip/
echo "synced from $NAUT and $OIP"
