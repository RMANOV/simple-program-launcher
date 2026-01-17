//! Windows platform data sources (placeholder for cross-platform support)
//!
//! Data sources:
//! - %APPDATA%\Microsoft\Windows\Recent\ - .lnk files
//! - Jump Lists (automaticDestinations-ms)
//! - Registry MRU keys

use crate::config::LaunchItem;
use crate::platform::PlatformDataSource;
use anyhow::Result;

pub struct WindowsDataSource;

impl WindowsDataSource {
    pub fn new() -> Self {
        Self
    }
}

impl PlatformDataSource for WindowsDataSource {
    fn recent_files(&self, _limit: usize) -> Result<Vec<LaunchItem>> {
        // TODO: Parse .lnk files from Recent folder
        Ok(vec![])
    }

    fn installed_apps(&self) -> Result<Vec<LaunchItem>> {
        // TODO: Read from Start Menu and registry
        Ok(vec![])
    }

    fn frequent_programs(&self, _limit: usize) -> Result<Vec<LaunchItem>> {
        // TODO: Parse Jump Lists
        Ok(vec![])
    }

    fn launch(&self, item: &LaunchItem) -> Result<()> {
        use std::process::Command;

        Command::new("cmd")
            .args(["/C", "start", "", &item.path])
            .args(&item.args)
            .spawn()?;

        Ok(())
    }
}
