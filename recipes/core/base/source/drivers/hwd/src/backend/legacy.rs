use std::error::Error;

use super::Backend;

#[allow(dead_code)]
pub struct LegacyBackend;

impl Backend for LegacyBackend {
    fn new() -> Result<Self, Box<dyn Error>> {
        Ok(Self)
    }

    fn probe(&mut self) -> Result<(), Box<dyn Error>> {
        log::info!("TODO: handle driver spawning from legacy backend");
        Ok(())
    }
}
