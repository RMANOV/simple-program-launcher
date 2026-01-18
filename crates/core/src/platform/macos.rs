//! macOS platform data sources
//!
//! Data sources:
//! - ~/Library/Application Support/com.apple.sharedfilelist for recent files
//! - /Applications/*.app for installed apps
//! - LaunchServices for frequent programs

use crate::config::{ItemType, LaunchItem};
use crate::platform::PlatformDataSource;
use anyhow::{Context, Result};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub struct MacOSDataSource {
    home_dir: PathBuf,
}

impl MacOSDataSource {
    pub fn new() -> Self {
        let home_dir = std::env::var("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("/Users"));
        Self { home_dir }
    }

    /// Scan /Applications for .app bundles
    fn scan_applications(&self) -> Result<Vec<AppInfo>> {
        let mut apps = Vec::new();

        let app_dirs = [
            PathBuf::from("/Applications"),
            PathBuf::from("/System/Applications"),
            self.home_dir.join("Applications"),
        ];

        for app_dir in &app_dirs {
            if !app_dir.exists() {
                continue;
            }

            if let Ok(entries) = fs::read_dir(app_dir) {
                for entry in entries.flatten() {
                    let path = entry.path();
                    if path.extension().is_some_and(|e| e == "app") {
                        if let Some(app_info) = self.parse_app_bundle(&path) {
                            apps.push(app_info);
                        }
                    }
                }
            }
        }

        // Remove duplicates by name
        apps.sort_by(|a, b| a.name.cmp(&b.name));
        apps.dedup_by(|a, b| a.name == b.name);

        Ok(apps)
    }

    /// Parse an .app bundle to extract name and icon
    fn parse_app_bundle(&self, app_path: &Path) -> Option<AppInfo> {
        let info_plist = app_path.join("Contents/Info.plist");

        // Try to get the app name from the bundle name
        let name = app_path
            .file_stem()?
            .to_string_lossy()
            .to_string();

        // Try to parse Info.plist for display name
        let display_name = if info_plist.exists() {
            self.parse_info_plist(&info_plist)
                .and_then(|info| info.get("CFBundleDisplayName").or(info.get("CFBundleName")).cloned())
                .unwrap_or(name.clone())
        } else {
            name.clone()
        };

        Some(AppInfo {
            name: display_name,
            path: app_path.to_string_lossy().to_string(),
            bundle_id: None,
        })
    }

    /// Parse Info.plist file (simplified - just extract key strings)
    fn parse_info_plist(&self, path: &Path) -> Option<HashMap<String, String>> {
        // Use plutil to convert plist to JSON for easier parsing
        let output = Command::new("plutil")
            .args(["-convert", "json", "-o", "-", path.to_str()?])
            .output()
            .ok()?;

        if !output.status.success() {
            return None;
        }

        let json_str = String::from_utf8_lossy(&output.stdout);
        let parsed: serde_json::Value = serde_json::from_str(&json_str).ok()?;

        let mut result = HashMap::new();
        if let serde_json::Value::Object(map) = parsed {
            for (key, value) in map {
                if let serde_json::Value::String(s) = value {
                    result.insert(key, s);
                }
            }
        }

        Some(result)
    }

    /// Get recent files using mdfind (Spotlight)
    fn get_recent_files_spotlight(&self, limit: usize) -> Result<Vec<PathBuf>> {
        // Use mdfind to find recently modified files
        let output = Command::new("mdfind")
            .args([
                "-onlyin", self.home_dir.to_str().unwrap_or("~"),
                "kMDItemLastUsedDate > $time.today(-7)",
            ])
            .output()
            .context("Failed to run mdfind")?;

        if !output.status.success() {
            return Ok(vec![]);
        }

        let stdout = String::from_utf8_lossy(&output.stdout);
        let files: Vec<PathBuf> = stdout
            .lines()
            .filter(|line| !line.is_empty())
            .filter(|line| {
                let path = Path::new(line);
                path.is_file() && !line.contains("/Library/")
            })
            .take(limit)
            .map(PathBuf::from)
            .collect();

        Ok(files)
    }

    /// Get frequently used apps from LaunchServices
    fn get_frequent_from_launch_services(&self, limit: usize) -> Result<Vec<String>> {
        // Try to read launch services database
        // This is a simplified approach - the actual database is more complex
        let ls_path = self.home_dir.join("Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist");

        if !ls_path.exists() {
            return Ok(vec![]);
        }

        // Use defaults to read the plist
        let output = Command::new("defaults")
            .args(["read", ls_path.to_str().unwrap_or_default()])
            .output()
            .ok();

        // For now, return empty - full implementation would parse the plist
        // and extract frequently used handlers
        drop(output);

        Ok(vec![])
    }

    /// Get shell history frequency (zsh on macOS)
    fn get_shell_history_frequency(&self) -> Result<HashMap<String, usize>> {
        let mut frequency: HashMap<String, usize> = HashMap::new();

        // Try zsh history (default on modern macOS)
        let zsh_history = self.home_dir.join(".zsh_history");
        if zsh_history.exists() {
            if let Ok(content) = fs::read_to_string(&zsh_history) {
                for line in content.lines() {
                    // zsh history format: : timestamp:0;command
                    let cmd_part = if line.contains(';') {
                        line.split(';').nth(1).unwrap_or(line)
                    } else {
                        line
                    };
                    if let Some(cmd) = cmd_part.split_whitespace().next() {
                        *frequency.entry(cmd.to_string()).or_default() += 1;
                    }
                }
            }
        }

        // Also try bash history
        let bash_history = self.home_dir.join(".bash_history");
        if bash_history.exists() {
            if let Ok(content) = fs::read_to_string(&bash_history) {
                for line in content.lines() {
                    if let Some(cmd) = line.split_whitespace().next() {
                        *frequency.entry(cmd.to_string()).or_default() += 1;
                    }
                }
            }
        }

        Ok(frequency)
    }
}

impl PlatformDataSource for MacOSDataSource {
    fn recent_files(&self, limit: usize) -> Result<Vec<LaunchItem>> {
        let files = self.get_recent_files_spotlight(limit)?;

        Ok(files
            .into_iter()
            .filter_map(|path| {
                // Skip if file doesn't exist
                if !path.exists() {
                    return None;
                }

                let name = path
                    .file_name()?
                    .to_string_lossy()
                    .to_string();

                Some(LaunchItem {
                    name,
                    path: path.to_string_lossy().to_string(),
                    icon: None,
                    args: vec![],
                    item_type: ItemType::Document,
                })
            })
            .collect())
    }

