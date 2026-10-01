# patch_ovmf_timeout.py
import mmap, sys

print("TOO RISKY!!")
exit(0)
file = sys.argv[1] or "tools/firmware/QEMU_EFI.fd"
with open(file, "r+b") as f:
    mm = mmap.mmap(f.fileno(), 0)
    # pattern OVMF places near the timeout variable (00 00 00 00 00 00 00 00, followed by Timeout)
    # safer: search for the known default value (0x0003) used by OVMF
    for i in range(len(mm)-2):
        if mm[i] == 0x03 and mm[i+1] == 0x00:   # default timeout = 3 seconds
            mm[i] = 0x00
            mm[i+1] = 0x00
            break
    mm.flush()