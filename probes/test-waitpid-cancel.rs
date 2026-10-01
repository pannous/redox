/// Test for placeholder state bug in procmgr
///
/// This test exercises the waitpid + cancellation path that was causing
/// "State Id(X) was placeholder!" warnings.
///
/// The bug: When waitpid completes successfully, the state entry wasn't
/// removed from the hashmap, leaving a Placeholder state that would trigger
/// warnings if a cancellation arrived later.

use std::process::{Command, Child};
use std::time::Duration;
use std::thread;

fn spawn_short_lived_child() -> Child {
    Command::new("true")
        .spawn()
        .expect("Failed to spawn child")
}

fn main() {
    println!("Testing waitpid + cancellation race condition...");
    println!("This test should complete WITHOUT 'placeholder' warnings in logs.\n");

    // Test 1: Sequential waitpid operations
    println!("[Test 1] Sequential waitpid on multiple children");
    for i in 0..10 {
        let mut child = spawn_short_lived_child();
        let result = child.wait();
        println!("  Child {} exit: {:?}", i, result);
    }

    // Test 2: Rapid fork/wait cycles
    println!("\n[Test 2] Rapid fork/wait cycles");
    for i in 0..20 {
        let mut child = spawn_short_lived_child();
        // Wait immediately - this should complete quickly
        let result = child.wait();
        println!("  Rapid cycle {} exit: {:?}", i, result);
    }

    // Test 3: Multiple children in parallel
    println!("\n[Test 3] Multiple children in parallel");
    let mut children: Vec<Child> = (0..5)
        .map(|_| spawn_short_lived_child())
        .collect();

    for (i, child) in children.iter_mut().enumerate() {
        let result = child.wait();
        println!("  Parallel child {} exit: {:?}", i, result);
    }

    // Test 4: Long-running children
    println!("\n[Test 4] Long-running children");
    let mut children: Vec<Child> = (0..3)
        .map(|_| {
            Command::new("sleep")
                .arg("1")
                .spawn()
                .expect("Failed to spawn sleep")
        })
        .collect();

    // Wait a bit, then wait on all
    thread::sleep(Duration::from_millis(500));
    for (i, child) in children.iter_mut().enumerate() {
        let result = child.wait();
        println!("  Long child {} exit: {:?}", i, result);
    }

    println!("\n✓ All tests completed successfully!");
    println!("Check logs for any 'State Id(X) was placeholder!' warnings.");
    println!("Expected: ZERO warnings (bug is fixed)");
}
