// Simple package manager for Redox OS
// HTTPS support via pure-Rust rustls-rustcrypto

use std::env;
use std::fs::{self, File};
use std::io::Read;
use std::path::Path;
use std::process;
use std::sync::Arc;

use ureq::{Agent, tls::{TlsConfig, TlsProvider, RootCerts}};

// HTTPS package server
const PKG_SERVER: &str = "https://static.redox-os.org/pkg/aarch64-unknown-redox";
const PKG_DIR: &str = "/pkg";
const LOCAL_PKG: &str = "/scheme/9p.hostshare/packages";

fn create_agent() -> Agent {
    let crypto = Arc::new(rustls_rustcrypto::provider());

    let tls_config = TlsConfig::builder()
        .provider(TlsProvider::Rustls)
        .root_certs(RootCerts::WebPki)
        .unversioned_rustls_crypto_provider(crypto)
        .build();

    Agent::config_builder()
        .tls_config(tls_config)
        .build()
        .new_agent()
}

fn print_usage() {
    eprintln!("Redox Package Manager (simple-pkg) v0.3");
    eprintln!();
    eprintln!("Usage: pkg <command> [args]");
    eprintln!();
    eprintln!("Commands:");
    eprintln!("  list              List installed packages");
    eprintln!("  available         List packages in {}", LOCAL_PKG);
    eprintln!("  install <name>    Install package (from local or remote)");
    eprintln!("  install-local <path>  Install from local .tar.gz file");
    eprintln!("  search <query>    Search remote packages");
    eprintln!("  fetch <url>       Fetch and extract a package from URL");
    eprintln!();
    eprintln!("HTTPS supported via pure-Rust TLS.");
}

fn fetch_url(url: &str) -> Result<Vec<u8>, String> {
    eprintln!("Fetching: {}", url);

    let agent = create_agent();
    let response = agent.get(url)
        .call()
        .map_err(|e| format!("HTTP(S) error: {}", e))?;

    let mut data = Vec::new();
    response.into_body()
        .into_reader()
        .read_to_end(&mut data)
        .map_err(|e| format!("Read error: {}", e))?;

    Ok(data)
}

/// Parse repo.toml format: name = "hash"
fn parse_repo(content: &str) -> Vec<(String, String)> {
    let mut packages = Vec::new();

    for line in content.lines() {
        let line = line.trim();
        // Skip empty lines, comments, and section headers
        if line.is_empty() || line.starts_with('#') || line.starts_with('[') {
            continue;
        }

        // Parse: name = "hash"
        if let Some((name, rest)) = line.split_once('=') {
            let name = name.trim();
            let hash = rest.trim().trim_matches('"').trim_matches('\'');
            if !name.is_empty() && !hash.is_empty() {
                packages.push((name.to_string(), hash.to_string()));
            }
        }
    }

    packages
}

fn list_installed() {
    let pkg_dir = Path::new(PKG_DIR);

    if !pkg_dir.exists() {
        eprintln!("No packages installed (no {} directory)", PKG_DIR);
        return;
    }

    match fs::read_dir(pkg_dir) {
        Ok(entries) => {
            println!("Installed packages:");
            for entry in entries.flatten() {
                if entry.path().is_dir() {
                    println!("  {}", entry.file_name().to_string_lossy());
                }
            }
        }
        Err(e) => eprintln!("Error reading {}: {}", PKG_DIR, e),
    }
}

fn list_available() {
    let local_dir = Path::new(LOCAL_PKG);

    if !local_dir.exists() {
        eprintln!("Local package directory not found: {}", LOCAL_PKG);
        eprintln!("Create it on host at: /opt/other/redox/share/packages/");
        return;
    }

    match fs::read_dir(local_dir) {
        Ok(entries) => {
            println!("Available local packages:");
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                if name.ends_with(".tar.gz") || name.ends_with(".tar") {
                    println!("  {}", name);
                }
            }
        }
        Err(e) => eprintln!("Error reading {}: {}", LOCAL_PKG, e),
    }
}

fn install_local(path: &str) {
    let path = if path.starts_with('/') {
        path.to_string()
    } else {
        format!("{}/{}", LOCAL_PKG, path)
    };

    if !Path::new(&path).exists() {
        eprintln!("File not found: {}", path);
        process::exit(1);
    }

    let name = Path::new(&path)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("package")
        .trim_end_matches(".tar");

    let dest_dir = format!("{}/{}", PKG_DIR, name);
    fs::create_dir_all(&dest_dir).ok();

    eprintln!("Installing {} from {}...", name, path);

    match extract_tar_gz(&path, &dest_dir) {
        Ok(_) => eprintln!("Successfully installed {}", name),
        Err(e) => eprintln!("Error extracting: {}", e),
    }
}

fn search_packages(query: &str) {
    let repo_url = format!("{}/repo.toml", PKG_SERVER);

    match fetch_url(&repo_url) {
        Ok(data) => {
            let content = String::from_utf8_lossy(&data);
            let packages = parse_repo(&content);

            let query_lower = query.to_lowercase();
            let matches: Vec<_> = packages.iter()
                .filter(|(name, _)| {
                    query == "*" || query.is_empty() ||
                    name.to_lowercase().contains(&query_lower)
                })
                .collect();

            println!("Packages matching '{}' ({} found):", query, matches.len());
            for (name, _hash) in matches {
                println!("  {}", name);
            }
        }
        Err(e) => eprintln!("Error fetching repo: {}", e),
    }
}

