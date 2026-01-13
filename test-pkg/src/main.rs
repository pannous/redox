fn main() {
    println!("Test 1: Basic startup");
    
    println!("Test 2: Creating callback");
    let callback = std::rc::Rc::new(std::cell::RefCell::new(
        pkg::callback::PlainCallback::new()
    ));
    println!("  Callback created");
    
    println!("Test 3: Setting up paths");
    let install_path = "/";
    let target = "aarch64-unknown-redox";
    println!("  Install: {}, Target: {}", install_path, target);
    
    println!("Test 4: Creating Library");
    match pkg::Library::new(install_path, target, callback) {
        Ok(mut lib) => {
            println!("  ✓ Library created!");
            
            println!("Test 5: Getting package names");
            match lib.get_all_package_names() {
                Ok(names) => println!("  ✓ Got {} package names", names.len()),
                Err(e) => println!("  ✗ Failed: {}", e),
            }
        }
        Err(e) => {
            println!("  ✗ Failed to create library: {}", e);
        }
    }
    
    println!("Done!");
}
