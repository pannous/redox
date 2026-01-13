fn main() {
    println!("Testing tokio runtime initialization...");
    
    match tokio::runtime::Runtime::new() {
        Ok(rt) => {
            println!("Tokio runtime created successfully!");
            drop(rt);
            println!("Runtime dropped successfully!");
        }
        Err(e) => {
            println!("Failed to create tokio runtime: {}", e);
        }
    }
}