    fn installed_apps(&self) -> Result<Vec<LaunchItem>> {
        let apps = self.scan_applications()?;

        Ok(apps
            .into_iter()
            .map(|app| LaunchItem {
                name: app.name,
                path: app.path,
                icon: None,
                args: vec![],
                item_type: ItemType::Program,
            })
            .collect())
    }

    fn frequent_programs(&self, limit: usize) -> Result<Vec<LaunchItem>> {
        let frequency = self.get_shell_history_frequency()?;
        let apps = self.installed_apps()?;

        // Create a map of command -> app
        let mut cmd_to_app: HashMap<String, &LaunchItem> = HashMap::new();
        for app in &apps {
            // Extract the base name from the app path
            if let Some(name) = Path::new(&app.path).file_stem() {
                let name_str = name.to_string_lossy().to_lowercase();
                cmd_to_app.insert(name_str, app);
            }
        }

        // Sort by frequency
        let mut freq_vec: Vec<_> = frequency.iter().collect();
        freq_vec.sort_by(|a, b| b.1.cmp(a.1));

        // Get top apps that match shell commands
        let result: Vec<LaunchItem> = freq_vec
            .iter()
            .filter_map(|(cmd, _)| {
                let cmd_lower = cmd.to_lowercase();
                cmd_to_app.get(&cmd_lower).map(|app| (*app).clone())
            })
            .take(limit)
            .collect();

        Ok(result)
    }

    fn launch(&self, item: &LaunchItem) -> Result<()> {
        match item.item_type {
            ItemType::Document => {
                // Use open for documents
                Command::new("open")
                    .arg(&item.path)
                    .spawn()
                    .context("Failed to open document")?;
            }
            ItemType::Program => {
                // Use open -a for applications
                if item.path.ends_with(".app") {
                    Command::new("open")
                        .arg("-a")
                        .arg(&item.path)
                        .args(&item.args)
                        .spawn()
                        .context("Failed to launch application")?;
                } else {
                    Command::new(&item.path)
                        .args(&item.args)
                        .spawn()
                        .context("Failed to launch program")?;
                }
            }
            ItemType::Shortcut => {
                // Execute the command directly
                Command::new(&item.path)
                    .args(&item.args)
                    .spawn()
                    .context("Failed to execute shortcut")?;
            }
        }

        Ok(())
    }
}

#[derive(Debug)]
struct AppInfo {
    name: String,
    path: String,
    bundle_id: Option<String>,
}
