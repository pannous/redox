use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::fs::File;
use std::path::Path;
use std::time::Duration;

pub struct SimpleHttpClient {
    timeout: Duration,
}

pub struct Response {
    pub status: u16,
    pub headers: Vec<(String, String)>,
    pub stream: Box<dyn Read>,
}

impl SimpleHttpClient {
    pub fn new() -> Self {
        Self {
            timeout: Duration::from_secs(30),
        }
    }
    
    pub fn get(&self, url: &str) -> io::Result<Response> {
        eprintln!("[HTTP] Parsing URL: {}", url);
        let (host, port, path) = parse_url(url)?;
        let addr = format!("{}:{}", host, port);
        
        eprintln!("[HTTP] Connecting to {}...", addr);
        let mut stream = TcpStream::connect(&addr)?;
        eprintln!("[HTTP] Connected!");
        
        stream.set_read_timeout(Some(self.timeout))?;
        stream.set_write_timeout(Some(self.timeout))?;
        
        let request = format!(
            "GET {} HTTP/1.1\r\nHost: {}\r\nConnection: close\r\nUser-Agent: pkg/redox\r\n\r\n",
            path, host
        );
        
        eprintln!("[HTTP] Sending request...");
        stream.write_all(request.as_bytes())?;
        stream.flush()?;
        
        eprintln!("[HTTP] Reading response...");
        let mut reader = BufReader::new(stream);
        let mut status_line = String::new();
        reader.read_line(&mut status_line)?;
        
        eprintln!("[HTTP] Status line: {}", status_line.trim());
        let status = parse_status_line(&status_line)?;
        
        let mut headers = Vec::new();
        loop {
            let mut line = String::new();
            reader.read_line(&mut line)?;
            if line == "\r\n" || line == "\n" {
                break;
            }
            if let Some((key, value)) = line.split_once(':') {
                headers.push((key.trim().to_string(), value.trim().to_string()));
            }
        }
        
        eprintln!("[HTTP] Got {} headers", headers.len());
        
        Ok(Response {
            status,
            headers,
            stream: Box::new(reader),
        })
    }
    
    pub fn download(&self, url: &str, path: &Path) -> io::Result<u64> {
        let mut response = self.get(url)?;
        
        if response.status != 200 {
            return Err(io::Error::new(
                io::ErrorKind::Other,
                format!("HTTP error: {}", response.status),
            ));
        }
        
        let mut file = File::create(path)?;
        let bytes = io::copy(&mut response.stream, &mut file)?;
        file.flush()?;
        
        Ok(bytes)
    }
}

fn parse_url(url: &str) -> io::Result<(String, String, String)> {
    let url = url.strip_prefix("http://").ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidInput, "Only HTTP URLs supported")
    })?;
    
    let (host_port, path) = url.split_once('/').unwrap_or((url, ""));
    let path = if path.is_empty() { "/" } else { &format!("/{}", path) };
    
    let (host, port) = if host_port.contains(':') {
        let mut parts = host_port.split(':');
        (
            parts.next().unwrap().to_string(),
            parts.next().unwrap().to_string(),
        )
    } else {
        (host_port.to_string(), "80".to_string())
    };
    
    Ok((host, port, path.to_string()))
}

fn parse_status_line(line: &str) -> io::Result<u16> {
    let parts: Vec<&str> = line.split_whitespace().collect();
    if parts.len() < 2 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "Invalid HTTP status line",
        ));
    }
    
    parts[1].parse().map_err(|_| {
        io::Error::new(io::ErrorKind::InvalidData, "Invalid status code")
    })
}
