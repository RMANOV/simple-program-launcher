//! macOS platform data sources (placeholder for cross-platform support)
//!
//! Data sources:
//! - ~/Library/Preferences/com.apple.recentitems.plist
//! - /Applications/*.app/Contents/Info.plist
//! - LaunchServices database

use crate::config::LaunchItem;
use crate::platform::PlatformDataSource;
use anyhow::Result;

pub struct MacOSDataSource;

impl MacOSDataSource {
    pub fn new() -> Self {
        Self
    }
}

impl PlatformDataSource for MacOSDataSource {
    fn recent_files(&self, _limit: usize) -> Result<Vec<LaunchItem>> {
        // TODO: Parse com.apple.recentitems.plist
        Ok(vec![])
    }

    fn installed_apps(&self) -> Result<Vec<LaunchItem>> {
        // TODO: Scan /Applications for .app bundles
        Ok(vec![])
    }

    fn frequent_programs(&self, _limit: usize) -> Result<Vec<LaunchItem>> {
        // TODO: Use LaunchServices database
        Ok(vec![])
    }

    fn launch(&self, item: &LaunchItem) -> Result<()> {
        use std::process::Command;

        Command::new("open")
            .arg(&item.path)
            .args(&item.args)
            .spawn()?;

        Ok(())
    }
}
