//! Mouse input listener using rdev for cross-platform event capture

use rdev::{listen, Button, Event, EventType};
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

/// Trigger event sent when L+R click is detected
#[derive(Debug, Clone)]
pub struct TriggerEvent {
    /// Mouse position at trigger time
    pub position: (f64, f64),
    /// Timestamp
    pub timestamp: Instant,
}

/// Mouse state tracker
struct MouseState {
    left_pressed: Option<Instant>,
    right_pressed: Option<Instant>,
    last_position: (f64, f64),
    last_trigger: Option<Instant>,
}

impl Default for MouseState {
    fn default() -> Self {
        Self {
            left_pressed: None,
            right_pressed: None,
            last_position: (0.0, 0.0),
            last_trigger: None,
        }
    }
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
            position: state.last_position,
            timestamp: now,
        })
    }

    /// Handle a mouse event
    fn handle_event(&self, event: &Event) {
        match event.event_type {
            EventType::ButtonPress(Button::Left) => {
                if let Ok(mut state) = self.state.lock() {
                    state.left_pressed = Some(Instant::now());
                }
                if let Some(trigger) = self.check_trigger() {
                    let _ = self.trigger_tx.send(trigger);
                }
            }
            EventType::ButtonPress(Button::Right) => {
                if let Ok(mut state) = self.state.lock() {
                    state.right_pressed = Some(Instant::now());
                }
                if let Some(trigger) = self.check_trigger() {
                    let _ = self.trigger_tx.send(trigger);
                }
            }
            EventType::ButtonRelease(Button::Left) => {
                if let Ok(mut state) = self.state.lock() {
                    state.left_pressed = None;
                }
            }
            EventType::ButtonRelease(Button::Right) => {
                if let Ok(mut state) = self.state.lock() {
                    state.right_pressed = None;
                }
            }
            EventType::MouseMove { x, y } => {
                if let Ok(mut state) = self.state.lock() {
                    state.last_position = (x, y);
                }
            }
            _ => {}
        }
    }

    /// Start listening for mouse events (blocking)
    ///
    /// This spawns a background thread that processes events and returns immediately.
    /// The thread will run until the process exits.
    pub fn start(self) -> thread::JoinHandle<()> {
        let state = self.state.clone();
        let threshold = self.simultaneous_threshold;
        let debounce = self.debounce_duration;
        let trigger_tx = self.trigger_tx.clone();

        thread::spawn(move || {
            let listener = InputListener {
                state,
                simultaneous_threshold: threshold,
                debounce_duration: debounce,
                trigger_tx,
            };

            log::info!("Starting mouse event listener...");

            if let Err(e) = listen(move |event| {
                listener.handle_event(&event);
            }) {
                log::error!("Failed to listen for events: {:?}", e);
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
        listener.handle_event(&Event {
            time: std::time::SystemTime::now(),
            name: None,
            event_type: EventType::ButtonPress(Button::Left),
        });

        // Simulate right press within threshold
        listener.handle_event(&Event {
            time: std::time::SystemTime::now(),
            name: None,
            event_type: EventType::ButtonPress(Button::Right),
        });

        // Should receive trigger
        assert!(rx.try_recv().is_ok());
    }

    #[test]
    fn test_debounce() {
        let (listener, rx) = InputListener::new(50, 1000);

        // First trigger
        listener.handle_event(&Event {
            time: std::time::SystemTime::now(),
            name: None,
            event_type: EventType::ButtonPress(Button::Left),
        });
        listener.handle_event(&Event {
            time: std::time::SystemTime::now(),
            name: None,
            event_type: EventType::ButtonPress(Button::Right),
        });

        assert!(rx.try_recv().is_ok());

        // Release buttons
        listener.handle_event(&Event {
            time: std::time::SystemTime::now(),
            name: None,
            event_type: EventType::ButtonRelease(Button::Left),
        });
        listener.handle_event(&Event {
            time: std::time::SystemTime::now(),
            name: None,
            event_type: EventType::ButtonRelease(Button::Right),
        });

        // Try to trigger again immediately (should be debounced)
        listener.handle_event(&Event {
            time: std::time::SystemTime::now(),
            name: None,
            event_type: EventType::ButtonPress(Button::Left),
        });
        listener.handle_event(&Event {
            time: std::time::SystemTime::now(),
            name: None,
            event_type: EventType::ButtonPress(Button::Right),
        });

        assert!(rx.try_recv().is_err()); // Should be debounced
    }
}