fn install_package(name: &str) {
    let repo_url = format!("{}/repo.toml", PKG_SERVER);

    let hash = match fetch_url(&repo_url) {
        Ok(data) => {
            let content = String::from_utf8_lossy(&data);
            let packages = parse_repo(&content);
            packages.into_iter()
                .find(|(n, _)| n == name)
                .map(|(_, h)| h)
        }
        Err(e) => {
            eprintln!("Error fetching repo: {}", e);
            None
        }
    };

    let pkg_url = match hash {
        Some(h) => {
            // Format: {server}/{name}/{hash}.tar.gz
            format!("{}/{}/{}.tar.gz", PKG_SERVER, name, h)
        }
        None => {
            eprintln!("Package '{}' not found in repository", name);
            process::exit(1);
        }
    };

    fetch_and_install(&pkg_url, name);
}

fn fetch_and_install(url: &str, name: &str) {
    eprintln!("Installing {} from {}", name, url);

    let data = match fetch_url(url) {
        Ok(d) => d,
        Err(e) => {
            eprintln!("Error fetching package: {}", e);
            process::exit(1);
        }
    };

    eprintln!("Downloaded {} bytes", data.len());

    let tmp_path = format!("/tmp/{}.tar.gz", name);
    if let Err(e) = fs::write(&tmp_path, &data) {
        eprintln!("Error saving package: {}", e);
        process::exit(1);
    }

    let dest_dir = format!("{}/{}", PKG_DIR, name);
    fs::create_dir_all(&dest_dir).ok();

    eprintln!("Extracting to {}...", dest_dir);

    match extract_tar_gz(&tmp_path, &dest_dir) {
        Ok(_) => {
            eprintln!("Successfully installed {}", name);
            fs::remove_file(&tmp_path).ok();
        }
        Err(e) => {
            eprintln!("Error extracting: {}", e);
            eprintln!("Package saved to: {}", tmp_path);
        }
    }
}

fn extract_tar_gz(archive_path: &str, dest: &str) -> Result<(), String> {
    use std::io::BufReader;
    use flate2::read::GzDecoder;

    let file = File::open(archive_path)
        .map_err(|e| format!("Cannot open archive: {}", e))?;

    let reader = BufReader::new(file);

    if archive_path.ends_with(".gz") {
        let decoder = GzDecoder::new(reader);
        let mut archive = tar::Archive::new(decoder);
        archive.unpack(dest)
            .map_err(|e| format!("Extraction failed: {}", e))?;
    } else {
        let mut archive = tar::Archive::new(reader);
        archive.unpack(dest)
            .map_err(|e| format!("Extraction failed: {}", e))?;
    }

    Ok(())
}

fn show_info(name: &str) {
    let repo_url = format!("{}/repo.toml", PKG_SERVER);

    match fetch_url(&repo_url) {
        Ok(data) => {
            let content = String::from_utf8_lossy(&data);
            let packages = parse_repo(&content);

            match packages.iter().find(|(n, _)| n == name) {
                Some((pkg_name, hash)) => {
                    println!("Package: {}", pkg_name);
                    println!("  Hash: {}", hash);
                    println!("  URL: {}/{}/{}.tar.gz", PKG_SERVER, pkg_name, hash);
                }
                None => eprintln!("Package '{}' not found", name),
            }
        }
        Err(e) => eprintln!("Error: {}", e),
    }
}

fn update_repo() {
    let repo_url = format!("{}/repo.toml", PKG_SERVER);

    match fetch_url(&repo_url) {
        Ok(data) => {
            let dest = format!("{}/repo.toml", PKG_DIR);
            fs::create_dir_all(PKG_DIR).ok();

            match fs::write(&dest, &data) {
                Ok(_) => {
                    let packages = parse_repo(&String::from_utf8_lossy(&data));
                    eprintln!("Updated package list: {} packages", packages.len());
                }
                Err(e) => eprintln!("Error saving repo.toml: {}", e),
            }
        }
        Err(e) => eprintln!("Error fetching repo: {}", e),
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        print_usage();
        process::exit(1);
    }

    match args[1].as_str() {
        "list" | "ls" => list_installed(),
        "available" | "avail" => list_available(),
        "search" | "find" => {
            let query = args.get(2).map(|s| s.as_str()).unwrap_or("*");
            search_packages(query);
        }
        "install" | "i" => {
            if args.len() < 3 {
                eprintln!("Usage: pkg install <package>");
                process::exit(1);
            }
            let pkg = &args[2];
            let local_path = format!("{}/{}.tar.gz", LOCAL_PKG, pkg);
            if Path::new(&local_path).exists() {
                install_local(&local_path);
            } else {
                install_package(pkg);
            }
        }
        "install-local" | "il" => {
            if args.len() < 3 {
                eprintln!("Usage: pkg install-local <path>");
                process::exit(1);
            }
            install_local(&args[2]);
        }
        "info" | "show" => {
            if args.len() < 3 {
                eprintln!("Usage: pkg info <package>");
                process::exit(1);
            }
            show_info(&args[2]);
        }
        "fetch" => {
            if args.len() < 3 {
                eprintln!("Usage: pkg fetch <url>");
                process::exit(1);
            }
            fetch_and_install(&args[2], "fetched");
        }
        "update" | "up" => update_repo(),
        "-h" | "--help" | "help" => print_usage(),
        cmd => {
            eprintln!("Unknown command: {}", cmd);
            print_usage();
            process::exit(1);
        }
    }
}
