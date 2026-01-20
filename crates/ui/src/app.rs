//! Main UI application logic using egui

use crate::theme::{dark_theme, ThemeColors};
use arboard::Clipboard;
use chrono::Utc;
use eframe::egui::{self, CentralPanel, Context, Key, RichText, ScrollArea, Vec2};
use launcher_core::{
    config::{ItemType, LaunchItem},
    platform::{get_data_source, PlatformDataSource},
    ConfigManager, UsageTracker,
};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

/// Default display limit for clipboard in UI (scrollable for more)
const CLIPBOARD_DISPLAY_LIMIT: usize = 10;

/// Fuzzy search scoring - matches Python implementation
fn fuzzy_score(query: &str, text: &str) -> i32 {
    let query_lower = query.to_lowercase();
    let text_lower = text.to_lowercase();

    // Exact substring match (highest priority)
    if let Some(pos) = text_lower.find(&query_lower) {
        return 1000 + (100 - pos.min(100) as i32);
    }

    // Fuzzy matching
    let mut score = 0i32;
    let mut q_idx = 0;
    let mut consecutive = 0i32;
    let mut prev_match_idx: i32 = -2;

    let query_chars: Vec<char> = query_lower.chars().collect();
    let text_chars: Vec<char> = text.chars().collect();
    let text_lower_chars: Vec<char> = text_lower.chars().collect();

    for (t_idx, &char) in text_lower_chars.iter().enumerate() {
        if q_idx < query_chars.len() && char == query_chars[q_idx] {
            score += 1;

            // Consecutive bonus
            if t_idx as i32 == prev_match_idx + 1 {
                consecutive += 1;
                score += consecutive * 10;
            } else {
                consecutive = 0;
            }

            // Word start bonus
            if t_idx == 0 || matches!(text_chars.get(t_idx.wrapping_sub(1)), Some(' ' | '_' | '-' | '.' | '/' | '\\')) {
                score += 5;
            }

            prev_match_idx = t_idx as i32;
            q_idx += 1;
        }
    }

    // All query chars must match
    if q_idx < query_chars.len() {
        return 0;
    }

    score
}

/// Search clipboard history with fuzzy matching
fn fuzzy_search_clipboard(query: &str, history: &[ClipboardEntry], limit: usize) -> Vec<ClipboardEntry> {
    if query.is_empty() {
        return history.iter().take(limit).cloned().collect();
    }

    let mut scored: Vec<(i32, &ClipboardEntry)> = history
        .iter()
        .filter_map(|entry| {
            let score = fuzzy_score(query, &entry.text);
            if score > 0 { Some((score, entry)) } else { None }
        })
        .collect();

    scored.sort_by(|a, b| b.0.cmp(&a.0));
    scored.into_iter().take(limit).map(|(_, e)| e.clone()).collect()
}

/// Clipboard history entry with usage tracking
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct ClipboardEntry {
    pub text: String,
    #[serde(skip)]
    pub preview: String,
    #[serde(default)]
    pub count: u32,
    #[serde(default)]
    pub last_used: Option<String>,
}

impl ClipboardEntry {
    pub fn new(text: String) -> Self {
        let mut entry = Self {
            text,
            preview: String::new(),
            count: 0,
            last_used: Some(Utc::now().format("%Y-%m-%d %H:%M:%S").to_string()),
        };
        entry.update_preview();
        entry
    }

    /// Update the preview string based on current state
    fn update_preview(&mut self) {
        let truncated = if self.text.len() > 40 {
            format!("{}...", &self.text[..37])
        } else {
            self.text.clone()
        }
        .replace('\n', " ");

        let mut preview = truncated;
        if self.count > 0 {
            preview.push_str(&format!(" ({})", self.count));
        }
        if let Some(result) = eval_math(&self.text) {
            preview.push_str(&format!(" = {}", result));
        }
        self.preview = preview;
    }

