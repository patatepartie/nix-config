#!/usr/bin/env bash

SESSION=hachi
TOP_DIR="${HOME}/Tech/Bespoke/beall/hachi"

tmux new-session -d -s $SESSION -c "${TOP_DIR}" -n 'up'
tmux new-window -t $SESSION:2 -c "${TOP_DIR}" -n 'git'
tmux new-window -t $SESSION:3 -c "${TOP_DIR}" -n 'curl'
tmux new-window -t $SESSION:4 -c "${TOP_DIR}" -n 'run'
tmux new-window -t $SESSION:5 -c "${TOP_DIR}" -n 'test'

tmux select-window -t $SESSION:2
tmux split-window -h -c "${TOP_DIR}"
tmux select-pane -L

tmux select-window -t $SESSION:1
