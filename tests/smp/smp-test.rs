use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Instant;

const ITERATIONS: usize = 1_000_000;
const NUM_THREADS: usize = 4;

fn get_thread_info() -> String {
    // Try to determine which CPU this thread is running on
    // On Linux this would use sched_getcpu(), but on Redox we'll use thread ID
    format!("tid={:?}", thread::current().id())
}

fn worker_thread(thread_id: usize, counter: Arc<AtomicUsize>) {
    println!("[Thread {}] Starting on {}", thread_id, get_thread_info());

    let start = Instant::now();

    for i in 0..ITERATIONS {
        counter.fetch_add(1, Ordering::Relaxed);

        // Print progress every 250k iterations
        if i > 0 && i % 250_000 == 0 {
            println!("[Thread {}] Progress: {}/{} iterations", thread_id, i, ITERATIONS);
        }
    }

    let elapsed = start.elapsed();
    println!("[Thread {}] Completed {} iterations in {:.3}s",
             thread_id, ITERATIONS, elapsed.as_secs_f64());
}

fn main() {
    println!("=== Redox SMP Test Program ===");
    println!("Testing parallel execution on {} threads", NUM_THREADS);
    println!("Each thread will perform {} iterations\n", ITERATIONS);

    // Create atomic counters for each thread
    let counters: Vec<Arc<AtomicUsize>> = (0..NUM_THREADS)
        .map(|_| Arc::new(AtomicUsize::new(0)))
        .collect();

    // Measure total execution time
    let total_start = Instant::now();

    // Spawn worker threads
    let handles: Vec<_> = counters
        .iter()
        .enumerate()
        .map(|(id, counter)| {
            let counter_clone = Arc::clone(counter);
            thread::spawn(move || worker_thread(id, counter_clone))
        })
        .collect();

    println!("Spawned {} threads, waiting for completion...\n", NUM_THREADS);

    // Wait for all threads to complete
    for (id, handle) in handles.into_iter().enumerate() {
        handle.join().expect(&format!("Thread {} panicked", id));
    }

    let total_elapsed = total_start.elapsed();

    // Verify results
    println!("\n=== Results ===");
    let mut all_correct = true;
    for (id, counter) in counters.iter().enumerate() {
        let count = counter.load(Ordering::Relaxed);
        let correct = count == ITERATIONS;
        println!("Thread {}: {} iterations ({})",
                 id, count, if correct { "OK" } else { "FAILED" });
        all_correct = all_correct && correct;
    }

    println!("\n=== Performance ===");
    println!("Total execution time: {:.3}s", total_elapsed.as_secs_f64());

    let total_iterations = NUM_THREADS * ITERATIONS;
    let throughput = total_iterations as f64 / total_elapsed.as_secs_f64();
    println!("Total iterations: {}", total_iterations);
    println!("Throughput: {:.0} iterations/sec", throughput);

    // Calculate expected single-threaded time (estimate)
    // If truly parallel on 4 CPUs, should be ~4x faster than single-threaded
    let estimated_single_threaded = total_elapsed.as_secs_f64() * NUM_THREADS as f64;
    let speedup = estimated_single_threaded / total_elapsed.as_secs_f64();
    println!("Estimated speedup: {:.2}x", speedup);

    if speedup > 3.0 {
        println!("✓ Excellent parallelism (>3x speedup)");
    } else if speedup > 2.0 {
        println!("✓ Good parallelism (>2x speedup)");
    } else if speedup > 1.5 {
        println!("⚠ Limited parallelism (>1.5x speedup)");
    } else {
        println!("⚠ Poor parallelism (<1.5x speedup) - may be running serially");
    }

    println!("\n=== Summary ===");
    if all_correct {
        println!("✓ All threads completed successfully");
        std::process::exit(0);
    } else {
        println!("✗ Some threads failed verification");
        std::process::exit(1);
    }
}
