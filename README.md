# kOS - Custom Operating System Collection

A collection of x86 real-mode operating systems written in assembly (NASM), featuring a Unix-like kernel with 60+ commands, GUI capabilities, and a multi-boot bootloader.

## 🚀 Features

### JBoot - Multi-Kernel Bootloader
- **Triple-boot capability** - Choose between 3 different kernels
- Interactive boot menu
- Loads kernels from disk sectors
- Supports large kernels (40+ sectors)

### K122A - Unix-like Kernel
The flagship kernel with full Unix-like functionality:

**System Features:**
- Real RAM-based VFS (Virtual File System)
- Process management (11+ processes)
- User/permission system (UID-based)
- Shell with command parsing
- 60+ Linux-like commands

**Supported Commands:**
```
ls, pwd, cat, ps, mkdir, touch, rm, echo, cd, uname, whoami, chmod, 
kill, cp, mv, df, free, uptime, date, hostname, reboot, halt, grep, 
find, wc, head, tail, env, top, vmstat, dmesg, lsof, netstat, ifconfig, 
ping, wget, curl, tar, gzip, zip, mount, umount, fdisk, mkfs, fsck, 
su, sudo, passwd, chgrp, ln, stat, du, man, which, alias, history, 
export, source, and more...
```

**Process Types:**
- Kernel processes (UID 0)
- Application processes (UID 100-999)
- User processes (UID 1000+)

**File System:**
- Directory support
- File permissions (rwx)
- File ownership
- Path navigation

### K122E - Text Mode Kernel
- Simple text-based interface
- Lightweight design
- Basic I/O operations

### K122P - GUI Kernel
- Graphical user interface
- Pixel-based graphics
- Mouse support

## 📋 System Requirements

**To Build:**
- NASM assembler
- Any x86-compatible system

**To Run:**
- x86 emulator (QEMU recommended)
- Or real x86 hardware with BIOS

## 🛠️ Building

### Assemble the kernels:
```bash
nasm -f bin k122a.asm -o k122a.bin
nasm -f bin k122e.asm -o k122e.bin
nasm -f bin k122p.asm -o k122p.bin
nasm -f bin jboot.asm -o jboot.bin
```

### Create bootable disk image:
```bash
# Windows (PowerShell)
cmd /c "copy /b jboot.bin + k122e.bin + k122p.bin + k122a.bin os.img"

# Linux/Mac
cat jboot.bin k122e.bin k122p.bin k122a.bin > os.img
```

## 🎮 Running

### QEMU (Recommended):
```bash
qemu-system-i386 -drive file=os.img,format=raw,index=0,media=disk
```

### VirtualBox:
1. Create a new VM (Other/DOS)
2. Convert image: `VBoxManage convertfromraw os.img os.vdi`
3. Attach os.vdi as hard disk
4. Boot

### Real Hardware:
```bash
# Write to USB drive (CAUTION: This will erase the drive!)
# Linux
sudo dd if=os.img of=/dev/sdX bs=512

# Windows
# Use Rufus or Win32DiskImager in DD mode
```

## 📖 Usage

### Boot Menu
On startup, JBoot presents a menu:
```
1 - K122E Text
2 - K122P GUI
3 - K122A Unix
```

### K122A Shell Commands
Once booted into K122A:
```bash
# List files
ls

# Create directory
mkdir mydir

# Create file
touch myfile.txt

# Write to file
echo "Hello World" > myfile.txt

# Read file
cat myfile.txt

# Process management
ps              # List processes
top             # System monitor
kill <pid>      # Kill process

# System info
uname           # Kernel version
free            # Memory usage
df              # Disk usage
uptime          # System uptime
```

## 🏗️ Architecture

### Memory Layout
```
0x0000 - 0x7BFF  : BIOS/IVT
0x7C00 - 0x7DFF  : Bootloader (512 bytes)
0x8000 - 0xFFFF  : Kernel space
  - Code segment
  - VFS tables
  - Process tables
  - Stack
```

### Disk Layout
```
Sector 0      : JBoot bootloader
Sector 1-9    : K122E kernel
Sector 10-27  : K122P kernel
Sector 28-68  : K122A kernel
```

### K122A Internals
- **VFS**: 256 file entries, RAM-based
- **Processes**: 11 processes with state management
- **Shell**: Command parser with argument support
- **Permissions**: Basic Unix-like rwx permissions

## 🐛 Known Limitations

- 16-bit real mode only (no protected mode)
- Limited to 64KB per segment
- No multitasking (cooperative only)
- No virtual memory
- Basic filesystem (no persistence to disk)
- Limited error handling

## 🎯 Future Improvements

- [ ] Protected mode support
- [ ] Persistent filesystem (write to disk)
- [ ] Preemptive multitasking
- [ ] More complete POSIX compatibility
- [ ] Network stack implementation
- [ ] Extended memory support

## 📝 License

This project is open source and available for educational purposes.

## 🤝 Contributing

Feel free to fork, modify, and submit pull requests!

## ⚠️ Disclaimer

This is an educational project. Use at your own risk. Not suitable for production use.

## 🔧 Troubleshooting

**Boot fails:**
- Verify BIOS boot order
- Check disk image integrity
- Try different emulator settings

**Kernel doesn't load:**
- Verify sector offsets in JBoot
- Check kernel size doesn't exceed allocated sectors
- Ensure proper compilation with NASM

**Commands not working:**
- Some commands are partially implemented

## 📚 Resources

- [OSDev Wiki](https://wiki.osdev.org/)
- [NASM Documentation](https://www.nasm.us/docs.php)
- [x86 Assembly Guide](https://www.cs.virginia.edu/~evans/cs216/guides/x86.html)

## Next expected updates 
In Future K122P and K122E will lose support

---

**Made with ☕ and lots of assembly code!**
