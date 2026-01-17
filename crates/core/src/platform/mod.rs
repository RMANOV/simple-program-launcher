//! Platform-specific data sources for recent files and installed applications

#[cfg(target_os = "linux")]
pub mod linux;

#[cfg(target_os = "windows")]
pub mod windows;

#[cfg(target_os = "macos")]
pub mod macos;

use crate::config::LaunchItem;
use anyhow::Result;

/// Platform-agnostic interface for data sources
pub trait PlatformDataSource {
    /// Get recently used files
    fn recent_files(&self, limit: usize) -> Result<Vec<LaunchItem>>;

    /// Get installed applications
    fn installed_apps(&self) -> Result<Vec<LaunchItem>>;

    /// Get frequently used programs (from shell history, etc.)
    fn frequent_programs(&self, limit: usize) -> Result<Vec<LaunchItem>>;

    /// Launch an item
    fn launch(&self, item: &LaunchItem) -> Result<()>;
}

/// Get the platform-specific data source
#[cfg(target_os = "linux")]
pub fn get_data_source() -> impl PlatformDataSource {
    linux::LinuxDataSource::new()
}

#[cfg(target_os = "windows")]
pub fn get_data_source() -> impl PlatformDataSource {
    windows::WindowsDataSource::new()
}

#[cfg(target_os = "macos")]
pub fn get_data_source() -> impl PlatformDataSource {
    macos::MacOSDataSource::new()
}
