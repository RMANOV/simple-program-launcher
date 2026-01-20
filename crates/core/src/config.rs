//! Configuration management with hot-reload support

use anyhow::{Context, Result};
use notify::{Event, RecommendedWatcher, RecursiveMode, Watcher};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, RwLock};

/// A launchable item (program, document, or shortcut)
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LaunchItem {
    /// Display name
    pub name: String,
    /// Path to executable or document
    pub path: String,
    /// Optional icon path
    #[serde(default)]
    pub icon: Option<String>,
    /// Arguments to pass (for programs)
    #[serde(default)]
    pub args: Vec<String>,
    /// Item type
    #[serde(default)]
    pub item_type: ItemType,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Default)]
#[serde(rename_all = "lowercase")]
pub enum ItemType {
    #[default]
    Program,
    Document,
    Shortcut,
}

/// Configuration for the launcher
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Pinned programs (user-selected)
    #[serde(default)]
    pub pinned_programs: Vec<LaunchItem>,

    /// Pinned documents (user-selected)
    #[serde(default)]
    pub pinned_documents: Vec<LaunchItem>,

    /// Custom shortcuts (e.g., shutdown, lock)
    #[serde(default)]
    pub shortcuts: Vec<LaunchItem>,

    /// Pinned clipboard entries
    #[serde(default)]
    pub pinned_clipboard: Vec<String>,

    /// Maximum number of frequent items to show
    #[serde(default = "default_max_frequent")]
    pub max_frequent_programs: usize,

    #[serde(default = "default_max_frequent")]
    pub max_frequent_documents: usize,

    /// Maximum clipboard history items
    #[serde(default = "default_max_clipboard")]
    pub max_clipboard_history: usize,

    /// Trigger settings
    #[serde(default)]
    pub trigger: TriggerConfig,

    /// UI settings
    #[serde(default)]
    pub ui: UiConfig,
}

fn default_max_frequent() -> usize {
    5
}

