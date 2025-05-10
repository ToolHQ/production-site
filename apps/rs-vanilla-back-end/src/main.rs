use std::fs::File;
use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::{Arc, Condvar, Mutex};
use std::thread;

const MAX_CONCURRENT_CONNECTIONS: usize = 100;

struct Semaphore {
    count: Mutex<usize>,
    condvar: Condvar,
}

impl Semaphore {
    fn new(limit: usize) -> Self {
        Self {
            count: Mutex::new(limit),
            condvar: Condvar::new(),
        }
    }

    fn acquire(&self) {
        let mut count = self.count.lock().unwrap();
        while *count == 0 {
            count = self.condvar.wait(count).unwrap();
        }
        *count -= 1;
    }

    fn release(&self) {
        let mut count = self.count.lock().unwrap();
        *count += 1;
        self.condvar.notify_one();
    }
}

fn main() {
    let semaphore = Arc::new(Semaphore::new(MAX_CONCURRENT_CONNECTIONS));
        let listener = TcpListener::bind("0.0.0.0:3000").expect("Failed to bind");

        println!("🟢 Listening on http://0.0.0.0:3000");

        for stream in listener.incoming() {
        let stream = match stream {
            Ok(s) => s,
                Err(e) => {
                    eprintln!("Connection failed: {}", e);
                continue;
        }
        };

        let sem = semaphore.clone();
        thread::spawn(move || {
            sem.acquire();
            handle_client(stream);
            sem.release();
        });
    }
}

fn close_connection(stream: TcpStream) {
    if let Err(e) = stream.shutdown(std::net::Shutdown::Both) {
        eprintln!("Failed to close connection: {}", e);
    }
}

fn handle_client(mut stream: TcpStream) {
    let peer_addr = stream.peer_addr().unwrap();
    let mut buf_reader = BufReader::new(stream.try_clone().unwrap());

    // Loop to support request pipelining
    loop {
        let mut request_line = String::new();

        // Read just the first line of the request to get method, path, and version
        let mut bytes_read = match buf_reader.read_line(&mut request_line) {
            Ok(n) if n == 0 => {
                // EOF: client closed connection cleanly
                close_connection(stream);
                return;
            }
            Ok(n) => n,
            Err(e) => {
                eprintln!("Failed to read from {}: {}", peer_addr, e);
                close_connection(stream);
                return;
            }
        };

        let first_line_parts: Vec<&str> = request_line.split_whitespace().collect();
        if first_line_parts.len() != 3 {
            // TODO: Support HTTP/0.9
            let _ = stream.write_all(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\n\r\n");
            eprintln!("Invalid request line: {}", request_line);
            close_connection(stream);
            return;
        }
        let http_method = first_line_parts[0].to_string();
        let http_path = first_line_parts[1].to_string();
        let http_version = first_line_parts[2].to_string();

        if http_version != "HTTP/1.1" {
            // TODO: Support HTTP/1.0 and HTTP/2 and HTTP/3
            let _ = stream
                .write_all(b"HTTP/1.1 505 HTTP Version Not Supported\r\nContent-Length: 0\r\n\r\n");
            eprintln!("Unsupported HTTP version: {}", http_version);
            close_connection(stream);
            return;
        }

        // Headers of interest
        let mut connection_header = "keep-alive".to_string();

        // Read line by line to get the headers using O(1) memory
        loop {
            request_line.clear();
            bytes_read += match buf_reader.read_line(&mut request_line) {
                Ok(n) if n == 0 => {
                    // EOF: client closed connection cleanly
                    close_connection(stream);
                    return;
                }
                Ok(n) => n,
                Err(e) => {
                    eprintln!("Failed to read from {}: {}", peer_addr, e);
                    close_connection(stream);
                    return;
                }
            };

            let request_line_trimmed = request_line.trim_end();
            // When \r\n\r\n is reached, the headers are done
            if request_line_trimmed.is_empty() {
                break;
            }

            if let Some((header_name, header_value)) = request_line_trimmed.split_once(':') {
                let header_name = header_name.trim();
                let header_value = header_value.trim();
                if header_name.eq_ignore_ascii_case("Connection") {
                    connection_header = header_value.to_string();
                }
            } else {
                eprintln!("Invalid header: {}", request_line_trimmed);
            }
        }

        // Handles GET /health
        if http_method.eq_ignore_ascii_case("GET") && http_path == "/health" {
            let _ = stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n");
            if connection_header.eq_ignore_ascii_case("close") {
                close_connection(stream);
                break;
            }
            continue;
        }

        // Logs request
        println!(
            "Request Received: {} {} from {}. Bytes read: {}. Connection: {}",
            http_method, http_path, peer_addr, bytes_read, connection_header
        );

        // Handles GET /ndjson
        if http_method.eq_ignore_ascii_case("GET") && http_path == "/ndjson" {
            if let Ok(file) = File::open("/app/data/flights-1m.ndjson") {
                let _ = stream.write_all(
                    b"HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nContent-Disposition: attachment; filename=\"file.ndjson\"\r\n\r\n",
                );
                let mut line = String::new();
                let mut reader = BufReader::with_capacity(1024 * 10, file);
                loop {
                    line.clear();
                    let bytes = reader.read_line(&mut line).unwrap_or(0);
                    if bytes == 0 {
                        break;
                    }
                    let _ = stream.write_all(line.as_bytes());
                    let _ = stream.flush();
                }
                drop(line);
                drop(reader);
                return;
            } else {
                let _ =
                    stream.write_all(b"HTTP/1.1 500 Internal Server Error\r\n\r\nFile not found");
                return;
            }
        }

        // Send 404 as default
        let response_body = format!(
            "You requested {} {}\nFrom {} (bytes read: {})\n",
            http_method, http_path, peer_addr, bytes_read
        );
        let response = format!(
            "HTTP/1.1 404 Not Found\r\nContent-Length: {}\r\nConnection: {}\r\nContent-Type: text/plain\r\n\r\n{}",
            response_body.len(),
            connection_header,
            response_body
        );
        println!("Response {}", response_body);
        let _ = stream.write_all(response.as_bytes());

        if connection_header.eq_ignore_ascii_case("close") {
            // If the connection header is "close", close the connection
            close_connection(stream);
            break;
        }
    }

    drop(buf_reader);
}
