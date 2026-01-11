use std::env;
use std::io::{self, Write, BufRead};
use std::process::{Command, Stdio};

fn main() {
    let stdin = io::stdin();
    let mut stdout = io::stdout();

    loop {
        // Print prompt
        let cwd = env::current_dir()
            .map(|p| p.display().to_string())
            .unwrap_or_else(|_| "?".into());
        print!("{}$ ", cwd);
        stdout.flush().ok();

        // Read line
        let mut line = String::new();
        if stdin.lock().read_line(&mut line).unwrap_or(0) == 0 {
            break; // EOF
        }

        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.is_empty() {
            continue;
        }

        match parts[0] {
            "exit" | "quit" => break,
            "cd" => {
                let target = parts.get(1).copied().unwrap_or("~");
                let target = if target == "~" {
                    env::var("HOME").unwrap_or_else(|_| "/".into())
                } else {
                    target.to_string()
                };
                if let Err(e) = env::set_current_dir(&target) {
                    eprintln!("cd: {}: {}", target, e);
                }
            }
            "pwd" => match env::current_dir() {
                Ok(p) => println!("{}", p.display()),
                Err(e) => eprintln!("pwd: {}", e),
            },
            "export" => {
                if let Some(arg) = parts.get(1) {
                    if let Some((k, v)) = arg.split_once('=') {
                        env::set_var(k, v);
                    }
                }
            }
            cmd => {
                // Run external command
                match Command::new(cmd)
                    .args(&parts[1..])
                    .stdin(Stdio::inherit())
                    .stdout(Stdio::inherit())
                    .stderr(Stdio::inherit())
                    .spawn()
                {
                    Ok(mut child) => {
                        let _ = child.wait();
                    }
                    Err(e) => eprintln!("{}: {}", cmd, e),
                }
            }
        }
    }
}
