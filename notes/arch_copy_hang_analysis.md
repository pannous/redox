# arch_copy_to_user Hang Analysis - 2026-01-30

## Problem
`arch_copy_to_user` hangs when trying to write even 1 byte to userspace address 0x1000.

## What We Tried
1. ✗ 8-byte copy optimization - still hangs
2. ✗ Byte-by-byte copy - still hangs
3. ✗ Memory barriers (DSB/ISB) - still hangs
4. ✗ STTR (unprivileged store) - still hangs
5. ✗ 1-byte test copy - still hangs

## Critical Observations
- NO exceptions are raised (data abort handler never called)
- Store instructions appear to hang indefinitely
- Even single byte stores hang
- Destination: 0x1000 (PAGE_SIZE, start of userspace)
- Source: 0xffff800083b20000 (kernel memory)

## Hypothesis: Page Table Issue
The userspace pages at 0x1000 may not be mapped in the active page tables.

Possible causes:
1. Still using kernel page tables (TTBR1_EL1) instead of user page tables (TTBR0_EL1)
2. Grant::zeroed() didn't actually allocate/map the pages
3. Page table entries don't have correct permissions
4. Address space wasn't properly activated for the bootstrap context

## Next Steps
1. Check which TTBR is active (read TTBR0_EL1/TTBR1_EL1)
2. Verify Grant::zeroed actually mapped pages
3. Check if context switch properly activated bootstrap's address space
4. Dump page table entries for address 0x1000
5. Check if we need to explicitly switch page tables before usermode_bootstrap
