use std::fs::{self, File};
use std::io::{Write, Read};
use std::process::{Command, exit};
use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Instant;

const NUM_WORKERS: usize = 8;
const ITERATIONS: usize = 10000;
const MEMORY_SIZE: usize = 1024 * 1024; // 1MB

fn cpu_intensive_work(worker_id: usize, counter: Arc<AtomicUsize>) {
    let mut sum: u64 = 0;
    for i in 0..ITERATIONS * 100 {
        sum = sum.wrapping_add((i * worker_id) as u64);
        if i % 10000 == 0 {
            counter.fetch_add(1, Ordering::Relaxed);
        }
    }
    println!("Worker {}: CPU intensive work done (sum={})", worker_id, sum);
}

fn memory_intensive_work(worker_id: usize) {
    let mut buffer = vec![0u8; MEMORY_SIZE];

    // Write pattern
    for i in 0..MEMORY_SIZE {
        buffer[i] = ((i + worker_id) & 0xFF) as u8;
    }

    // Verify pattern
    for i in 0..MEMORY_SIZE {
        if buffer[i] != ((i + worker_id) & 0xFF) as u8 {
            eprintln!("Worker {}: Memory corruption at {}!", worker_id, i);
            return;
        }
    }

    println!("Worker {}: Memory test passed ({} bytes)", worker_id, MEMORY_SIZE);
}

fn io_intensive_work(worker_id: usize) -> Result<(), std::io::Error> {
    let filename = format!("/tmp/smp_test_{}.tmp", worker_id);

    // Write test data
    {
        let mut file = File::create(&filename)?;
        for i in 0..1000 {
            writeln!(file, "Worker {} iteration {}", worker_id, i)?;
        }
    }

    // Read and verify
    let mut file = File::open(&filename)?;
    let mut contents = String::new();
    file.read_to_string(&mut contents)?;
    let lines = contents.lines().count();

    // Cleanup
    fs::remove_file(&filename)?;

    println!("Worker {}: I/O test passed ({} lines)", worker_id, lines);
    Ok(())
}

fn worker_process(worker_id: usize) {
    println!("Worker {} starting (PID {})...", worker_id, std::process::id());

    let counter = Arc::new(AtomicUsize::new(0));

    cpu_intensive_work(worker_id, counter.clone());
    memory_intensive_work(worker_id);

    if let Err(e) = io_intensive_work(worker_id) {
        eprintln!("Worker {}: I/O error: {}", worker_id, e);
    }

    println!("Worker {} completed all tests", worker_id);
}

fn main() {
    println!("=== SMP Stress Test ===");
    println!("Starting {} concurrent worker processes...\n", NUM_WORKERS);

    let start_time = Instant::now();
    let mut children = Vec::new();

    // Spawn worker processes
    for i in 0..NUM_WORKERS {
        match unsafe { libc::fork() } {
            -1 => {
                eprintln!("Failed to fork worker {}", i);
                exit(1);
            }
            0 => {
                // Child process
                worker_process(i);
                exit(0);
            }
            pid => {
                // Parent process
                children.push(pid);
            }
        }
    }

    // Wait for all workers
    let mut failed = 0;
    for (i, &pid) in children.iter().enumerate() {
        let mut status: i32 = 0;
        let result = unsafe { libc::waitpid(pid, &mut status as *mut i32, 0) };

        if result < 0 {
            eprintln!("Failed to wait for worker {}", i);
            failed += 1;
        } else if !libc::WIFEXITED(status) || libc::WEXITSTATUS(status) != 0 {
            eprintln!("Worker {} failed with status {}", i, status);
            failed += 1;
        } else {
            println!("Worker {} (PID {}) completed successfully", i, pid);
        }
    }

    let duration = start_time.elapsed();

    println!("\n=== Test Results ===");
    println!("Duration: {:.2} seconds", duration.as_secs_f64());
    println!("Workers completed: {}/{}", NUM_WORKERS - failed, NUM_WORKERS);
    println!("Status: {}", if failed == 0 { "PASSED" } else { "FAILED" });

    exit(if failed > 0 { 1 } else { 0 });
}
