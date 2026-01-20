//! Simple Program Launcher
//!
//! Cross-platform program launcher triggered by simultaneous L+R mouse click.

mod input;

use anyhow::{Context, Result};
use input::InputListener;
use launcher_core::{ConfigManager, UsageTracker};
use launcher_ui::run_popup;
use std::sync::{Arc, Mutex};

fn main() -> Result<()> {
    // Initialize logging
    env_logger::Builder::from_env(
        env_logger::Env::default().default_filter_or("info"),
    )
    .format_timestamp_secs()
    .init();

    log::info!("Starting Simple Program Launcher");

    // Load configuration
    let config_manager = Arc::new(
        ConfigManager::new().context("Failed to initialize config manager")?,
    );

    // Initialize usage tracker
    let usage_tracker = Arc::new(Mutex::new(
        UsageTracker::new().context("Failed to initialize usage tracker")?,
    ));

    // Get trigger settings
    let (simultaneous_threshold, debounce) = {
        let config = config_manager.get();
        (
            config.trigger.simultaneous_threshold_ms,
            config.trigger.debounce_ms,
        )
    };

    // Create input listener
    let (listener, trigger_rx) = InputListener::new(simultaneous_threshold, debounce);

    // Start listening for mouse events
    let _listener_handle = listener.start();

    log::info!(
        "Listening for L+R click (threshold: {}ms, debounce: {}ms)",
        simultaneous_threshold,
        debounce
    );
    log::info!("Press Ctrl+C to exit");

    // Main event loop - wait for triggers
    loop {
        match trigger_rx.recv() {
            Ok(trigger) => {
                log::info!(
                    "Trigger detected at position ({:.0}, {:.0})",
                    trigger.position.0,
                    trigger.position.1
                );

                // Show the popup window on main thread (required by winit)
                if let Err(e) = run_popup(trigger.position, config_manager.clone(), usage_tracker.clone()) {
                    log::error!("Popup error: {}", e);
                }
            }
            Err(e) => {
                log::error!("Trigger channel error: {}", e);
                break;
            }
        }
    }

    Ok(())
}
