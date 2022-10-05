#!/bin/sh

systemctl set-property --runtime -- system.slice AllowedCPUs=4,5
systemctl set-property --runtime -- user.slice AllowedCPUs=4,5
systemctl set-property --runtime -- init.scope AllowedCPUs=4,5

# The kernel's dirty page writeback mechanism uses kthread workers. They introduce
# massive arbitrary latencies and aren't migrated by cset.
# Restrict the workqueue to use only cpu 0.
echo $HOST_CORES_MASK > /sys/bus/workqueue/devices/writeback/cpumask
echo 0 > /sys/bus/workqueue/devices/writeback/numa