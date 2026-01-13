fn main() {
    println!("Testing pkg library initialization...");
    
    let (install_path, target) = ("/", "aarch64-unknown-redox");
    println!("Install path: {}, Target: {}", install_path, target);
    
    println!("Creating Library...");
    match pkg::Library::new(install_path, target, std::rc::Rc::new(std::cell::RefCell::new(pkg::callback::PlainCallback::new()))) {
        Ok(_lib) => {
            println!("✓ Library created successfully!");
        }
        Err(e) => {
            println!("✗ Failed to create library: {}", e);
        }
    }
    
    println!("Done!");
}
