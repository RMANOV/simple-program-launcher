//! Main UI application logic using egui

use crate::theme::{dark_theme, ThemeColors};
use arboard::Clipboard;
use eframe::egui::{self, CentralPanel, Context, Key, RichText, ScrollArea, Vec2};
use launcher_core::{
    config::{ItemType, LaunchItem},
    platform::{get_data_source, PlatformDataSource},
    ConfigManager, UsageTracker,
};
use std::sync::{Arc, Mutex};

/// Default display limit for clipboard in UI (scrollable for more)
const CLIPBOARD_DISPLAY_LIMIT: usize = 10;

/// Clipboard history entry
#[derive(Clone, Debug)]
pub struct ClipboardEntry {
    pub text: String,
    pub preview: String, // Truncated for display
}

impl ClipboardEntry {
    pub fn new(text: String) -> Self {
        let preview = if text.len() > 50 {
            format!("{}...", &text[..47])
        } else {
            text.clone()
        };
        Self { text, preview }
    }

    /// Check if this looks like a password (simple heuristic)
    pub fn looks_like_password(&self) -> bool {
        let text = &self.text;
        // High entropy short strings, or strings with "password" patterns
        text.len() >= 8
            && text.len() <= 32
            && text.chars().any(|c| c.is_ascii_uppercase())
            && text.chars().any(|c| c.is_ascii_lowercase())
            && text.chars().any(|c| c.is_ascii_digit())
            && !text.contains(' ')
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
}

impl LauncherApp {
    pub fn new(
        config_manager: Arc<ConfigManager>,
        usage_tracker: Arc<Mutex<UsageTracker>>,
    ) -> Self {
        let platform = Box::new(get_data_source());
        let clipboard = Clipboard::new().ok();

        let config = config_manager.get();
        let frequent_programs = platform
            .frequent_programs(config.max_frequent_programs)
            .unwrap_or_default();
        let recent_documents = platform
            .recent_files(config.max_frequent_documents)
            .unwrap_or_default();

        Self {
            config_manager,
            usage_tracker,
            platform,
            clipboard,
            clipboard_history: Vec::new(),
            last_clipboard_content: String::new(),
            frequent_programs,
            recent_documents,
            should_close: false,
            show_add_dialog: false,
            add_dialog_name: String::new(),
            add_dialog_path: String::new(),
        }
    }

    /// Refresh data from platform sources
    pub fn refresh(&mut self) {
        let config = self.config_manager.get();
        self.frequent_programs = self
            .platform
            .frequent_programs(config.max_frequent_programs)
            .unwrap_or_default();
        self.recent_documents = self
            .platform
            .recent_files(config.max_frequent_documents)
            .unwrap_or_default();
    }

