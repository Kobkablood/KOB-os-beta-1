# KOB-os-1

🚀 KOBos Beta 1 — How to Run the Operating System

KOBos is an independent Linux distribution based on Debian 13 Trixie, featuring the XFCE desktop environment.

This guide explains how to download, boot, install, and test KOBos.

📥 1. Download KOBos

Download the KOBos ISO image:

File: kobos-beta1-amd64.hybrid.iso

Architecture: AMD64 (64-bit)

Format: Hybrid ISO

Make sure the ISO file has been downloaded completely.

💻 2. Run KOBos using VirtualBox

Recommended for first-time users.

Install VirtualBox.

Open VirtualBox.

Click New.

Name: KOBos Beta 1.

Type: Linux.

Version: Debian (64-bit).

Configure the virtual machine:

RAM: 4096 MB

CPUs: 2

Video Memory: 128 MB

Create a virtual hard disk if required.

Open Settings → Storage.

Attach kobos-beta1-amd64.hybrid.iso as a virtual optical disk.

Start the virtual machine.

🐧 3. Run KOBos using QEMU (Linux)

Install QEMU:

sudo apt update
sudo apt install qemu-system-x86 -y

Start KOBos:

qemu-system-x86_64 \
  -m 4096 \
  -smp 2 \
  -cdrom kobos-beta1-amd64.hybrid.iso \
  -boot d

💿 4. Boot KOBos from a USB Drive

Prepare a USB drive with at least 8 GB of storage.

Download balenaEtcher.

Select the KOBos ISO image.

Select your USB drive.

Click Flash.

Restart your computer.

Open the Boot Menu.

Select your USB drive.

⚠️ WARNING: Flashing the ISO will erase all data on the selected USB drive. Make sure you select the correct device.

⚙️ 5. Install KOBos

If the Calamares installer is included in the ISO:

Boot from the KOBos ISO.

Wait for the Live System to load.

Open the Calamares installer, if available.

Follow the installation instructions.

Select the target disk.

Complete the installation.

Restart your computer.

⚠️ Installing with disk formatting may erase existing data. We recommend testing KOBos in a virtual machine first.

🧪 6. Beta 1 Testing

We appreciate your help testing KOBos!

Please check:

Does KOBos boot successfully?

Does the XFCE desktop environment work?

Do the mouse and keyboard work?

Does the internet connection work?

Do system applications launch correctly?

Does the Calamares installer work (if included)?

If you find a bug, please create a GitHub Issue and describe the problem.

📢 Feedback & Contributions

KOBos is continuously evolving. Your feedback, bug reports, and suggestions help us improve the operating system.

Thank you for testing KOBos!

KOBos — Your System. Your Rules. 🚀

Project information

Details

Version

Beta 1

Base

Debian 13 Trixie

Architecture

AMD64 (64-bit)

Desktop Environment

XFCE 4

Installer

Calamares (if included)
