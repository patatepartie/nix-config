#!/usr/bin/env bash

SESSION=github
TOP_DIR="${HOME}/Tech/Bespoke/tools/github"

tmux new-session -d -s $SESSION -c "${TOP_DIR}" -n 'run'
tmux new-window -t $SESSION:1 -c "${TOP_DIR}" -n 'git'

tmux select-window -t $SESSION:0

