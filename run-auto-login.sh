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

if {$boot_wait > 0} {
    after [expr {$boot_wait * 1000}]
}

expect {
    -re "login:" { send "root\r" }
    timeout { }
}

interact
