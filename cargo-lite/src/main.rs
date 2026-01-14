//! cargo-lite: Minimal offline Rust build tool for Redox
//!
//! Supports:
//! - Building single crates with local (path) dependencies
//! - No network access required
//! - Pure Rust implementation

use serde::Deserialize;
use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

#[derive(Debug, Deserialize)]
struct CargoToml {
    package: Package,
    #[serde(default)]
    dependencies: HashMap<String, Dependency>,
    #[serde(default)]
    lib: Option<LibTarget>,
    #[serde(default, rename = "bin")]
    bins: Vec<BinTarget>,
}

#[derive(Debug, Deserialize)]
struct Package {
    name: String,
    #[serde(default)]
    version: String,
    #[serde(default)]
    edition: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum Dependency {
    Version(String),
    Detailed(DetailedDep),
}

#[derive(Debug, Deserialize)]
struct DetailedDep {
    #[serde(default)]
    version: Option<String>,
    #[serde(default)]
    path: Option<String>,
    #[serde(default)]
    features: Vec<String>,
    #[serde(default)]
    optional: bool,
}

#[derive(Debug, Deserialize)]
struct LibTarget {
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    path: Option<String>,
}

#[derive(Debug, Deserialize)]
struct BinTarget {
    name: String,
    #[serde(default)]
    path: Option<String>,
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        print_help();
        return ExitCode::from(1);
    }

    // Handle "cargo lite build" style invocation
    let cmd = if args[1] == "lite" && args.len() > 2 {
        &args[2]
    } else {
        &args[1]
    };

    let result = match cmd.as_str() {
        "build" | "b" => cmd_build(false),
        "run" | "r" => cmd_build(true),
        "check" | "c" => cmd_check(),
        "--version" | "-V" => {
            println!("cargo-lite 0.1.0");
            Ok(())
        }
        "--help" | "-h" | "help" => {
            print_help();
            Ok(())
        }
        _ => {
            eprintln!("Unknown command: {}", cmd);
            print_help();
            Err("Unknown command".into())
        }
    };

    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("Error: {}", e);
            ExitCode::from(1)
        }
    }
}

fn print_help() {
    println!("cargo-lite 0.1.0 - Minimal offline Rust build tool");
    println!();
    println!("USAGE:");
    println!("    cargo-lite <COMMAND>");
    println!();
    println!("COMMANDS:");
    println!("    build, b    Compile the current package");
    println!("    run, r      Build and run the current package");
    println!("    check, c    Check the current package for errors");
    println!("    help        Show this help message");
    println!();
    println!("NOTE: Only supports local (path) dependencies.");
    println!("      For crates.io dependencies, pre-vendor them first.");
}

fn cmd_build(run_after: bool) -> Result<(), Box<dyn std::error::Error>> {
    let manifest = load_manifest(".")?;
    let output_dir = PathBuf::from("target/release");
    fs::create_dir_all(&output_dir)?;

    // Collect path dependencies
    let mut extern_args = Vec::new();
    let mut dep_libs = Vec::new();

    for (name, dep) in &manifest.dependencies {
        if let Some(path) = get_dep_path(dep) {
            println!("   Compiling dependency {} (path: {})", name, path);
            let lib_path = build_dependency(&path, &name, &output_dir)?;
            let crate_name = name.replace('-', "_");
            extern_args.push(format!("--extern"));
            extern_args.push(format!("{}={}", crate_name, lib_path.display()));
            dep_libs.push(lib_path);
        } else {
            eprintln!("Warning: Skipping non-path dependency: {}", name);
        }
    }

    // Determine source file
    let src_path = find_main_source(&manifest)?;
    let output_name = &manifest.package.name;
    let output_path = output_dir.join(output_name);

    println!("   Compiling {} v{}", manifest.package.name, manifest.package.version);

    let mut cmd = Command::new("rustc");
    cmd.arg(&src_path)
        .arg("-o")
        .arg(&output_path)
        .arg("--edition")
        .arg(manifest.package.edition.as_deref().unwrap_or("2021"))
        .arg("-C")
        .arg("opt-level=2")
        .arg("-L")
        .arg(&output_dir);

    for arg in extern_args {
        cmd.arg(arg);
    }

    let status = cmd.status()?;

    if !status.success() {
        return Err(format!("rustc failed with {}", status).into());
    }

    println!("    Finished release [optimized] target");
    println!("     Created {}", output_path.display());

    if run_after {
        println!("     Running `{}`", output_path.display());
        let status = Command::new(&output_path).status()?;
        if !status.success() {
            return Err(format!("Process exited with {}", status).into());
        }
    }

    Ok(())
}