fn default_max_clipboard() -> usize {
    10000
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TriggerConfig {
    /// Time threshold for simultaneous L+R click (ms)
    #[serde(default = "default_simultaneous_threshold")]
    pub simultaneous_threshold_ms: u64,

    /// Debounce time to prevent accidental triggers (ms)
    #[serde(default = "default_debounce")]
    pub debounce_ms: u64,
}

fn default_simultaneous_threshold() -> u64 {
    200
}

fn default_debounce() -> u64 {
    500
}

impl Default for TriggerConfig {
    fn default() -> Self {
        Self {
            simultaneous_threshold_ms: default_simultaneous_threshold(),
            debounce_ms: default_debounce(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UiConfig {
    /// Window width
    #[serde(default = "default_width")]
    pub width: f32,

    /// Window margin from edges
    #[serde(default = "default_margin")]
    pub margin: f32,

    /// Dark mode (always true for now)
    #[serde(default = "default_dark_mode")]
    pub dark_mode: bool,
}

fn default_width() -> f32 {
    300.0
}

fn default_margin() -> f32 {
    4.0
}

fn default_dark_mode() -> bool {
    true
}

impl Default for UiConfig {
    fn default() -> Self {
        Self {
            width: default_width(),
            margin: default_margin(),
            dark_mode: default_dark_mode(),
        }
    }
}

impl Default for Config {
    fn default() -> Self {
        Self {
            pinned_programs: vec![],
            pinned_documents: vec![],
            pinned_clipboard: vec![],
            shortcuts: vec![
                LaunchItem {
                    name: "Lock Screen".to_string(),
                    path: if cfg!(target_os = "linux") {
                        "loginctl".to_string()
                    } else if cfg!(target_os = "macos") {
                        "pmset".to_string()
                    } else {
                        "rundll32.exe".to_string()
                    },
                    icon: None,
                    args: if cfg!(target_os = "linux") {
                        vec!["lock-session".to_string()]
                    } else if cfg!(target_os = "macos") {
                        vec!["displaysleepnow".to_string()]
                    } else {
                        vec![
                            "user32.dll,LockWorkStation".to_string(),
                        ]
                    },
                    item_type: ItemType::Shortcut,
                },
            ],
            max_frequent_programs: default_max_frequent(),
            max_frequent_documents: default_max_frequent(),
            max_clipboard_history: default_max_clipboard(),
            trigger: TriggerConfig::default(),
            ui: UiConfig::default(),
        }
    }
}

impl Config {
    /// Get the config file path
    pub fn config_path() -> Result<PathBuf> {
        let dirs = directories::ProjectDirs::from("com", "rmanov", "launcher")
            .context("Failed to determine config directory")?;
        let config_dir = dirs.config_dir();
        fs::create_dir_all(config_dir).context("Failed to create config directory")?;
        Ok(config_dir.join("config.json"))
    }

    /// Load config from file, creating default if missing
    pub fn load() -> Result<Self> {
        let path = Self::config_path()?;

        if path.exists() {
            let content = fs::read_to_string(&path)
                .with_context(|| format!("Failed to read config from {:?}", path))?;
            serde_json::from_str(&content)
                .with_context(|| format!("Failed to parse config from {:?}", path))
        } else {
            let config = Config::default();
            config.save()?;
            Ok(config)
        }
    }

    /// Save config to file
    pub fn save(&self) -> Result<()> {
        let path = Self::config_path()?;
        let content = serde_json::to_string_pretty(self)?;
        fs::write(&path, content)
            .with_context(|| format!("Failed to write config to {:?}", path))?;
        Ok(())
    }

    /// Pin a program
    pub fn pin_program(&mut self, item: LaunchItem) {
        if !self.pinned_programs.iter().any(|p| p.path == item.path) {
            self.pinned_programs.push(item);
        }
    }

    /// Pin a document
    pub fn pin_document(&mut self, item: LaunchItem) {
        if !self.pinned_documents.iter().any(|d| d.path == item.path) {
            self.pinned_documents.push(item);
        }
    }

    /// Unpin a program
    pub fn unpin_program(&mut self, path: &str) {
        self.pinned_programs.retain(|p| p.path != path);
    }

    /// Unpin a document
    pub fn unpin_document(&mut self, path: &str) {
        self.pinned_documents.retain(|d| d.path != path);
    }

    /// Add a custom shortcut
    pub fn add_shortcut(&mut self, item: LaunchItem) {
        self.shortcuts.push(item);
    }

    /// Pin a clipboard entry
    pub fn pin_clipboard(&mut self, text: String) {
        if !self.pinned_clipboard.contains(&text) {
            self.pinned_clipboard.push(text);
        }
    }

    /// Unpin a clipboard entry
    pub fn unpin_clipboard(&mut self, text: &str) {
        self.pinned_clipboard.retain(|t| t != text);
    }
}

/// Configuration manager with hot-reload support
pub struct ConfigManager {
    config: Arc<RwLock<Config>>,
    _watcher: Option<RecommendedWatcher>,
    reloaded: Arc<AtomicBool>,
}

impl ConfigManager {
    /// Create a new config manager with file watching
    pub fn new() -> Result<Self> {
        let config = Config::load()?;
        let config = Arc::new(RwLock::new(config));
        let reloaded = Arc::new(AtomicBool::new(false));

        let config_path = Config::config_path()?;

        let watcher_config = config.clone();
        let watcher_reloaded = reloaded.clone();
        let mut watcher = notify::recommended_watcher(move |res: Result<Event, _>| {
            if let Ok(event) = res {
                if event.kind.is_modify() {
                    if let Ok(new_config) = Config::load() {
                        if let Ok(mut cfg) = watcher_config.write() {
                            *cfg = new_config;
                            watcher_reloaded.store(true, Ordering::SeqCst);
                            log::info!("Config hot-reloaded");
                        }
                    }
                }
            }
        })?;

        watcher.watch(config_path.parent().unwrap(), RecursiveMode::NonRecursive)?;

        Ok(Self {
            config,
            _watcher: Some(watcher),
            reloaded,
        })
    }

    /// Get a read lock on the config
    pub fn get(&self) -> std::sync::RwLockReadGuard<'_, Config> {
        self.config.read().unwrap()
    }

    /// Get a write lock and save after modification
    pub fn modify<F>(&self, f: F) -> Result<()>
    where
        F: FnOnce(&mut Config),
    {
        let mut config = self.config.write().unwrap();
        f(&mut config);
        config.save()
    }

    /// Check if config was reloaded (non-blocking)
    pub fn check_reload(&self) -> bool {
        self.reloaded.swap(false, Ordering::SeqCst)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert_eq!(config.max_frequent_programs, 5);
        assert_eq!(config.max_clipboard_history, 10000);
        assert!(config.ui.dark_mode);
    }

    #[test]
    fn test_config_serialization() {
        let config = Config::default();
        let json = serde_json::to_string_pretty(&config).unwrap();
        let parsed: Config = serde_json::from_str(&json).unwrap();
        assert_eq!(parsed.max_frequent_programs, config.max_frequent_programs);
    }
}
