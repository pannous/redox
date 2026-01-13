use std::fs;

fn count_open_fds() -> usize {
    let mut count = 0;
    // Check FDs from 0 to 200
    for i in 0..200 {
        if let Ok(_) = fs::metadata(format!("/scheme/sys/context/{}/fd/{}", 
                                             std::process::id(), i)) {
            count += 1;
        }
    }
    count
}

fn list_open_fds() {
    println!("Open file descriptors:");
    for i in 0..50 {
        let path = format!("/scheme/sys/context/{}/fd/{}", std::process::id(), i);
        if let Ok(link) = fs::read_link(&path) {
            println!("  FD {}: {:?}", i, link);
        }
    }
}

fn main() {
    let pid = std::process::id();
    println!("PID: {}", pid);
    
    println!("\n=== Before reqwest initialization ===");
    list_open_fds();
    let before = count_open_fds();
    println!("Open FDs: {}", before);
    
    println!("\n=== Creating reqwest client ===");
    match reqwest::blocking::Client::builder().build() {
        Ok(client) => {
            println!("✓ Client created successfully!");
            let after = count_open_fds();
            println!("Open FDs after: {}", after);
            println!("Diff: +{}", after - before);
        }
        Err(e) => {
            println!("✗ Failed to create client: {}", e);
            println!("\n=== After failure ===");
            list_open_fds();
            let after = count_open_fds();
            println!("Open FDs after failure: {}", after);
            println!("Diff: +{}", after - before);
        }
    }
}
