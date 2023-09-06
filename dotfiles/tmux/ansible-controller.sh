#!/usr/bin/env bash

SESSION="ansible-controller"
TOP_DIR="${HOME}/Tech/Bespoke/infra"

tmux new-session -d -s $SESSION -c "${TOP_DIR}" -n 'uat'
tmux send-keys 'echo ./bin/start-ec2-session.sh ansible-controller-uat' C-m

tmux new-window -t $SESSION:2 -c "${TOP_DIR}" -n 'prod'
tmux send-keys 'echo ./bin/start-ec2-session.sh ansible-controller-prod' C-m

tmux select-window -t $SESSION:1

tmux attach-session -t $SESSION
