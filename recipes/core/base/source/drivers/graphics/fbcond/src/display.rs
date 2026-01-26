use console_draw::{TextScreen, V2DisplayMap};
use drm::buffer::Buffer;
use drm::control::Device;
use graphics_ipc::v2::{Damage, V2GraphicsHandle};
use inputd::ConsumerHandle;
use std::io;

pub struct Display {
    pub input_handle: ConsumerHandle,
    pub map: Option<V2DisplayMap>,
}

impl Display {
    pub fn open_new_vt() -> io::Result<Self> {
        let input_handle = ConsumerHandle::new_vt()?;
        let mut display = Self {
            input_handle,
            map: None,
        };
        display.reopen_for_handoff();
        Ok(display)
    }

    /// Re-open the display after a handoff.
    pub fn reopen_for_handoff(&mut self) {
        let display_file = match self.input_handle.open_display_v2() {
            Ok(f) => f,
            Err(_) => return,
        };

        let new_display_handle = match V2GraphicsHandle::from_file(display_file) {
            Ok(h) => h,
            Err(_) => return,
        };

        let first_display = match new_display_handle.first_display() {
            Ok(d) => d,
            Err(_) => return,
        };

        let connector = match new_display_handle.get_connector(first_display, true) {
            Ok(c) => c,
            Err(_) => return,
        };

        let modes = connector.modes();
        if modes.is_empty() {
            return;
        }
        let (width, height) = modes[0].size();

        if let Ok(map) = V2DisplayMap::new(new_display_handle, width.into(), height.into()) {
            self.map = Some(map);
        }
    }

    pub fn handle_resize(map: &mut V2DisplayMap, text_screen: &mut TextScreen) {
        let (width, height) = match map.display_handle.first_display().and_then(|handle| {
            Ok(map.display_handle.get_connector(handle, true)?.modes()[0].size())
        }) {
            Ok((width, height)) => (width.into(), height.into()),
            Err(err) => {
                log::error!("fbcond: failed to get display size: {}", err);
                map.fb.size()
            }
        };

        if (width, height) != map.fb.size() {
            if let Err(err) = text_screen.resize(map, width, height) {
                log::error!("fbcond: failed to create or map framebuffer: {}", err);
                return;
            }
        }
    }

    pub fn sync_rect(&mut self, damage: Damage) {
        if let Some(map) = &self.map {
            map.display_handle
                .update_plane(0, u32::from(map.fb.handle()), damage)
                .unwrap();
        }
    }
}
