use std::fs::File;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;

fn main() {
    std::thread::spawn(|| {
        let listener = TcpListener::bind("0.0.0.0:3000").expect("Failed to bind");

        println!("🟢 Listening on http://0.0.0.0:3000");

        for stream in listener.incoming() {
            match stream {
                Ok(stream) => {
                    thread::spawn(|| {
                        handle_client(stream);
                    });
                }
                Err(e) => {
                    eprintln!("Connection failed: {}", e);
                }
            }
        }
    });

    loop {
        // std::thread::sleep(std::time::Duration::from_secs(1));
        std::thread::park();
    }
}

fn close_connection(stream: TcpStream) {
    if let Err(e) = stream.shutdown(std::net::Shutdown::Both) {
        eprintln!("Failed to close connection: {}", e);
    }
}

fn handle_client(mut stream: TcpStream) {
    let mut buffer = [0; 1024];
    if stream.read(&mut buffer).is_err() {
        close_connection(stream);
        return;
    }

    if buffer.starts_with(b"GET /health") {
        let response = String::from("HTTP/1.1 200 OK\r\nContent-Length: 13\r\n\r\nHello, world!");
        if let Err(e) = stream.write_all(response.as_bytes()) {
            eprintln!("Failed to write (/health): {e}");
        }
        drop(response);
        close_connection(stream);
        return;
    }
    println!("Request: {}", String::from_utf8_lossy(&buffer));
    if buffer.starts_with(b"GET /ndjson ") {
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
        } else {
            let _ = stream.write_all(b"HTTP/1.1 500 Internal Server Error\r\n\r\nFile not found");
        }
    } else {
        let _ = stream.write_all(b"HTTP/1.1 404 Not Found\r\n\r\nRoute not found");
    }
    close_connection(stream);
}
