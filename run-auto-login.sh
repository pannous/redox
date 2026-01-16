#!/usr/bin/expect -f
# Auto-login wrapper for run-dev.sh using expect.

set timeout -1
set boot_wait 1
# ${env(BOOT_WAIT):-30}
if {![info exists boot_wait] || $boot_wait == ""} {
    set boot_wait 0
}

# spawn ./run-dev.sh
spawn ./run-dev.sh -g # gui 

# Auto-select default resolution in QEMU GUI window after 2s
exec bash -c {sleep 1 && osascript -e 'tell application "System Events" to keystroke return'} &
exec bash -c {sleep 2 && osascript -e 'tell application "System Events" to keystroke return'} &
exec bash -c {sleep 3 && osascript -e 'tell application "System Events" to keystroke return'} &
exec bash -c {sleep 5 && osascript -e 'tell application "System Events" to keystroke return'} &

if {$boot_wait > 0} {
    after [expr {$boot_wait * 1000}]
}

expect {
    -re "login:" { send "root\r" }
    timeout { }
}

interact
