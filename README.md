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

***

# Personal Hardware Configuration
For more detailed specifications check out log of [hwinfo --short](logs/pc-configuration.txt).
* **Motherboard**: Gigabyte Z370HD3 Rev 1.0
* **CPU**: Intel Core i5 8400
* **GPU**: Zotac GeForce RTX 3070
* **SSD**: Samsung 970 EVO 512GB

***

# Table of Contents
* [Introduction](#introduction)
* [Pre-requisites](#pre-requisites)
* [Enable IOMMU](#enable-iommu)
* [Dynamic PCIe Binding](#dynamic-pcie-binding)
* [Creating Windows 11 Virtual Machine](#creating-windows-11-virtual-machine)
* [References](#references)

***

# Introduction

***

# Pre-requisites

***

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
    > * **[grep](https://www.geeksforgeeks.org/grep-command-in-unixlinux/)** is used for string matching. **-i** is to ignore case and **-e** is to add a regex expression. In this command, we get the lines from **dmesg** that contains either **IOMMU** or **DMAR**.

    A line saying something like `DMAR: IOMMU enabled` should appear. [Check my log output here.](logs/dmesg-log.txt)

7. If IOMMU is turned on then check for IOMMU groups. Create a script with the contents of [group-ionmmu-hw.sh](scripts/group-iommu-hw.sh). Then execute it.
    > * This script gives you the IOMMU group each hardware in your system belongs to. We pass everything under the same IOMMU group to the guest machine.  
    > * The output will have multiple lines all following the format shown below:  
    >      * IOMMU Group **[GROUP NO]**: **[Bus Address]** Title [0600]: Short Description **[Hardware ID]** (rev **[Revision number]**)
    > * *If your GPU and audio driver are in a IOMMU group with something other than the PCIe driver, you need to do an ACS override Patch.

***

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
    > * **systemctl** is used to manager services in manjaro. 
    > * **libvirtd** is a service for managing virtual machines. 
    > * It needs to be restarted so that it can use the new hook helper script.

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
    > * **Remember to add addition `virsh nodedev-detach $PCI_NAME` for each PCI device you wish to passthrough**
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

We're done setting up the hooks for PCI passthrough.

***

# Creating Windows 11 Virtual Machine

1. Download a windows 11 iso from the official microsoft site.
2. Download the stable release of virtio iso from [here](https://docs.fedoraproject.org/en-US/quick-docs/creating-windows-virtual-machines-using-virtio-drivers/).
3. Install TPM emulator `sudo pacman -Syyu swtpm`.
4. Create a virtual machine following `Virtual Machine Manager`
    > * How to install OS: Local Install Media
    > * Choose ISO: Windows 11 iso downloaded in step 1.
    > * Memory: I set 16384MB.
    > * CPU: I set 4
    > * Storage: I created a custom 64GB qcow2 storage.
    > * Virtual machine name: Must be **win11**
    > * Tick configure before installation.
5. In **Overview**, set firmware to secure boot.<br><img src="images/screen-captures/vm-setup-bios.png" alt="BIOS Options" style="width:512px;"/>
6. Go to **CPU** and set options.<br><img src="images/screen-captures/vm-setup-cpu.png" alt="CPU Options" style="width:512px;"/>
    > * Socket: How many CPUs are attached. In my case only 1.
    > * Cores: I set 4. Meaning, I'll have one CPU with 4 cores.
    > * Threads: I set 1. Meaning, Each core will have one thread.
7. Go to **SATA disk 1** and set options.<br><img src="images/screen-captures/vm-setup-sata.png" alt="SATA Options" style="width:512px;"/>
    > * Virtio disks are much more optimized for VMs compared to SATA.
    > * The cache mode `write-back` is a minor optmization to speed up disk speeds.
8. Go to **NIC** and set options.<br><img src="images/screen-captures/vm-setup-nic.png" alt="SATA Options" style="width:512px;"/>
9. Remove everything else except for the followings in the scrren shot.<br><img src="images/screen-captures/vm-setup-remove.png" alt="SATA Options" style="width:512px;"/>
10. Add new hardware.<br><img src="images/screen-captures/vm-setup-virt-iso.png" alt="SATA Options" style="width:512px;"/>
    > We're loading the virtio iso downloaded in step 2.
11. Go to **boot options** and configure CD ROM1 to boot first and then the virtio disk.<br><img src="images/screen-captures/vm-setup-boot-options.png" alt="SATA Options" style="width:512px;"/>
12. Add PCI hardware using `Add Hardware`. Each individual hardware must be added seperately.<br><img src="images/screen-captures/vm-setup-pci-add.png" alt="SATA Options" style="width:512px;"/>
    > **Make sure to repeat this step for all the devices associated with your GPU in the same IOMMU group**
13. Add USB devices to passthrough using `Add New Hardware`.<br><img src="images/screen-captures/vm-setup-usb-add.png" alt="SATA Options" style="width:512px;"/>
    > **The USB devices passed through will NOT be available on the host at this point.** Have additional mouse and keyboards attached so that you can use the host machine.
14. Add TPM through `Add New Hardware`.<br><img src="images/screen-captures/vm-setup-tpm.png" alt="SATA Options" style="width:512px;"/>
    > **TPM or Trusted Platform Module** is a hardware chip required to use Windows 11. We're basically emulating this.
15. (Optional) If you're using an nVidia GPU then you might face [Issue 43](https://passthroughpo.st/apply-error-43-workaround/). 
    * If you want to use all its features on the VM, you need to hide that the guest machine is a VM. To do this add the following XML portion under `<hyperv>`.
        ```xml
        <features>
            ...
            <hyperv>
                ...
                <spinlocks state="on" retries="8191"/>
                <vendor_id state="on" value="kvm hyperv"/>  <!-- Add this line -->
            </hyperv>
            ...
        </features>
        ```
    * In addition, instruct the kvm to hide its state by adding the following code directly below the `<hyperv>` section:
        ```xml
        <features>
            ...
            <hyperv>
                ...
            </hyperv>
            <kvm>
                <hidden state="on"/>
            </kvm>
            ...
        </features>
        ```
    * Finally, add the following line to `<feature>`
        ```xml
        <feature>
            ...
            <ioapic driver="kvm"/>
        </features>
        ```
16. Begin Installation.

# References
* [PCI Passthrough via OVMF](https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF)
* [GPU Passthrough Tutorial](https://github.com/bryansteiner/gpu-passthrough-tutorial#part2)