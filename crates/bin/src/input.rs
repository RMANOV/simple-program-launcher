//! Mouse input listener using evdev for Linux (works on both X11 and Wayland)

use evdev::{Device, InputEventKind, Key};
use std::os::unix::io::AsRawFd;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

/// Trigger event sent when L+R click is detected
#[derive(Debug, Clone)]
pub struct TriggerEvent {
    /// Mouse position at trigger time (always 0,0 with evdev - use cursor position from GUI)
    pub position: (f64, f64),
    /// Timestamp
    pub timestamp: Instant,
}

/// Mouse state tracker
struct MouseState {
    left_pressed: Option<Instant>,
    right_pressed: Option<Instant>,
    last_trigger: Option<Instant>,
}

impl Default for MouseState {
    fn default() -> Self {
        Self {
            left_pressed: None,
            right_pressed: None,
            last_trigger: None,
        }
    }
}

/// Find all mouse devices (devices that support BTN_LEFT)
fn find_mouse_devices() -> Vec<Device> {
    evdev::enumerate()
        .filter_map(|(_, device)| {
            if let Some(keys) = device.supported_keys() {
                if keys.contains(Key::BTN_LEFT) {
                    log::info!("Found mouse device: {:?}", device.name());
                    return Some(device);
                }
            }
            None
        })
        .collect()
}

/// Input listener that detects simultaneous L+R mouse clicks
pub struct InputListener {
    state: Arc<Mutex<MouseState>>,
    simultaneous_threshold: Duration,
    debounce_duration: Duration,
    trigger_tx: Sender<TriggerEvent>,
}

impl InputListener {
    /// Create a new input listener
    ///
    /// # Arguments
    /// * `simultaneous_threshold_ms` - Maximum time between L and R clicks to count as simultaneous
    /// * `debounce_ms` - Minimum time between triggers to prevent accidental double-triggers
    pub fn new(simultaneous_threshold_ms: u64, debounce_ms: u64) -> (Self, Receiver<TriggerEvent>) {
        let (trigger_tx, trigger_rx) = channel();

        let listener = Self {
            state: Arc::new(Mutex::new(MouseState::default())),
            simultaneous_threshold: Duration::from_millis(simultaneous_threshold_ms),
            debounce_duration: Duration::from_millis(debounce_ms),
            trigger_tx,
        };

        (listener, trigger_rx)
    }

    /// Check if both buttons are pressed within the threshold
    fn check_trigger(&self) -> Option<TriggerEvent> {
        let mut state = self.state.lock().ok()?;

        let (left_time, right_time) = match (state.left_pressed, state.right_pressed) {
            (Some(l), Some(r)) => (l, r),
            _ => return None,
        };

        // Check if both buttons were pressed within the threshold
        let diff = if left_time > right_time {
            left_time.duration_since(right_time)
        } else {
            right_time.duration_since(left_time)
        };

        if diff > self.simultaneous_threshold {
            return None;
        }

        // Check debounce
        let now = Instant::now();
        if let Some(last) = state.last_trigger {
            if now.duration_since(last) < self.debounce_duration {
                return None;
            }
        }

        // Trigger!
        state.last_trigger = Some(now);

        // Clear button states to prevent re-triggering
        state.left_pressed = None;
        state.right_pressed = None;

        Some(TriggerEvent {
            position: (0.0, 0.0), // evdev doesn't provide absolute position
            timestamp: now,
        })
    }

    /// Handle a button event
    fn handle_button(&self, key: Key, pressed: bool) {
        match key {
            Key::BTN_LEFT => {
                if let Ok(mut state) = self.state.lock() {
                    state.left_pressed = if pressed { Some(Instant::now()) } else { None };
                }
                if pressed {
                    if let Some(trigger) = self.check_trigger() {
                        let _ = self.trigger_tx.send(trigger);
                    }
                }
            }
            Key::BTN_RIGHT => {
                if let Ok(mut state) = self.state.lock() {
                    state.right_pressed = if pressed { Some(Instant::now()) } else { None };
                }
                if pressed {
                    if let Some(trigger) = self.check_trigger() {
                        let _ = self.trigger_tx.send(trigger);
                    }
                }
            }
            _ => {}
        }
    }

    /// Start listening for mouse events
    ///
    /// This spawns a background thread that processes events and returns immediately.
    /// The thread will run until the process exits.
    ///
    /// Note: Requires read access to /dev/input/event* devices.
    /// User typically needs to be in the 'input' group: sudo usermod -aG input $USER
    pub fn start(self) -> thread::JoinHandle<()> {
        thread::spawn(move || {
            log::info!("Starting evdev mouse event listener...");

            let mut devices = find_mouse_devices();

            if devices.is_empty() {
                log::error!(
                    "No mouse devices found. Make sure you have read access to /dev/input/event*. \
                     Try: sudo usermod -aG input $USER (then log out and back in)"
                );
                return;
            }

            log::info!("Monitoring {} mouse device(s)", devices.len());

            // Set devices to non-blocking mode using fcntl
            for device in &devices {
                let fd = device.as_raw_fd();
                unsafe {
                    let flags = libc::fcntl(fd, libc::F_GETFL);
                    if flags >= 0 {
                        libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK);
                    }
                }
            }

            loop {
                let mut had_events = false;

                for device in &mut devices {
                    if let Ok(events) = device.fetch_events() {
                        for event in events {
                            if let InputEventKind::Key(key) = event.kind() {
                                // value: 1 = press, 0 = release
                                let pressed = event.value() == 1;
                                self.handle_button(key, pressed);
                                had_events = true;
                            }
                        }
                    }
                }

                // Sleep a bit if no events to avoid busy-waiting
                if !had_events {
                    thread::sleep(Duration::from_millis(10));
                }
            }
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_trigger_detection() {
        let (listener, rx) = InputListener::new(50, 500);

        // Simulate left press
        listener.handle_button(Key::BTN_LEFT, true);

        // Simulate right press within threshold
        listener.handle_button(Key::BTN_RIGHT, true);

        // Should receive trigger
        assert!(rx.try_recv().is_ok());
    }

    #[test]
    fn test_debounce() {
        let (listener, rx) = InputListener::new(50, 1000);

        // First trigger
        listener.handle_button(Key::BTN_LEFT, true);
        listener.handle_button(Key::BTN_RIGHT, true);

        assert!(rx.try_recv().is_ok());

        // Release buttons
        listener.handle_button(Key::BTN_LEFT, false);
        listener.handle_button(Key::BTN_RIGHT, false);

        // Try to trigger again immediately (should be debounced)
        listener.handle_button(Key::BTN_LEFT, true);
        listener.handle_button(Key::BTN_RIGHT, true);

        assert!(rx.try_recv().is_err()); // Should be debounced
    }
}