    /// Check if this looks like a password (simple heuristic)
    pub fn looks_like_password(&self) -> bool {
        let text = &self.text;
        text.len() >= 8
            && text.len() <= 32
            && text.chars().any(|c| c.is_ascii_uppercase())
            && text.chars().any(|c| c.is_ascii_lowercase())
            && text.chars().any(|c| c.is_ascii_digit())
            && !text.contains(' ')
    }
}

/// Evaluate simple math expressions
fn eval_math(text: &str) -> Option<f64> {
    let expr = text
        .trim()
        .replace('x', "*")
        .replace('×', "*")
        .replace('÷', "/")
        .replace(',', ".")
        .replace(' ', "");

    // Must contain digits and at least one operator
    if !expr.chars().any(|c| c.is_ascii_digit()) {
        return None;
    }
    if !expr.chars().any(|c| "+-*/".contains(c)) {
        return None;
    }
    // Only allow safe math characters
    if !expr.chars().all(|c| "0123456789.+-*/()".contains(c)) {
        return None;
    }

    meval::eval_str(&expr).ok()
}

/// Get the path to clipboard history JSON file
fn clipboard_file_path() -> PathBuf {
    directories::ProjectDirs::from("com", "launcher", "simple-program-launcher")
        .map(|dirs| dirs.config_dir().join("clipboard.json"))
        .unwrap_or_else(|| PathBuf::from("clipboard.json"))
}

/// Load clipboard history from disk
fn load_clipboard_history() -> Vec<ClipboardEntry> {
    let path = clipboard_file_path();
    if !path.exists() {
        return Vec::new();
    }

    match fs::read_to_string(&path) {
        Ok(content) => {
            let mut entries: Vec<ClipboardEntry> =
                serde_json::from_str(&content).unwrap_or_default();
            // Update previews (since they're skipped in serialization)
            for entry in &mut entries {
                entry.update_preview();
            }
            // Sort by count DESC, then last_used DESC
            entries.sort_by(|a, b| {
                b.count
                    .cmp(&a.count)
                    .then_with(|| b.last_used.cmp(&a.last_used))
            });
            entries
        }
        Err(_) => Vec::new(),
    }
}

/// Save clipboard history to disk with smart eviction
fn save_clipboard_history(history: &[ClipboardEntry], max_size: usize) {
    let path = clipboard_file_path();
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }

    let mut to_save: Vec<ClipboardEntry> = history.to_vec();

    // Smart eviction: if over limit, remove items with lowest (count, last_used)
    if to_save.len() > max_size {
        to_save.sort_by(|a, b| {
            a.count
                .cmp(&b.count)
                .then_with(|| a.last_used.cmp(&b.last_used))
        });
        // Remove oldest/least-used entries
        to_save.drain(0..to_save.len() - max_size);
        // Re-sort by count DESC, last_used DESC for display
        to_save.sort_by(|a, b| {
            b.count
                .cmp(&a.count)
                .then_with(|| b.last_used.cmp(&a.last_used))
        });
    }

    if let Ok(json) = serde_json::to_string_pretty(&to_save) {
        let _ = fs::write(&path, json);
    }
}

/// The launcher popup application
pub struct LauncherApp {
    config_manager: Arc<ConfigManager>,
    usage_tracker: Arc<Mutex<UsageTracker>>,
    platform: Box<dyn PlatformDataSource + Send>,
    clipboard: Option<Clipboard>,
    clipboard_history: Vec<ClipboardEntry>,
    last_clipboard_content: String,

    // UI state
    frequent_programs: Vec<LaunchItem>,
    recent_documents: Vec<LaunchItem>,
    should_close: bool,
    show_add_dialog: bool,
    add_dialog_name: String,
    add_dialog_path: String,
    clipboard_search_query: String,

    // Pending actions (to avoid borrow issues)
    pending_launch: Option<LaunchItem>,
    pending_pin: Option<LaunchItem>,
    pending_paste: Option<String>,
    pending_pin_clipboard: Option<String>,
    pending_unpin_clipboard: Option<String>,

    // Frame counter for delayed focus check
    frame_count: u32,
}

