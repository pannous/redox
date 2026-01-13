fn main() {
    println!("Testing reqwest (blocking only, no TLS)...");
    
    println!("Creating client...");
    match reqwest::blocking::Client::builder().build() {
        Ok(client) => {
            println!("Client created!");
            println!("Making HTTP request...");
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
