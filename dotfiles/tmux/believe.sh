#!/usr/bin/env bash

SESSION=believe
TOP_DIR="${HOME}/Tech/Bespoke/beall/believe"

tmux new-session -d -s $SESSION -c "${TOP_DIR}" -n 'up'
tmux new-window -t $SESSION:1 -c "${TOP_DIR}" -n 'git'
tmux new-window -t $SESSION:2 -c "${TOP_DIR}" -n 'run'
tmux new-window -t $SESSION:3 -c "${TOP_DIR}" -n 'test'

tmux select-window -t $SESSION:1
tmux split-window -h -c "${TOP_DIR}"
tmux select-pane -L

tmux select-window -t $SESSION:0