impl LauncherApp {
    pub fn new(
        config_manager: Arc<ConfigManager>,
        usage_tracker: Arc<Mutex<UsageTracker>>,
    ) -> Self {
        let platform = Box::new(get_data_source());
        let clipboard = Clipboard::new().ok();

        // Get config values then drop the lock
        let (max_frequent_programs, max_frequent_documents) = {
            let config = config_manager.get();
            (config.max_frequent_programs, config.max_frequent_documents)
        };

        let frequent_programs = platform
            .frequent_programs(max_frequent_programs)
            .unwrap_or_default();
        let recent_documents = platform
            .recent_files(max_frequent_documents)
            .unwrap_or_default();

        // Load clipboard history from disk
        let clipboard_history = load_clipboard_history();

        Self {
            config_manager,
            usage_tracker,
            platform,
            clipboard,
            clipboard_history,
            last_clipboard_content: String::new(),
            frequent_programs,
            recent_documents,
            should_close: false,
            show_add_dialog: false,
            add_dialog_name: String::new(),
            add_dialog_path: String::new(),
            clipboard_search_query: String::new(),
            pending_launch: None,
            pending_pin: None,
            pending_paste: None,
            pending_pin_clipboard: None,
            pending_unpin_clipboard: None,
            frame_count: 0,
        }
    }

    /// Refresh data from platform sources
    pub fn refresh(&mut self) {
        let (max_frequent_programs, max_frequent_documents) = {
            let config = self.config_manager.get();
            (config.max_frequent_programs, config.max_frequent_documents)
        };

        self.frequent_programs = self
            .platform
            .frequent_programs(max_frequent_programs)
            .unwrap_or_default();
        self.recent_documents = self
            .platform
            .recent_files(max_frequent_documents)
            .unwrap_or_default();
    }

    /// Update clipboard history
    fn update_clipboard(&mut self) {
        if let Some(ref mut clipboard) = self.clipboard {
            if let Ok(text) = clipboard.get_text() {
                if !text.is_empty() && text != self.last_clipboard_content {
                    self.last_clipboard_content = text.clone();

                    // Skip password-like content
                    let temp_entry = ClipboardEntry::new(text.clone());
                    if temp_entry.looks_like_password() {
                        return;
                    }

                    // Check if entry already exists
                    if let Some(existing) = self
                        .clipboard_history
                        .iter_mut()
                        .find(|e| e.text == text)
                    {
                        // Update last_used timestamp
                        existing.last_used =
                            Some(Utc::now().format("%Y-%m-%d %H:%M:%S").to_string());
                        existing.update_preview();
                    } else {
                        // Add new entry
                        let entry = ClipboardEntry::new(text);
                        self.clipboard_history.insert(0, entry);
                    }

                    // Save to disk with smart eviction
                    let max_history = self.config_manager.get().max_clipboard_history;
                    save_clipboard_history(&self.clipboard_history, max_history);

                    // Re-sort by count DESC, last_used DESC
                    self.clipboard_history.sort_by(|a, b| {
                        b.count
                            .cmp(&a.count)
                            .then_with(|| b.last_used.cmp(&a.last_used))
                    });
                }
            }
        }
    }

    /// Launch an item and record usage
    fn launch_item(&mut self, item: &LaunchItem) {
        if let Err(e) = self.platform.launch(item) {
            log::error!("Failed to launch {}: {}", item.name, e);
            return;
        }

        // Record usage
        if let Ok(mut tracker) = self.usage_tracker.lock() {
            match item.item_type {
                ItemType::Program | ItemType::Shortcut => {
                    tracker.record_program(&item.path, &item.name);
                }
                ItemType::Document => {
                    tracker.record_document(&item.path, &item.name);
                }
            }
            let _ = tracker.save_if_dirty();
        }

        self.should_close = true;
    }

