//! Core library for the program launcher
//!
//! Provides configuration management, usage tracking, and platform-specific data sources.

pub mod config;
pub mod platform;
pub mod usage;

pub use config::{Config, ConfigManager, ItemType, LaunchItem};
pub use platform::PlatformDataSource;
pub use usage::{UsageData, UsageRecord, UsageTracker};