fn cmd_check() -> Result<(), Box<dyn std::error::Error>> {
    let manifest = load_manifest(".")?;
    let src_path = find_main_source(&manifest)?;

    println!("    Checking {} v{}", manifest.package.name, manifest.package.version);

    let status = Command::new("rustc")
        .arg(&src_path)
        .arg("--emit=metadata")
        .arg("--edition")
        .arg(manifest.package.edition.as_deref().unwrap_or("2021"))
        .arg("-o")
        .arg("/dev/null")
        .status()?;

    if !status.success() {
        return Err("Check failed".into());
    }

    println!("    Finished checking");
    Ok(())
}

fn load_manifest(dir: &str) -> Result<CargoToml, Box<dyn std::error::Error>> {
    let path = Path::new(dir).join("Cargo.toml");
    let content = fs::read_to_string(&path)
        .map_err(|e| format!("Failed to read {}: {}", path.display(), e))?;
    let manifest: CargoToml = toml::from_str(&content)
        .map_err(|e| format!("Failed to parse {}: {}", path.display(), e))?;
    Ok(manifest)
}

fn find_main_source(manifest: &CargoToml) -> Result<PathBuf, Box<dyn std::error::Error>> {
    // Check for explicit bin target
    if !manifest.bins.is_empty() {
        if let Some(path) = &manifest.bins[0].path {
            return Ok(PathBuf::from(path));
        }
    }

    // Check standard locations
    for path in &["src/main.rs", "main.rs", "src/lib.rs"] {
        if Path::new(path).exists() {
            return Ok(PathBuf::from(path));
        }
    }

    Err("No main.rs or lib.rs found".into())
}

fn get_dep_path(dep: &Dependency) -> Option<String> {
    match dep {
        Dependency::Detailed(d) => d.path.clone(),
        Dependency::Version(_) => None,
    }
}

fn build_dependency(
    dep_path: &str,
    name: &str,
    output_dir: &Path,
) -> Result<PathBuf, Box<dyn std::error::Error>> {
    let manifest = load_manifest(dep_path)?;

    // Find lib source
    let lib_src = if let Some(lib) = &manifest.lib {
        lib.path.clone().unwrap_or_else(|| "src/lib.rs".to_string())
    } else {
        "src/lib.rs".to_string()
    };

    let src_path = Path::new(dep_path).join(&lib_src);
    if !src_path.exists() {
        return Err(format!("Library source not found: {}", src_path.display()).into());
    }

    let crate_name = name.replace('-', "_");
    let lib_name = format!("lib{}.rlib", crate_name);
    let lib_path = output_dir.join(&lib_name);

    let status = Command::new("rustc")
        .arg(&src_path)
        .arg("--crate-type=rlib")
        .arg("--crate-name")
        .arg(&crate_name)
        .arg("-o")
        .arg(&lib_path)
        .arg("--edition")
        .arg(manifest.package.edition.as_deref().unwrap_or("2021"))
        .arg("-C")
        .arg("opt-level=2")
        .status()?;

    if !status.success() {
        return Err(format!("Failed to build dependency: {}", name).into());
    }

    Ok(lib_path)
}
