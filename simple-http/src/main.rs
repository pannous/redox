use simple_http::SimpleHttpClient;

fn main() {
    println!("Testing simple HTTP client...");
    
    let client = SimpleHttpClient::new();
    
    println!("Creating HTTP GET to http://example.com...");
    match client.get("http://example.com") {
        Ok(response) => {
            println!("SUCCESS!");
            println!("Status: {}", response.status);
            println!("Headers: {}", response.headers.len());
            for (key, value) in response.headers.iter().take(3) {
                println!("  {}: {}", key, value);
            }
        }
        Err(e) => {
            println!("FAILED: {}", e);
        }
    }
    
    println!("Done!");
}