    /// Paste clipboard item and increment usage count
    fn paste_clipboard(&mut self, text: &str) {
        // Increment count for the pasted item
        if let Some(entry) = self.clipboard_history.iter_mut().find(|e| e.text == text) {
            entry.count += 1;
            entry.last_used = Some(Utc::now().format("%Y-%m-%d %H:%M:%S").to_string());
            entry.update_preview();
        }

        // Save updated history
        let max_history = self.config_manager.get().max_clipboard_history;
        save_clipboard_history(&self.clipboard_history, max_history);

        // Set clipboard and close
        if let Some(ref mut clipboard) = self.clipboard {
            let _ = clipboard.set_text(text);
        }
        self.should_close = true;
    }

    /// Pin an item to config
    fn pin_item(&self, item: LaunchItem) {
        let _ = self.config_manager.modify(|config| {
            match item.item_type {
                ItemType::Program | ItemType::Shortcut => config.pin_program(item),
                ItemType::Document => config.pin_document(item),
            }
        });
    }

    /// Draw a section header
    fn section_header(ui: &mut egui::Ui, text: &str) {
        ui.add_space(4.0);
        ui.label(
            RichText::new(text)
                .color(ThemeColors::SECTION_HEADER)
                .size(12.0),
        );
        ui.add_space(2.0);
    }

    /// Draw a separator line
    fn separator(ui: &mut egui::Ui) {
        ui.add_space(4.0);
        let rect = ui.available_rect_before_wrap();
        let painter = ui.painter();
        painter.line_segment(
            [
                egui::pos2(rect.left(), rect.top()),
                egui::pos2(rect.right(), rect.top()),
            ],
            egui::Stroke::new(1.0, ThemeColors::SEPARATOR),
        );
        ui.add_space(4.0);
    }

    /// Process pending actions
    fn process_pending_actions(&mut self) {
        // Handle pending launch
        if let Some(item) = self.pending_launch.take() {
            self.launch_item(&item);
        }

        // Handle pending pin
        if let Some(item) = self.pending_pin.take() {
            self.pin_item(item);
        }

        // Handle pending paste
        if let Some(text) = self.pending_paste.take() {
            self.paste_clipboard(&text);
        }

        // Handle pending clipboard pin
        if let Some(text) = self.pending_pin_clipboard.take() {
            let _ = self.config_manager.modify(|cfg| {
                cfg.pin_clipboard(text);
            });
        }

        // Handle pending clipboard unpin
        if let Some(text) = self.pending_unpin_clipboard.take() {
            let _ = self.config_manager.modify(|cfg| {
                cfg.unpin_clipboard(&text);
            });
        }
    }

    /// Draw the add shortcut dialog
    fn add_shortcut_dialog(&mut self, ctx: &Context) {
        egui::Window::new("Add Shortcut")
            .collapsible(false)
            .resizable(false)
            .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    ui.label("Name:");
                    ui.text_edit_singleline(&mut self.add_dialog_name);
                });

                ui.horizontal(|ui| {
                    ui.label("Path:");
                    ui.text_edit_singleline(&mut self.add_dialog_path);
                });

                ui.horizontal(|ui| {
                    if ui.button("Cancel").clicked() {
                        self.show_add_dialog = false;
                        self.add_dialog_name.clear();
                        self.add_dialog_path.clear();
                    }

                    if ui.button("Add").clicked() && !self.add_dialog_name.is_empty() {
                        let item = LaunchItem {
                            name: self.add_dialog_name.clone(),
                            path: self.add_dialog_path.clone(),
                            icon: None,
                            args: vec![],
                            item_type: ItemType::Shortcut,
                        };

                        let _ = self.config_manager.modify(|config| {
                            config.add_shortcut(item);
                        });

                        self.show_add_dialog = false;
                        self.add_dialog_name.clear();
                        self.add_dialog_path.clear();
                    }
                });
            });
    }
}

