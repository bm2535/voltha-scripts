#!/bin/bash
cp /usr/local/bin/voltha/voltha.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable voltha.service
