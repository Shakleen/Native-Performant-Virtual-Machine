#!/bin/sh

systemctl set-property --runtime -- system.slice AllowedCPUs=0-5
systemctl set-property --runtime -- user.slice AllowedCPUs=0-5
systemctl set-property --runtime -- init.scope AllowedCPUs=0-5

# Revert changes made to the writeback workqueue
echo $TOTAL_CORES_MASK > /sys/bus/workqueue/devices/writeback/cpumask
echo 1 > /sys/bus/workqueue/devices/writeback/numa