impl eframe::App for LauncherApp {
    fn update(&mut self, ctx: &Context, _frame: &mut eframe::Frame) {
        // Check for config hot-reload
        if self.config_manager.check_reload() {
            self.refresh();
        }

        // Update clipboard history
        self.update_clipboard();

        // Process any pending actions from previous frame
        self.process_pending_actions();

        // Handle keyboard shortcuts
        ctx.input(|i| {
            // Escape to close
            if i.key_pressed(Key::Escape) {
                self.should_close = true;
            }

            // Number keys 1-9 for shortcuts
            let config = self.config_manager.get();
            let mut all_items: Vec<LaunchItem> = Vec::new();
            all_items.extend(config.pinned_programs.iter().cloned());
            all_items.extend(self.frequent_programs.iter().cloned());
            all_items.extend(config.pinned_documents.iter().cloned());
            all_items.extend(self.recent_documents.iter().cloned());
            all_items.extend(config.shortcuts.iter().cloned());
            drop(config);

            for (idx, key) in [
                Key::Num1, Key::Num2, Key::Num3, Key::Num4, Key::Num5,
                Key::Num6, Key::Num7, Key::Num8, Key::Num9,
            ]
            .iter()
            .enumerate()
            {
                if i.key_pressed(*key) {
                    if let Some(item) = all_items.get(idx) {
                        self.pending_launch = Some(item.clone());
                        return;
                    }
                }
            }
        });

        // Close window if requested
        if self.should_close {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
            return;
        }

        // Apply theme
        ctx.set_style(dark_theme());

        // Get config data we need (clone to avoid holding lock)
        let (
            pinned_programs,
            pinned_documents,
            pinned_clipboard,
            shortcuts,
            max_frequent_programs,
            max_frequent_documents,
        ) = {
            let config = self.config_manager.get();
            (
                config.pinned_programs.clone(),
                config.pinned_documents.clone(),
                config.pinned_clipboard.clone(),
                config.shortcuts.clone(),
                config.max_frequent_programs,
                config.max_frequent_documents,
            )
        };

        // Main panel
        CentralPanel::default().show(ctx, |ui| {
            ScrollArea::vertical().show(ui, |ui| {
                let mut shortcut_num = 1usize;

                // === Pinned Programs ===
                if !pinned_programs.is_empty() {
                    Self::section_header(ui, "Pinned Programs");
                    for item in &pinned_programs {
                        ui.horizontal(|ui| {
                            if shortcut_num <= 9 {
                                ui.label(
                                    RichText::new(format!("[{}]", shortcut_num))
                                        .color(ThemeColors::DIM_TEXT)
                                        .monospace(),
                                );
                            }

                            let response = ui.add(
                                egui::Button::new(&item.name)
                                    .fill(egui::Color32::TRANSPARENT)
                                    .min_size(Vec2::new(ui.available_width() - 40.0, 24.0)),
                            );

                            if response.clicked() {
                                self.pending_launch = Some(item.clone());
                            }

                            ui.label(RichText::new("\u{1F4CC}").color(ThemeColors::PIN_ICON)); // 📌
                        });
                        shortcut_num += 1;
                    }
                    Self::separator(ui);
                }

                // === Frequent Programs ===
                let frequent_programs: Vec<_> = self
                    .frequent_programs
                    .iter()
                    .filter(|p| !pinned_programs.iter().any(|pp| pp.path == p.path))
                    .take(max_frequent_programs)
                    .cloned()
                    .collect();

                if !frequent_programs.is_empty() {
                    Self::section_header(ui, "Frequent Programs");
                    for item in &frequent_programs {
                        ui.horizontal(|ui| {
                            if shortcut_num <= 9 {
                                ui.label(
                                    RichText::new(format!("[{}]", shortcut_num))
                                        .color(ThemeColors::DIM_TEXT)
                                        .monospace(),
                                );
                            }

                            let response = ui.add(
                                egui::Button::new(&item.name)
                                    .fill(egui::Color32::TRANSPARENT)
                                    .min_size(Vec2::new(ui.available_width() - 60.0, 24.0)),
                            );

                            if response.clicked() {
                                self.pending_launch = Some(item.clone());
                            }

                            if ui.small_button("pin").clicked() {
                                self.pending_pin = Some(item.clone());
                            }
                        });
                        shortcut_num += 1;
                    }
                    Self::separator(ui);
                }

                // === Pinned Documents ===
                if !pinned_documents.is_empty() {
                    Self::section_header(ui, "Pinned Documents");
                    for item in &pinned_documents {
                        ui.horizontal(|ui| {
                            if shortcut_num <= 9 {
                                ui.label(
                                    RichText::new(format!("[{}]", shortcut_num))
                                        .color(ThemeColors::DIM_TEXT)
                                        .monospace(),
                                );
                            }

                            let response = ui.add(
                                egui::Button::new(&item.name)
                                    .fill(egui::Color32::TRANSPARENT)
                                    .min_size(Vec2::new(ui.available_width() - 40.0, 24.0)),
                            );

                            if response.clicked() {
                                self.pending_launch = Some(item.clone());
                            }

                            ui.label(RichText::new("\u{1F4CC}").color(ThemeColors::PIN_ICON)); // 📌
                        });
                        shortcut_num += 1;
                    }
                    Self::separator(ui);
                }

                // === Recent Documents ===
                let recent_docs: Vec<_> = self
                    .recent_documents
                    .iter()
                    .filter(|d| !pinned_documents.iter().any(|pd| pd.path == d.path))
                    .take(max_frequent_documents)
                    .cloned()
                    .collect();

                if !recent_docs.is_empty() {
                    Self::section_header(ui, "Recent Documents");
                    for item in &recent_docs {
                        ui.horizontal(|ui| {
                            if shortcut_num <= 9 {
                                ui.label(
                                    RichText::new(format!("[{}]", shortcut_num))
                                        .color(ThemeColors::DIM_TEXT)
                                        .monospace(),
                                );
                            }

                            let response = ui.add(
                                egui::Button::new(&item.name)
                                    .fill(egui::Color32::TRANSPARENT)
                                    .min_size(Vec2::new(ui.available_width() - 60.0, 24.0)),
                            );

                            if response.clicked() {
                                self.pending_launch = Some(item.clone());
                            }

                            if ui.small_button("pin").clicked() {
                                self.pending_pin = Some(item.clone());
                            }
                        });
                        shortcut_num += 1;
                    }
                    Self::separator(ui);
                }

                // === Clipboard History with Fuzzy Search ===
                if !self.clipboard_history.is_empty() {
                    Self::section_header(ui, "Clipboard History");

                    // Search box
                    ui.horizontal(|ui| {
                        ui.label(RichText::new("\u{1F50D}").color(ThemeColors::DIM_TEXT)); // 🔍
                        ui.add(
                            egui::TextEdit::singleline(&mut self.clipboard_search_query)
                                .hint_text("Search clipboard...")
                                .desired_width(ui.available_width() - 30.0),
                        );
                    });

                    ui.add_space(4.0);

                    // Fuzzy search results
                    let pinned_set: std::collections::HashSet<_> = pinned_clipboard.iter().collect();
                    let search_results = fuzzy_search_clipboard(
                        &self.clipboard_search_query,
                        &self.clipboard_history,
                        50,
                    );

                    // Show non-pinned results (first 10)
                    let regular_results: Vec<_> = search_results
                        .iter()
                        .filter(|e| !pinned_set.contains(&e.text))
                        .take(CLIPBOARD_DISPLAY_LIMIT)
                        .cloned()
                        .collect();

                    for entry in &regular_results {
                        ui.horizontal(|ui| {
                            let response = ui.add(
                                egui::Button::new(&entry.preview)
                                    .fill(egui::Color32::TRANSPARENT)
                                    .min_size(Vec2::new(ui.available_width() - 60.0, 24.0)),
                            );

                            if response.clicked() {
                                self.pending_paste = Some(entry.text.clone());
                            }

                            // Show full text on hover for long entries
                            if entry.text.len() > 40 {
                                response.on_hover_text(&entry.text);
                            }

                            // Pin button
                            if ui.small_button("pin").clicked() {
                                self.pending_pin_clipboard = Some(entry.text.clone());
                            }

                            ui.label(
                                RichText::new("\u{1F4CB}").color(ThemeColors::CLIPBOARD_ICON),
                            );
                        });
                    }

                    // Show pinned clipboard section
                    if !pinned_clipboard.is_empty() {
                        ui.add_space(4.0);
                        ui.label(RichText::new("Pinned").color(ThemeColors::SECTION_HEADER).size(11.0));

                        let query = &self.clipboard_search_query;
                        for text in &pinned_clipboard {
                            // Filter by search query
                            if !query.is_empty() && fuzzy_score(query, text) == 0 {
                                continue;
                            }

                            let preview = if text.len() > 47 {
                                format!("{}...", &text[..47])
                            } else {
                                text.clone()
                            };

                            ui.horizontal(|ui| {
                                let response = ui.add(
                                    egui::Button::new(&preview)
                                        .fill(egui::Color32::TRANSPARENT)
                                        .min_size(Vec2::new(ui.available_width() - 60.0, 24.0)),
                                );

                                if response.clicked() {
                                    self.pending_paste = Some(text.clone());
                                }

                                // Show full text on hover for long entries
                                if text.len() > 40 {
                                    response.on_hover_text(text);
                                }

                                // Unpin button
                                if ui.small_button("x").clicked() {
                                    self.pending_unpin_clipboard = Some(text.clone());
                                }

                                ui.label(RichText::new("\u{1F4CC}").color(ThemeColors::PIN_ICON)); // 📌
                            });
                        }
                    }
                    Self::separator(ui);
                }

                // === Shortcuts ===
                if !shortcuts.is_empty() {
                    Self::section_header(ui, "Shortcuts");
                    for item in &shortcuts {
                        ui.horizontal(|ui| {
                            if shortcut_num <= 9 {
                                ui.label(
                                    RichText::new(format!("[{}]", shortcut_num))
                                        .color(ThemeColors::DIM_TEXT)
                                        .monospace(),
                                );
                            }

                            let response = ui.add(
                                egui::Button::new(&item.name)
                                    .fill(egui::Color32::TRANSPARENT)
                                    .min_size(Vec2::new(ui.available_width() - 40.0, 24.0)),
                            );

                            if response.clicked() {
                                self.pending_launch = Some(item.clone());
                            }

                            ui.label(
                                RichText::new("\u{26A1}").color(ThemeColors::SHORTCUT_ICON),
                            ); // ⚡
                        });
                        shortcut_num += 1;
                    }
                    Self::separator(ui);
                }

                // === Add Shortcut Button ===
                ui.add_space(4.0);
                if ui
                    .add(
                        egui::Button::new("[+ Add Shortcut]")
                            .fill(egui::Color32::TRANSPARENT),
                    )
                    .clicked()
                {
                    self.show_add_dialog = true;
                }
            });
        });

        // Show add dialog if requested
        if self.show_add_dialog {
            self.add_shortcut_dialog(ctx);
        }

        // Click outside detection (simplified - close on focus loss)
        // Skip first 10 frames to allow window to gain focus after mouse click
        self.frame_count += 1;
        if self.frame_count > 10 && !ctx.input(|i| i.focused) {
            self.should_close = true;
        }
    }
}

/// Create and run the launcher popup window
pub fn run_popup(
    position: (f64, f64),
    config_manager: Arc<ConfigManager>,
    usage_tracker: Arc<Mutex<UsageTracker>>,
) -> Result<(), eframe::Error> {
    let width = {
        let config = config_manager.get();
        config.ui.width
    };

    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([width, 400.0])
            .with_position([position.0 as f32, position.1 as f32])
            .with_decorations(false)
            .with_transparent(true)
            .with_always_on_top()
            .with_resizable(false),
        ..Default::default()
    };

    eframe::run_native(
        "Launcher",
        options,
        Box::new(move |_cc| {
            Ok(Box::new(LauncherApp::new(
                config_manager.clone(),
                usage_tracker.clone(),
            )))
        }),
    )
}
