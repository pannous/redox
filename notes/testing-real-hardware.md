# Testing Redox SMP on Real aarch64 Hardware

## Quick Test: TCG Instead of HVF (Try First!)

**Easiest option** - Test if the issue is specific to HVF (macOS Hypervisor):

```bash
./test-tcg.sh
```

This switches QEMU from HVF (hardware virtualization) to TCG (software emulation). It's slower but if SMP works here, we know it's an HVF-specific bug.

**What to look for:**
- Do APs reach Rust code? (Look for `RAP` markers in debug.log)
- Does `AP_ENTRY_COUNT` increment above 0?

---

## Option 2: Raspberry Pi 4/5 (Most Practical)

### What You Need
- **Raspberry Pi 4 Model B** (4GB or 8GB RAM recommended) - $55-75
  - Or **Raspberry Pi 5** - $60-80
- **microSD card** (32GB+) and card reader
- **USB-to-Serial adapter** (for console output) - $10-15
  - FTDI FT232RL or similar
  - Connects to Pi's GPIO pins (TX, RX, GND)
- **Power supply** (USB-C for Pi 4/5)

### Setup Steps

1. **Install UEFI firmware on SD card**
   ```bash
   # Download Raspberry Pi UEFI firmware
   wget https://github.com/pftf/RPi4/releases/latest/download/RPi4_UEFI_Firmware_v1.38.zip
   unzip RPi4_UEFI_Firmware_v1.38.zip

   # Write to SD card (assuming /dev/disk4 - CHECK WITH diskutil list!)
   sudo dd if=RPi4_UEFI.fd of=/dev/rdisk4 bs=1m

   # Or use Raspberry Pi Imager and manually copy files
   ```

2. **Copy Redox image to SD card**
   ```bash
   # After UEFI firmware, create partition and copy Redox image
   # Or write Redox directly if using whole SD card
   sudo dd if=build/aarch64/pure-rust.img of=/dev/rdisk4 bs=1m
   ```

3. **Connect serial console**
   ```
   Pi GPIO     FTDI Adapter
   Pin 6 (GND) → GND
   Pin 8 (TX)  → RX
   Pin 10 (RX) → TX
   ```

4. **Boot and monitor**
   ```bash
   # On Mac, connect serial
   screen /dev/tty.usbserial-* 115200

   # Power on Pi
   # Watch for AP boot markers in serial output
   ```

### Expected Behavior
If it works on real hardware:
- You'll see APs boot successfully
- `AP_ENTRY_COUNT` will show 3 or 4
- Multiple CPUs visible in `/scheme/sys/cpu`

---

## Option 3: Other aarch64 Single Board Computers

### Budget Options ($30-100)
- **Orange Pi 5** ($60-100) - RK3588S, 4-8 cores, UEFI support
- **Rock Pi 4** ($50-75) - RK3399, 6 cores
- **Pine64 RockPro64** ($60-80) - RK3399, 6 cores

### Premium Options ($200+)
- **Nvidia Jetson Nano** - Tegra X1, 4 cores
- **96Boards** (HiKey 960, etc.) - built for development, good UEFI support

### Setup
Similar to Raspberry Pi:
1. Flash UEFI firmware if available
2. Copy Redox image
3. Connect serial console
4. Boot and test

---

## Option 4: Cloud ARM Instances (AWS Graviton, etc.)

### Pros
- No hardware purchase needed
- Easy to spin up/down
- Multiple instance types available

### Cons
- Costs money per hour
- Needs bare-metal for direct kernel boot
- More complex setup

### AWS Graviton Setup
```bash
# Launch a Graviton instance (bare metal preferred)
aws ec2 run-instances \
  --image-id ami-xxx \
  --instance-type a1.metal \
  --key-name your-key

# Copy Redox kernel and boot via kexec or custom bootloader
```

**Note:** Cloud instances typically boot Linux first, so you'd need to:
1. Boot Linux on Graviton instance
2. Use `kexec` to boot Redox kernel
3. Or set up custom PXE/netboot

---

## Option 5: Try Different QEMU Settings (Before Buying Hardware)

### Different QEMU Versions
```bash
# Try system QEMU instead of custom build
brew install qemu
/opt/homebrew/bin/qemu-system-aarch64 ...

# Or build latest QEMU from source
git clone https://gitlab.com/qemu-project/qemu.git
cd qemu
./configure --target-list=aarch64-softmmu
make -j8
```

### Different Machine Types
```bash
# Try different -M options
-M virt,gic-version=3    # GICv3 instead of GICv2
-M virt,highmem=on       # High memory enabled
-M sbsa-ref              # Server Base System Architecture
```

### Enable QEMU Tracing
```bash
# Add to QEMU command
-d cpu,exec,int,guest_errors -D qemu-trace.log

# After boot, check trace
grep -A5 "Taking exception" qemu-trace.log
grep "IN:" qemu-trace.log | tail -100  # Last 100 instructions
```

This will show exactly what instructions APs execute and if they take exceptions.

---

## Recommendation

**Try in this order:**

1. ✅ **Run `./test-tcg.sh` first** (5 minutes, no cost)
   - If this works → HVF bug, report to Apple/QEMU
   - If this fails → deeper issue

2. **Enable QEMU tracing** (10 minutes, no cost)
   ```bash
   # Edit run-dev.sh, add to QEMU command:
   -d cpu,exec,int -D qemu-trace.log
   ```
   - Check what APs actually execute after `br x3`

3. **Buy Raspberry Pi 4** ($75 + shipping)
   - Most accessible real hardware
   - Good UEFI support
   - Active community

4. **Try cloud instances** (if you have AWS/cloud credits)

5. **Buy other SBCs** (only if you want specific features)

The TCG test will immediately tell us if this is worth pursuing on real hardware!
