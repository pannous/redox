use std::fs;

fn main() {
    println!("Checking what files reqwest might need...");
    
    // Check common files that HTTP clients need
    let files_to_check = vec![
        "/dev/urandom",
        "/dev/random",
        "/scheme/rand",
        "/scheme/randd",
        "/etc/ssl/certs",
        "/etc/ssl/cert.pem",
        "/etc/ca-certificates",
        "/usr/share/ca-certificates",
    ];
    
    for path in files_to_check {
        match fs::metadata(path) {
            Ok(meta) => println!("✓ {} exists ({})", path, 
                if meta.is_dir() { "dir" } else { "file" }),
            Err(e) => println!("✗ {} missing: {}", path, e),
        }
    }
    
    println!("\nAttempting to create reqwest client...");
    
    match reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(30))
        .build() 
    {
        Ok(_) => println!("✓ Success!"),
        Err(e) => {
            println!("✗ Failed: {}", e);
            println!("  Error debug: {:?}", e);
        }
    }
}
