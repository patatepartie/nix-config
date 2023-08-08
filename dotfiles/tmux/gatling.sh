#!/usr/bin/env bash

SESSION=gatling
TOP_DIR="${HOME}/Tech/Bespoke/proto/gatling"

tmux new-session -d -s $SESSION -c "${TOP_DIR}" -n 'run'
tmux new-window -t $SESSION:1 -c "${TOP_DIR}" -n 'git'

tmux select-window -t $SESSION:1
tmux split-window -h -c "${TOP_DIR}"
tmux select-pane -L

tmux select-window -t $SESSION:0

