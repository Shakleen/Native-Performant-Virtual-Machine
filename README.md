# Native Performant Virtual Machine
Setup a linux host machine to run virtual machines with near native performance. 

This repository describes the process of creating a **Windows 11** virtual machine on the Arch based distribution **Manjaro**. The following optimizations are used to achieve native performance:
* **Dynamic PCI-e passthrough** to bind/unbind GPU drivers
* **CPU core isolation** to limit host machine to a set of cores
* **CPU Pinning** to limit guest machine to a set of cores
* **CPU Frequency governor** to control CPU frequency on guest machine
* **Huge Memory Pages**
* **Virtio Disk** to optimize I/O operations
* **Keybinded Peripheral Swapping** to control both host and guest through a single set of peripherals
* **Audio passthrough** to get audio stream from guest in host machine