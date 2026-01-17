     root:~# time ls /usr/bin | wc -l
     1
     real    22.097091675s
HOW??

  Both ls (23s) and simple-ls (30s) are extremely slow! This isn't a binary issue - it's likely:
  1. Filesystem (redoxfs) being slow for directory reads2. Too many stat() calls3. Dynamic linking overhead (but simple-ls
  is statically linked in initfs)

  ⏺ /bin = 0.5s, /usr/bin = 23s. Let me count files:


wget is still SLOOOOOW!!!

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

  -boot menu=off,strict=on \  no effect
  -fw_cfg name=etc/boot-menu,raw=off


 root:/scheme# cd lo2026-01-12T12-02-07.227Z [@inputd:208 ERROR] invalid path '' 


  0000000000000000: GUARD PAGE
kernel::context::signal:INFO -- UNHANDLED EXCEPTION, CPU #0, PID 60, NAME /usr/bin/randd, CONTEXT 0xfffffe800015a9f0
Abort


root:~# bash
relibc getrlimit(7, 0x7ffffffffb80): not implemented
bash-5.2# 

for i in 1 2 3 4 5; do echo loop $i; done
for i in 1 2 3 4 5; do echo loop \$i; done



kernel::arch::aarch64::interrupt::exception:ERROR -- FATAL: Not an SVC induced synchronous exception (ty=0)
=== CRASH REGISTERS ===
ESR_EL1: 0x0000000002000000 (EC=0b000000)
FAR_EL1: 0x00007fffffffcfe0
ELR_EL1: 0x000000000079c7f0
SP_EL0:  0x00007fffffffdd40
--- Scratch regs ---
X0:  0x0000000000000000  X1:  0x0000000000000028
X2:  0x0000000000000020  X3:  0x00000000007ab9e0
X4:  0x0000000000000000  X5:  0x00000000ffffffff
X6:  0x0000000000000006  X7:  0x00000000007a9a34
X8:  0x0000000000000040  X16: 0x00000000000014d0
X17: 0x0000000000000074  X18: 0x000000000000006f
--- Preserved regs ---
X29: 0x00007fffffffdd80  X30: 0x000000000079c7ec
X19: 0x00007fffffffdd48  X20: 0x00007fffffffdf68
=== STACK TRACE ===
ELR_EL1: 000000000079C7F0
SPSR_EL1: 0000000080000000
ESR_EL1: 0000000002000000
SP_EL0: 00007FFFFFFFDD40
X0:    0000000000000000
X1:    0000000000000028
X2:    0000000000000020
X3:    00000000007AB9E0
X4:    0000000000000000
X5:    00000000FFFFFFFF
X6:    0000000000000006
X7:    00000000007A9A34
X8:    0000000000000040
X9:    0000000000000001
X10:   0000000000000006
X11:   0000000000000000
X12:   0000000000000000
X13:   00000000FFFFFFFF
X14:   00000000FFFFFFFF
X15:   0000000000000006
X16:   00000000000014D0
X17:   0000000000000074
X18:   000000000000006F
X19:   00007FFFFFFFDD48
X20:   00007FFFFFFFDF68
X21:   0000000000000001
X22:   00007FFFFFFFDE50
X23:   0000000000000001
X24:   00007FFFFFFFDE60
X25:   0000000000000000
X26:   00007FFFFFFFE5A0
X27:   0000000000000001
X28:   00000000008DA208
X29:   00007FFFFFFFDD80
X30:   000000000079C7EC
  FP 00007fffffffdd80: PC 00000000007087c8
  FP 00007fffffffdd90: PC 00000000006ccd70
  FP 00007fffffffdda0: PC 00000000006ec900
  FP 00007fffffffddb0: PC 000000000043bf8c
  FP 00007fffffffddc0: PC 00000000006f6abc
  FP 00007fffffffde40: PC 00000000006f7fe8
  FP 00007fffffffe120: PC 00000000006f69f8
  FP 00007fffffffe1b0: PC 00000000006f6b80
  FP 00007fffffffe1e0: PC 000000000083c574
  FP 00007fffffffe220: PC 000000000081df20
  FP 00007fffffffe2f0: PC 00000000004284f4
  FP 00007fffffffe320: PC 0000000000427900
  FP 00007ffffffff850: PC 0000000000427588
  FP 00007ffffffff980: PC 000000000042e928
  FP 00007ffffffff9a0: PC 00000000006fdad8
  FP 00007ffffffff9b0: PC 00000000006ebb5c
  FP 00007ffffffff9e0: PC 00000000006ec1a4
  FP 00007ffffffffa90: PC 00000000006ebb14
  FP 00007ffffffffaf0: PC 00000000006ed384
  FP 00007ffffffffc10: PC 000000000042e908
  FP 00007ffffffffc30: PC 0000000000426adc
  FP 00007ffffffffc40: PC 00000000007389c4
  FP 00007ffffffffe80: PC 00000000003d4b78
  <Invalid next frame pointer 0x0000000000022080; stack walk ended>
  FP ffff800056b6ef40: PC 0000000056b6e000
  FP ffffff000029ba88: PC ffff800009000000
  0000000000000000: GUARD PAGE
