#!/usr/bin/env bash

SESSION=sisyphus
TOP_DIR="${HOME}/Tech/Bespoke/beall/sisyphus"

tmux new-session -d -s $SESSION -c "${TOP_DIR}" -n 'up'
tmux new-window -t $SESSION:2 -c "${TOP_DIR}" -n 'git'
tmux new-window -t $SESSION:3 -c "${TOP_DIR}" -n 'curl'
tmux new-window -t $SESSION:4 -c "${TOP_DIR}" -n 'run'

tmux select-window -t $SESSION:2
tmux split-window -h -c "${TOP_DIR}"
tmux select-pane -L

tmux select-window -t $SESSION:1
