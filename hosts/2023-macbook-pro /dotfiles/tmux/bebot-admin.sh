#!/usr/bin/env bash

SESSION="bebot-admin"
TOP_DIR="${HOME}/Tech/Bespoke/beall/bebot-admin"

tmux new-session -d -s $SESSION -c "${TOP_DIR}" -n 'run'
tmux new-window -t $SESSION:2 -c "${TOP_DIR}" -n 'git'
tmux new-window -t $SESSION:3 -c "${TOP_DIR}" -n 'curl'

tmux select-window -t $SESSION:2
tmux split-window -h -c "${TOP_DIR}"
tmux select-pane -L

tmux select-window -t $SESSION:1