kernel::context::signal:INFO -- UNHANDLED EXCEPTION, CPU #0, PID 80, NAME /usr/bin/orbital, CONTEXT 0xfffffe80001696b0
kernel::arch::aarch64::interrupt::exception:ERROR -- FATAL: Not an SVC induced synchronous exception (ty=111100)
=== CRASH REGISTERS ===
ESR_EL1: 0x00000000f2000001 (EC=0b111100)
FAR_EL1: 0x00000000200730c8
ELR_EL1: 0x00000000206597f8
SP_EL0:  0x00007ffffffffdf0
--- Scratch regs ---
X0:  0xffffffffffffffff  X1:  0xffffffffffffffff
X2:  0xffffffffffffffff  X3:  0xffffffffffffffff
X4:  0xffffffffffffffff  X5:  0x0000000000000000
X6:  0x0000000000000000  X7:  0x0000000000000000
X8:  0x000000000000009e  X16: 0x000000002012d658
X17: 0x0000000020659220  X18: 0x0000000020659260
--- Preserved regs ---
X29: 0x0000000000000000  X30: 0x00000000200cf174
X19: 0x00000000200d19c4  X20: 0x0000000000000000
=== STACK TRACE ===
ELR_EL1: 00000000206597F8
SPSR_EL1: 0000000020000000
ESR_EL1: 00000000F2000001
SP_EL0: 00007FFFFFFFFDF0
X0:    FFFFFFFFFFFFFFFF
X1:    FFFFFFFFFFFFFFFF
X2:    FFFFFFFFFFFFFFFF
X3:    FFFFFFFFFFFFFFFF
X4:    FFFFFFFFFFFFFFFF
X5:    0000000000000000
X6:    0000000000000000
X7:    0000000000000000
X8:    000000000000009E
X9:    0000000000000000
X10:   0000000000000000
X11:   0000000000000000
X12:   0000000000000000
X13:   0000000000000000
X14:   0000000000000000
X15:   0000000000000000
X16:   000000002012D658
X17:   0000000020659220
X18:   0000000020659260
X19:   00000000200D19C4
X20:   0000000000000000
X21:   00007FFFFFFFFE98
X22:   0000000000000000
X23:   0000000000000000
X24:   0000000000000000
X25:   0000000000000000
X26:   0000000000000000
X27:   0000000000000000
X28:   0000000000000000
X29:   0000000000000000
X30:   00000000200CF174
  <Unable to generate stack while frame pointers omitted>
  FP ffff800056b5ef40: PC 0000000056b5e000
  FP ffffff000029ba88: PC ffff800009000000
  0000000000000000: GUARD PAGE
kernel::context::signal:INFO -- UNHANDLED EXCEPTION, CPU #0, PID 83, NAME /usr/bin/ps, CONTEXT 0xfffffe8000169cc0
