//! Linux platform data sources
//! - Recent files from ~/.local/share/recently-used.xbel
//! - Installed apps from .desktop files
//! - Shell history for frequent programs

use crate::config::{ItemType, LaunchItem};
use crate::platform::PlatformDataSource;
use anyhow::{Context, Result};
use quick_xml::events::Event;
use quick_xml::Reader;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub struct LinuxDataSource {
    home_dir: PathBuf,
}

impl LinuxDataSource {
    pub fn new() -> Self {
        let home_dir = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/home"));
        Self { home_dir }
    }

    /// Parse recently-used.xbel file
    fn parse_recently_used(&self) -> Result<Vec<RecentItem>> {
        let xbel_path = self
            .home_dir
            .join(".local/share/recently-used.xbel");

        if !xbel_path.exists() {
            return Ok(vec![]);
        }

        let content = fs::read_to_string(&xbel_path)
            .with_context(|| format!("Failed to read {:?}", xbel_path))?;

        let mut reader = Reader::from_str(&content);
        reader.config_mut().trim_text(true);

        let mut items = Vec::new();
        let mut current_item: Option<RecentItem> = None;

        loop {
            match reader.read_event() {
                Ok(Event::Start(e)) if e.name().as_ref() == b"bookmark" => {
                    let mut item = RecentItem::default();
                    for attr in e.attributes().flatten() {
                        match attr.key.as_ref() {
                            b"href" => {
                                item.href = String::from_utf8_lossy(&attr.value).to_string();
                            }
                            b"modified" => {
                                item.modified = String::from_utf8_lossy(&attr.value).to_string();
                            }
                            _ => {}
                        }
                    }
                    current_item = Some(item);
                }
                Ok(Event::Start(e)) if e.name().as_ref() == b"mime:mime-type" => {
                    if let Some(ref mut item) = current_item {
                        for attr in e.attributes().flatten() {
                            if attr.key.as_ref() == b"type" {
                                item.mime_type = String::from_utf8_lossy(&attr.value).to_string();
                            }
                        }
                    }
                }
                Ok(Event::End(e)) if e.name().as_ref() == b"bookmark" => {
                    if let Some(item) = current_item.take() {
                        items.push(item);
                    }
                }
                Ok(Event::Eof) => break,
                Err(e) => {
                    log::warn!("Error parsing recently-used.xbel: {}", e);
                    break;
                }
                _ => {}
            }
        }

        // Sort by modification time (newest first)
        items.sort_by(|a, b| b.modified.cmp(&a.modified));

        Ok(items)
    }

    /// Parse .desktop files from standard locations
    fn parse_desktop_files(&self) -> Result<Vec<DesktopEntry>> {
        let search_paths = [
            PathBuf::from("/usr/share/applications"),
            PathBuf::from("/usr/local/share/applications"),
            self.home_dir.join(".local/share/applications"),
            PathBuf::from("/var/lib/flatpak/exports/share/applications"),
            self.home_dir.join(".local/share/flatpak/exports/share/applications"),
        ];

        let mut entries = Vec::new();

        for dir in &search_paths {
            if !dir.exists() {
                continue;
            }

            if let Ok(read_dir) = fs::read_dir(dir) {
                for entry in read_dir.flatten() {
                    let path = entry.path();
                    if path.extension().is_some_and(|e| e == "desktop") {
                        if let Ok(desktop) = self.parse_desktop_file(&path) {
                            if !desktop.no_display && !desktop.hidden {
                                entries.push(desktop);
                            }
                        }
                    }
                }
            }
        }

        // Remove duplicates by name
        entries.sort_by(|a, b| a.name.cmp(&b.name));
        entries.dedup_by(|a, b| a.name == b.name);

        Ok(entries)
    }

    /// Parse a single .desktop file
    fn parse_desktop_file(&self, path: &Path) -> Result<DesktopEntry> {
        let content = fs::read_to_string(path)?;
        let mut entry = DesktopEntry::default();
        let mut in_desktop_entry = false;

        for line in content.lines() {
            let line = line.trim();

            if line == "[Desktop Entry]" {
                in_desktop_entry = true;
                continue;
            }

            if line.starts_with('[') {
                in_desktop_entry = false;
                continue;
            }

            if !in_desktop_entry {
                continue;
            }

            if let Some((key, value)) = line.split_once('=') {
                match key {
                    "Name" if entry.name.is_empty() => entry.name = value.to_string(),
                    "Exec" => {
                        // Remove %u, %U, %f, %F, etc. placeholders
                        entry.exec = value
                            .split_whitespace()
                            .filter(|s| !s.starts_with('%'))
                            .collect::<Vec<_>>()
                            .join(" ");
                    }
                    "Icon" => entry.icon = Some(value.to_string()),
                    "NoDisplay" => entry.no_display = value == "true",
                    "Hidden" => entry.hidden = value == "true",
                    "Terminal" => entry.terminal = value == "true",
                    "Categories" => {
                        entry.categories = value.split(';').map(|s| s.to_string()).collect()
                    }
                    _ => {}
                }
            }
        }

        Ok(entry)
    }