    /// Update clipboard history
    fn update_clipboard(&mut self) {
        if let Some(ref mut clipboard) = self.clipboard {
            if let Ok(text) = clipboard.get_text() {
                if !text.is_empty() && text != self.last_clipboard_content {
                    self.last_clipboard_content = text.clone();

                    let entry = ClipboardEntry::new(text);

                    // Skip password-like content
                    if !entry.looks_like_password() {
                        // Remove duplicate if exists
                        self.clipboard_history
                            .retain(|e| e.text != entry.text);

                        // Add to front
                        self.clipboard_history.insert(0, entry);

                        // Trim to max size from config
                        let max_history = self.config_manager.get().max_clipboard_history;
                        self.clipboard_history.truncate(max_history);
                    }
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

    /// Paste clipboard item
    fn paste_clipboard(&mut self, text: &str) {
        if let Some(ref mut clipboard) = self.clipboard {
            let _ = clipboard.set_text(text);
        }
        self.should_close = true;
    }

    /// Pin an item to config
    fn pin_item(&mut self, item: LaunchItem) {
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

    /// Draw a launchable item row
    fn item_row(
        &mut self,
        ui: &mut egui::Ui,
        item: &LaunchItem,
        shortcut_key: Option<usize>,
        pinned: bool,
        show_pin_button: bool,
    ) -> bool {
        let mut launched = false;

        ui.horizontal(|ui| {
            // Shortcut key label
            if let Some(key) = shortcut_key {
                ui.label(
                    RichText::new(format!("[{}]", key))
                        .color(ThemeColors::DIM_TEXT)
                        .monospace(),
                );
            }

            // Main button
            let response = ui.add(
                egui::Button::new(&item.name)
                    .fill(egui::Color32::TRANSPARENT)
                    .min_size(Vec2::new(ui.available_width() - 40.0, 24.0)),
            );

            if response.clicked() {
                launched = true;
            }

            // Pin indicator or button
            if pinned {
                ui.label(RichText::new("\u{1F4CC}").color(ThemeColors::PIN_ICON)); // 📌
            } else if show_pin_button {
                if ui
                    .add(egui::Button::new("pin").small())
                    .on_hover_text("Pin this item")
                    .clicked()
                {
                    self.pin_item(item.clone());
                }
            }
        });

        launched
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

        // Handle keyboard shortcuts
        ctx.input(|i| {
            // Escape to close
            if i.key_pressed(Key::Escape) {
                self.should_close = true;
            }

            // Number keys 1-9 for shortcuts
            let config = self.config_manager.get();
            let mut all_items: Vec<&LaunchItem> = Vec::new();
            all_items.extend(config.pinned_programs.iter());
            all_items.extend(self.frequent_programs.iter());
            all_items.extend(config.pinned_documents.iter());
            all_items.extend(self.recent_documents.iter());
            all_items.extend(config.shortcuts.iter());

            for (idx, key) in [
                Key::Num1, Key::Num2, Key::Num3, Key::Num4, Key::Num5,
                Key::Num6, Key::Num7, Key::Num8, Key::Num9,
            ]
            .iter()
            .enumerate()
            {
                if i.key_pressed(*key) {
                    if let Some(item) = all_items.get(idx) {
                        let item_clone = (*item).clone();
                        drop(config);
                        self.launch_item(&item_clone);
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

        // Main panel
        CentralPanel::default().show(ctx, |ui| {
            ScrollArea::vertical().show(ui, |ui| {
                let config = self.config_manager.get();
                let mut shortcut_num = 1usize;

                // === Pinned Programs ===
                if !config.pinned_programs.is_empty() {
                    Self::section_header(ui, "Pinned Programs");
                    for item in &config.pinned_programs {
                        let item_clone = item.clone();
                        if self.item_row(ui, item, Some(shortcut_num), true, false) {
                            drop(config);
                            self.launch_item(&item_clone);
                            return;
                        }
                        shortcut_num += 1;
                    }
                    Self::separator(ui);
                }

                // === Frequent Programs ===
                let frequent_programs: Vec<_> = self
                    .frequent_programs
                    .iter()
                    .filter(|p| !config.pinned_programs.iter().any(|pp| pp.path == p.path))
                    .take(config.max_frequent_programs)
                    .collect();

                if !frequent_programs.is_empty() {
                    Self::section_header(ui, "Frequent Programs");
                    for item in frequent_programs {
                        let item_clone = item.clone();
                        if self.item_row(ui, item, Some(shortcut_num), false, true) {
                            drop(config);
                            self.launch_item(&item_clone);
                            return;
                        }
                        shortcut_num += 1;
                    }
                    Self::separator(ui);
                }

                // === Pinned Documents ===
                if !config.pinned_documents.is_empty() {
                    Self::section_header(ui, "Pinned Documents");
                    for item in &config.pinned_documents {
                        let item_clone = item.clone();
                        if self.item_row(ui, item, Some(shortcut_num), true, false) {
                            drop(config);
                            self.launch_item(&item_clone);
                            return;
                        }
                        shortcut_num += 1;
                    }
                    Self::separator(ui);
                }

                // === Recent Documents ===
                let recent_docs: Vec<_> = self
                    .recent_documents
                    .iter()
                    .filter(|d| !config.pinned_documents.iter().any(|pd| pd.path == d.path))
                    .take(config.max_frequent_documents)
                    .collect();

                if !recent_docs.is_empty() {
                    Self::section_header(ui, "Recent Documents");
                    for item in recent_docs {
                        let item_clone = item.clone();
                        if self.item_row(ui, item, Some(shortcut_num), false, true) {
                            drop(config);
                            self.launch_item(&item_clone);
                            return;
                        }
                        shortcut_num += 1;
                    }
                    Self::separator(ui);
                }

                // === Clipboard History ===
                if !self.clipboard_history.is_empty() {
                    Self::section_header(ui, "Clipboard History");
                    let history_clone = self.clipboard_history.clone();
                    for entry in &history_clone {
                        ui.horizontal(|ui| {
                            let response = ui.add(
                                egui::Button::new(&entry.preview)
                                    .fill(egui::Color32::TRANSPARENT)
                                    .min_size(Vec2::new(ui.available_width() - 30.0, 24.0)),
                            );

                            if response.clicked() {
                                self.paste_clipboard(&entry.text);
                            }

                            ui.label(
                                RichText::new("\u{1F4CB}").color(ThemeColors::CLIPBOARD_ICON),
                            ); // 📋
                        });
                    }
                    Self::separator(ui);
                }

                // === Shortcuts ===
                if !config.shortcuts.is_empty() {
                    Self::section_header(ui, "Shortcuts");
                    for item in &config.shortcuts {
                        ui.horizontal(|ui| {
                            if let Some(key) = (shortcut_num <= 9).then_some(shortcut_num) {
                                ui.label(
                                    RichText::new(format!("[{}]", key))
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
                                let item_clone = item.clone();
                                drop(config);
                                self.launch_item(&item_clone);
                                return;
                            }

                            ui.label(
                                RichText::new("\u{26A1}").color(ThemeColors::SHORTCUT_ICON),
                            ); // ⚡
                        });
                        shortcut_num += 1;
                    }
                    Self::separator(ui);
                }

                drop(config);

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
        if !ctx.input(|i| i.focused) {
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
    let config = config_manager.get();
    let width = config.ui.width;
    drop(config);

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
