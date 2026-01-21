//! GPU Info - Query virtio-gpu driver capabilities
//!
//! This tool queries the virtio-gpu driver to check for Venus/Vulkan support
//! and displays available GPU capabilities.

use std::fs;

fn main() {
    println!("=== GPU Info ===\n");

    // Check if virtio-gpu driver log exists
    let log_paths = [
        "/scheme/logging/fs/pci/virtio-gpud.log",
        "/scheme/9p.hostshare/virtio-gpud-debug.log",
    ];

    for path in &log_paths {
        if let Ok(content) = fs::read_to_string(path) {
            println!("Driver log ({}):", path);
            // Look for feature-related lines
            for line in content.lines() {
                if line.contains("Venus") || line.contains("VIRGL") ||
                   line.contains("BLOB") || line.contains("feature") ||
                   line.contains("capset") {
                    println!("  {}", line);
                }
            }
            println!();
        }
    }

    // Try to read display device info
    if let Ok(entries) = fs::read_dir("/scheme/display.virtio-gpu") {
        println!("Display device: /scheme/display.virtio-gpu");
        println!("  Files:");
        for entry in entries.flatten() {
            println!("    {}", entry.file_name().to_string_lossy());
        }
        println!();
    }

    // Check for 3D/Vulkan scheme (future)
    let venus_paths = [
        "/scheme/vulkan",
        "/scheme/gpu3d",
        "/scheme/venus",
    ];

    for path in &venus_paths {
        if fs::metadata(path).is_ok() {
            println!("Found 3D scheme: {}", path);
        }
    }

    println!("=== End GPU Info ===");
}
