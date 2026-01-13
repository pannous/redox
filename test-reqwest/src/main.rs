fn main() {
    println!("Testing basic HTTP with std::net...");
    
    use std::net::TcpStream;
    use std::io::{Read, Write};
    
    let mut stream = TcpStream::connect("example.com:80").expect("Failed to connect");
    println!("Connected!");
    
    let request = "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n";
    stream.write_all(request.as_bytes()).expect("Failed to write");
    
    let mut response = String::new();
    stream.read_to_string(&mut response).expect("Failed to read");
    
    println!("Response length: {}", response.len());
    println!("First 200 chars: {}", &response[..200.min(response.len())]);
}
