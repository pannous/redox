chmod not on 9p but OK on ~ => move bins there! or do on HOST!
root:/scheme/9p.hostshare# ./bin/chmod 777 chmod-test


Creating files on the share with currently creates the wrong permissions on the host system. 
echo test > test
cat test
echo test >> test2
cat test2
echo test | tee test3
cat test3
/scheme/9p.hostshare/test-write.sh

There is a little problem with the cat command or prompt in that it cuts off the last line if it doesn't end with a newline. (\r Prompt ?)

/opt/other/redox/share/ cat ok
na
ja
was
root:/scheme/9p.hostshare# cat ok
na
ja
root:/scheme/9p.hostshare# echo jaaa >> ok
root:/scheme/9p.hostshare# cat ok
jaaa

was

chmod has no effect


@notes/execution.md
There seem to be at least two problems with script execution: 
• they cannot be invoked via . 
• they cannot be invoked via path (only via source)
• they cannot be invoked Cross-device


lets do a
Full rebuild - Set up build for new relibc binaries
Full rebuild of all relibc binaries

root:/scheme/9p.hostshare# bash
relibc getrlimit(7, 0x7ffffffffb70): not implemented
bash-5.2# ls
ok  simple-sync  ba  simple-echo  hi  hello  
bash-5.2# . ba
bash: ba: I/O error
TODO: Broken utilities on current image: coreutils suite is corrupted (commands behave like `ls` and emit `ls:` errors); observed `sleep` and `stat` acting as `ls`, and `killall` is missing.



root:/scheme/9p.hostshare# df
Path            Size      Used      Free Use%
/scheme/memory   1422356    192756   1229600  13%
/scheme/logging   1422356    192756   1229600  13%
1970-01-01T00-05-26.968Z [@inputd:208 ERROR] invalid path ''


root:/scheme/9p.hostshare# echo ja >> ok
Overwrites the content instead of appending. 


⏺ Bash(cd /opt/other/redox/tools/firmware && \
      cp edk2-aarch64-code.fd edk2-aarch64-code.fd.orig && \…)
  ⎿  -rw-r--r--  1 me  wheel  67108864 Jan 11 19:47 edk2-aarch64-code.fd
     -rw-r--r--  1 me  wheel  67108864 Jan 11 19:47 edk2-aarch64-vars.fd
     -rw-r--r--  1 me  wheel   2097152 Jan  6 14:47 QEMU_EFI.fd

⏺ Now both are 64MB. Try again:

⏺ Bash(cd /opt/other/redox && timeout 5 ./run-dev.sh 2>&1 || true)
  ⎿  4-core HVF + cache=unsafe,snapshot=on | /scheme/9p.hostshare/ for persistence
     Using: /opt/other/redox/build/aarch64/pure-rust.img
     Socket mode: ./run-dev.sh -s
     … +2 lines (ctrl+o to expand)

⏺ QEMU starts now. The UEFI firmware is loading.

  Now run ./run-dev.sh and when you see the countdown:
  1. Press Esc to enter setup
  2. Boot Maintenance Manager → Boot Options → Set Timeout Value
  3. Enter 0 → Save → Exit

  This setting persists in edk2-aarch64-vars.fd - you only need to do it once.
## rmm sync_icache fix (2026-01-12)
- cloned rmm from gitlab.redox-os.org/redox-os/rmm into recipes/core/kernel/source/rmm/
- added sync_icache() to AArch64Arch in src/arch/aarch64.rs
- required for kernel build (kernel calls RmmA::sync_icache for instruction cache coherence after mprotect)