    /// Get program frequency from shell history
    fn get_shell_history_frequency(&self) -> Result<HashMap<String, usize>> {
        let mut frequency: HashMap<String, usize> = HashMap::new();

        // Try bash history
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

        // Try zsh history
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

        Ok(frequency)
    }
}

impl PlatformDataSource for LinuxDataSource {
    fn recent_files(&self, limit: usize) -> Result<Vec<LaunchItem>> {
        let items = self.parse_recently_used()?;

        Ok(items
            .into_iter()
            .filter_map(|item| {
                // Convert file:// URL to path
                let path = if item.href.starts_with("file://") {
                    urlencoding::decode(&item.href[7..])
                        .ok()?
                        .to_string()
                } else {
                    return None;
                };

                // Skip if file doesn't exist
                if !Path::new(&path).exists() {
                    return None;
                }

                let name = Path::new(&path)
                    .file_name()?
                    .to_string_lossy()
                    .to_string();

                Some(LaunchItem {
                    name,
                    path,
                    icon: None,
                    args: vec![],
                    item_type: ItemType::Document,
                })
            })
            .take(limit)
            .collect())
    }

    fn installed_apps(&self) -> Result<Vec<LaunchItem>> {
        let entries = self.parse_desktop_files()?;

        Ok(entries
            .into_iter()
            .map(|e| LaunchItem {
                name: e.name,
                path: e.exec,
                icon: e.icon,
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
            // Extract the base command from the exec path
            if let Some(cmd) = app.path.split_whitespace().next() {
                if let Some(base) = Path::new(cmd).file_name() {
                    cmd_to_app.insert(base.to_string_lossy().to_string(), app);
                }
            }
        }

        // Sort by frequency
        let mut freq_vec: Vec<_> = frequency.iter().collect();
        freq_vec.sort_by(|a, b| b.1.cmp(a.1));

        // Get top apps that match shell commands
        let result: Vec<LaunchItem> = freq_vec
            .iter()
            .filter_map(|(cmd, _)| cmd_to_app.get(cmd.as_str()).map(|app| (*app).clone()))
            .take(limit)
            .collect();

        Ok(result)
    }

    fn launch(&self, item: &LaunchItem) -> Result<()> {
        match item.item_type {
            ItemType::Document => {
                // Use xdg-open for documents
                Command::new("xdg-open")
                    .arg(&item.path)
                    .spawn()
                    .context("Failed to open document")?;
            }
            ItemType::Program | ItemType::Shortcut => {
                // Parse the exec line to get command and args
                let mut parts = item.path.split_whitespace();
                let cmd = parts.next().context("Empty command")?;
                let default_args: Vec<&str> = parts.collect();

                let mut command = Command::new(cmd);

                // Use item args if provided, otherwise use default args from exec
                if item.args.is_empty() {
                    command.args(default_args);
                } else {
                    command.args(&item.args);
                }

                command.spawn().context("Failed to launch program")?;
            }
        }

        Ok(())
    }
}

#[derive(Debug, Default)]
struct RecentItem {
    href: String,
    modified: String,
    mime_type: String,
}

#[derive(Debug, Default)]
struct DesktopEntry {
    name: String,
    exec: String,
    icon: Option<String>,
    no_display: bool,
    hidden: bool,
    terminal: bool,
    categories: Vec<String>,
}

/// Helper module for URL decoding
mod urlencoding {
    pub fn decode(input: &str) -> Result<String, std::string::FromUtf8Error> {
        let mut result = Vec::with_capacity(input.len());
        let mut chars = input.bytes();

        while let Some(b) = chars.next() {
            if b == b'%' {
                let high = chars.next();
                let low = chars.next();
                if let (Some(h), Some(l)) = (high, low) {
                    if let (Some(h_val), Some(l_val)) = (hex_to_u8(h), hex_to_u8(l)) {
                        result.push((h_val << 4) | l_val);
                        continue;
                    }
                }
                result.push(b);
            } else {
                result.push(b);
            }
        }

        String::from_utf8(result)
    }

    fn hex_to_u8(c: u8) -> Option<u8> {
        match c {
            b'0'..=b'9' => Some(c - b'0'),
            b'a'..=b'f' => Some(c - b'a' + 10),
            b'A'..=b'F' => Some(c - b'A' + 10),
            _ => None,
        }
    }
}

/// Get home directory
mod dirs {
    use std::path::PathBuf;

    pub fn home_dir() -> Option<PathBuf> {
        std::env::var_os("HOME").map(PathBuf::from)
    }
}
