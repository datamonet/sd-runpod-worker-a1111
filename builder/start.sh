#!/bin/bash

echo "Worker Initiated"

echo "Starting WebUI API"
python -u ${ROOT}/webui.py --listen --port 7860 ${CLI_ARGS} &

echo "Starting RunPod Handler"
python -u /rp_handler.py
