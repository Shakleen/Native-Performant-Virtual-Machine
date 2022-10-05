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

# Personal Hardware Configuration
For more detailed specifications check out log of [hwinfo --short](logs/pc-configuration.txt).
* **Motherboard**: Gigabyte Z370HD3 Rev 1.0
* **CPU**: Intel Core i5 8400
* **GPU**: Zotac GeForce RTX 3070
* **SSD**: Samsung 970 EVO 512GB

# Table of Contents
* [Introduction](#introduction)
* [Pre-requisites](#pre-requisites)
* [Enable IOMMU](#enable-iommu)
* [Dynamic PCIe Binding](#dynamic-pcie-binding)

# Introduction

# Pre-requisites

# Enable IOMMU
1. Open a terminal and execute `sudo nano /etc/default/grub`. 
    > * This will open up default GRUB configuration. 
    > * *[GRUB](https://itsfoss.com/what-is-grub/) is a boot loader used by Manjaro Linux to load the operating system. We will edit this file to turn on IOMMU everytime the OS boots because it will be a pain to manually turn IOMMU on everytime.

2. Append `intel_iommu=on iommu=pt` to the end of **GRUB_CMDLINE_LINUX_DEFAULT** options. Afterwards it should look like this:
    ```bash
    # .. lines ...
    GRUB_CMDLINE_LINUX_DEFAULT="quiet udev.log_priority=3 intel_iommu=on iommu=pt"
    # .. lines ...
    ```

3. Save and exit file.

4. Update grub by typing `sudo update-grub`. 
    > This basically updates GRUB bootloader with the new configuration options.

5. Reboot.

6. Check if IOMMU has been enabled by executing `sudo dmesg | grep -i -e DMAR -e IOMMU`
    > * **[dmesg (diagnostic messages)](https://en.wikipedia.org/wiki/Dmesg)** is a command that prints the message buffer of the kernel
    > * ***[grep](https://www.geeksforgeeks.org/grep-command-in-unixlinux/)** is used for string matching. **-i** is to ignore case and **-e** is to add a regex expression. In this command, we get the lines from **dmesg** that contains either **IOMMU** or **DMAR**.

    A line saying something like `DMAR: IOMMU enabled` should appear. [Check my log output here.](logs/dmesg-log.txt)

7. If IOMMU is turned on then check for IOMMU groups. Create a script with the contents of [group-ionmmu-hw.sh](scripts/group-iommu-hw.sh). Then execute it.
    > * This script gives you the IOMMU group each hardware in your system belongs to. We pass everything under the same IOMMU group to the guest machine.  
    > * The output will have multiple lines all following the format shown below:  
    >      * IOMMU Group **[GROUP NO]**: **[Bus Address]** Title [0600]: Short Description **[Hardware ID]** (rev **[Revision number]**)
    > * *If your GPU and audio driver are in a IOMMU group with something other than the PCIe driver, you need to do an ACS override Patch.

# Dynamic PCIe Binding
We are going to dynamically bind the **vfio drivers** before the VM starts and unbind these drivers after the VM terminates. To achieve this, we're going to use [libvirt hooks](https://libvirt.org/hooks.html). Libvirt has a hook system that allows you to run commands on startup or shutdown of a VM.

## Hook Helper Script
1. Create a bash script with the contents of [qemu](scripts/qemu.sh)
2. Create a directory named `hooks` in `etc/libvirt` by executing `cd /etc/libvirt && sudo mkdir hooks`.
    > * **cd** is change directory. We go into `/etc/libvirt`.  
    > * **mkdir** is used to create a new directory.  
    > * **&&** is basically for chaining commands together.
    >
    > In short, we go to a directory and create a new folder there.
3. Copy this script into `/etc/libvirt/hooks/`. Make sure the name of the file is `qemu`.
4. Make the script executable by running `sudo chmod +x /etc/libvirt/hooks/qemu`.
    > * **chmod** command sets the permissions of files or directories.  
    > * **+x** is basically used to make the file executable by anyone.
5. Restart libvert services using `sudo systemctl restart libvirtd` to use the new script.
    > **systemctl** is used to manager services in manjaro. **libvirtd** is a service for managing virtual machines. It needs to be restarted so that it can use the new hook helper script.

## Setting up hooks

Let's first get know the important hooks
```
# Before a VM is started, before resources are allocated:
/etc/libvirt/hooks/qemu.d/$vmname/prepare/begin/*

# Before a VM is started, after resources are allocated:
/etc/libvirt/hooks/qemu.d/$vmname/start/begin/*

# After a VM has started up:
/etc/libvirt/hooks/qemu.d/$vmname/started/begin/*

# After a VM has shut down, before releasing its resources:
/etc/libvirt/hooks/qemu.d/$vmname/stopped/end/*

# After a VM has shut down, after resources are released:
/etc/libvirt/hooks/qemu.d/$vmname/release/end/*
```
If we place **an executable script** in one of these directories, the **hook manager** will take care of everything else. So the directory structure will look like the following for `win11` virtual machine:
```
/etc/libvirt/hooks/
├── qemu
└── qemu.d
    └── win11
        ├── prepare
        │   └── begin
        └── release
            └── end
```
1. Create this folder structure by executing this 
    ```bash
    $ cd /etc/libvirt/hooks 
    $ sudo mkdir qemu.d && $ cd qemu.d
    $ sudo mkdir win11 && cd win11
    $ sudo mkdir prepare prepare/begin release release/end
    ```

2. Create a file called `kvm.conf` in `/etc/libvirt/hooks` by executing `sudo touch /etc/libvirt/hooks/kvm.conf`.
3. We will now place the PCIe device ids inside this file in the following format
    ```
    ## Virsh devices
    VIRSH_GPU_VIDEO=pci_0000_01_00_0
    VIRSH_GPU_AUDIO=pci_0000_01_00_1
    VIRSH_GPU_USB=pci_0000_0a_00_2
    VIRSH_GPU_SERIAL=pci_0000_0a_00_3
    VIRSH_NVME_SSD=pci_0000_04_00_0
    ```
    > * Make sure to replace the bus addresses with the ones you want to actually pass through. You get these from the script used to generate IOMMU groups. For example: `IOMMU Group 1 01:00.0 ...` converts to `VIRSH_...=pci_0000_01_00_0`
    > * I will not be passing my SSD through. And I won't be using the GPU USB option either.
4. Create the [bind_vfio.sh](scripts/pcie_dynamic_passthrough/bind.sh) script under `/etc/libvirt/hooks/win11/prepare/begin`. 
    > * [modprob](https://en.wikipedia.org/wiki/Modprobe) is used to 
    >   * add a loadable kernel module to the Linux kernel
    >   * remove a loadable kernel module from the kernel.
    > * `virsh nodedev-detach` basically detaches the PCI driver from host and attaches it to the guest machine which in this case is **win11**.
    > * ***Remember to add addition `virsh nodedev-detach $PCI_NAME` for each PCI device you wish to passthrough**
5. Create the [unbind_vfio.sh](scripts/pcie_dynamic_passthrough/unbind.sh) script under `/etc/libvirt/hooks/win11/release/end`.
    > * `modprob -r` is basically used to remove loadable kernel module from the kernel.
    > * `virsh nodedev-reattach` basically detaches the drivers from the guest and reattaches them to the host.
    > * As before add additional `virsh nodedev-reattach` lines for each PCI device.
6. After creating the scripts the tree structure for the directory should look like this
    ```
    /etc/libvirt/hooks/
    ├── kvm.conf
    ├── qemu
    └── qemu.d
        └── win10
            ├── prepare
            │   └── begin
            │       └── bind_vfio.sh
            └── release
                └── end
                    └── unbind_vfio.sh
    ```
7. Make these two scripts executable by running `chmod +x` on them.