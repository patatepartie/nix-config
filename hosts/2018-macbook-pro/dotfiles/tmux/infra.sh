#!/usr/bin/env bash

SESSION=infra
TOP_DIR="${HOME}/Tech/Bespoke/infra"

tmux new-session -d -s $SESSION -c "${TOP_DIR}/deploy" -n 'run'
tmux new-window -t $SESSION:2 -c "${TOP_DIR}" -n 'git'
tmux new-window -t $SESSION:3 -c "${TOP_DIR}" -n 'curl'
tmux new-window -t $SESSION:4 -c "${TOP_DIR}/deploy" -n 'vault'
tmux new-window -t $SESSION:5 -c "${TOP_DIR}" -n 'prod'
tmux new-window -t $SESSION:6 -c "${TOP_DIR}" -n 'uat'
tmux new-window -t $SESSION:7 -c "${TOP_DIR}/new-relic" -n 'new-relic'

tmux select-window -t $SESSION:2
tmux split-window -h -c "${TOP_DIR}"
tmux select-pane -L

tmux select-window -t $SESSION:5
tmux split-window -h -c "${TOP_DIR}"
tmux select-pane -L

tmux select-window -t $SESSION:6
tmux split-window -h -c "${TOP_DIR}"
tmux select-pane -L

tmux select-window -t $SESSION:4
tmux send-keys 'docker-compose run --rm infra ansible-vault --vault-password-file=.vault.pass view inventories/group_vars/uatnew/new_relic.vault.yml' C-m

tmux select-window -t $SESSION:1
