//! Minimal config TOML parser for Redox builds
//! Lists packages from config files with include resolution

use serde::Deserialize;
use std::collections::{BTreeMap, HashSet};
use std::path::{Path, PathBuf};
use std::{env, fs};

#[derive(Clone, Debug, Default, Deserialize)]
#[serde(untagged)]
enum PackageConfig {
    #[default]
    Empty,
    Build(String),
    Spec {
        #[allow(dead_code)]
        version: Option<String>,
        #[allow(dead_code)]
        git: Option<String>,
        #[allow(dead_code)]
        path: Option<String>,
    },
}

#[derive(Clone, Debug, Default, Deserialize)]
struct Config {
    #[serde(default)]
    include: Vec<PathBuf>,
    #[serde(default)]
    packages: BTreeMap<String, PackageConfig>,
}

impl Config {
    fn from_file(path: &Path) -> Result<Self, String> {
        let mut visited = HashSet::new();
        Self::from_file_inner(path, &mut visited)
    }

    fn from_file_inner(path: &Path, visited: &mut HashSet<PathBuf>) -> Result<Self, String> {
        // Canonicalize to detect cycles
        let canonical = path.canonicalize()
            .unwrap_or_else(|_| path.to_path_buf());

        if !visited.insert(canonical.clone()) {
            // Already visited - skip to break cycle
            return Ok(Config::default());
        }

        let data = fs::read_to_string(path)
            .map_err(|e| format!("{}: {}", path.display(), e))?;

        let mut config: Config = toml::from_str(&data)
            .map_err(|e| format!("{}: {}", path.display(), e))?;

        let config_dir = path.parent().unwrap_or(Path::new("."));

        // Process includes
        let includes = std::mem::take(&mut config.include);
        for inc_path in includes {
            let full_path = config_dir.join(&inc_path);
            match Config::from_file_inner(&full_path, visited) {
                Ok(inc_config) => config.merge(inc_config),
                Err(e) => eprintln!("Warning: {}", e),
            }
        }

        Ok(config)
    }

    fn merge(&mut self, other: Config) {
        for (pkg, pkg_config) in other.packages {
            self.packages.entry(pkg).or_insert(pkg_config);
        }
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() < 2 {
        eprintln!("Usage: {} <config.toml> [--json|--shell]", args[0]);
        eprintln!("\nLists packages from Redox config TOML files.");
        eprintln!("Resolves 'include' directives recursively.");
        std::process::exit(1);
    }

    let config_path = Path::new(&args[1]);
    let output_format = args.get(2).map(|s| s.as_str()).unwrap_or("--plain");

    let config = match Config::from_file(config_path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Error: {}", e);
            std::process::exit(1);
        }
    };

    let packages: Vec<&String> = config.packages.iter()
        .filter_map(|(name, pkg)| {
            match pkg {
                PackageConfig::Build(rule) if rule == "ignore" => None,
                _ => Some(name),
            }
        })
        .collect();

    match output_format {
        "--json" => {
            print!("[");
            for (i, pkg) in packages.iter().enumerate() {
                if i > 0 { print!(","); }
                print!("\"{}\"", pkg);
            }
            println!("]");
        }
        "--shell" => {
            // Output as shell array
            print!("(");
            for (i, pkg) in packages.iter().enumerate() {
                if i > 0 { print!(" "); }
                print!("{}", pkg);
            }
            println!(")");
        }
        _ => {
            for pkg in packages {
                println!("{}", pkg);
            }
        }
    }
}
