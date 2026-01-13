use std::fs;

fn main() {
    println!("Testing file opening...");
    
    // Try to open /dev/null many times
    let mut handles = Vec::new();
    for i in 0..100 {
        match fs::File::open("/scheme/null") {
            Ok(f) => handles.push(f),
            Err(e) => {
                println!("Failed to open /scheme/null at iteration {}: {}", i, e);
                break;
            }
        }
    }
    println!("Successfully opened {} files", handles.len());
    println!("Dropping handles...");
    drop(handles);
    
    println!("\nTesting reqwest initialization...");
    println!("Creating client...");
    match reqwest::blocking::Client::builder().build() {
        Ok(client) => {
            println!("Client created successfully!");
            println!("Attempting GET request...");
            match client.get("http://example.com").send() {
                Ok(response) => println!("Success! Status: {}", response.status()),
                Err(e) => println!("Request failed: {}", e),
            }
        }
        Err(e) => {
            println!("Failed to create client: {}", e);
        }
    }
}
