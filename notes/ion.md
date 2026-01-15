## DONE: liner EAGAIN error fix (2026-01-15)

Root cause: `change_blocking()` used O_RDWR (access mode) to clear O_NONBLOCK.
O_RDWR is not a status flag, so this did nothing.

Fix: Get flags with F_GETFL, clear O_NONBLOCK bit, set with F_SETFL.
See `recipes/core/ion/source/src/binary/readln.rs`

Committed: 27449fc9 in ion source repo

## Ion shell notes

source command / . works for executing scripts
/scheme/9p.hostshare/script.ion to run from 9p share
