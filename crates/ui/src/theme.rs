//! Dark theme configuration for the launcher UI

use egui::{Color32, CornerRadius, FontFamily, FontId, Stroke, Style, TextStyle, Vec2, Visuals};

/// Create the dark theme for the launcher
pub fn dark_theme() -> Style {
    let mut style = Style::default();

    // Dark mode visuals
    style.visuals = Visuals::dark();

    // Custom colors
    let bg_color = Color32::from_rgb(30, 30, 35);
    let panel_color = Color32::from_rgb(40, 40, 48);
    let accent_color = Color32::from_rgb(100, 149, 237); // Cornflower blue
    let text_color = Color32::from_rgb(230, 230, 230);

    style.visuals.window_fill = bg_color;
    style.visuals.panel_fill = panel_color;
    style.visuals.extreme_bg_color = Color32::from_rgb(20, 20, 25);

    // Selection colors
    style.visuals.selection.bg_fill = accent_color.gamma_multiply(0.5);
    style.visuals.selection.stroke = Stroke::new(1.0, accent_color);

    // Widget visuals
    style.visuals.widgets.noninteractive.bg_fill = panel_color;
    style.visuals.widgets.noninteractive.fg_stroke = Stroke::new(1.0, text_color);

    style.visuals.widgets.inactive.bg_fill = Color32::from_rgb(50, 50, 60);
    style.visuals.widgets.inactive.fg_stroke = Stroke::new(1.0, text_color);

    style.visuals.widgets.hovered.bg_fill = Color32::from_rgb(60, 60, 75);
    style.visuals.widgets.hovered.fg_stroke = Stroke::new(1.5, text_color);

    style.visuals.widgets.active.bg_fill = accent_color.gamma_multiply(0.7);
    style.visuals.widgets.active.fg_stroke = Stroke::new(2.0, text_color);

    // Rounded corners (using CornerRadius in egui 0.31+)
    let corner_radius = CornerRadius::same(4);
    style.visuals.widgets.noninteractive.corner_radius = corner_radius;
    style.visuals.widgets.inactive.corner_radius = corner_radius;
    style.visuals.widgets.hovered.corner_radius = corner_radius;
    style.visuals.widgets.active.corner_radius = corner_radius;
    style.visuals.window_corner_radius = CornerRadius::same(8);

    // Window shadow
    style.visuals.window_shadow.offset = [2, 4];
    style.visuals.window_shadow.blur = 8;
    style.visuals.window_shadow.spread = 0;
    style.visuals.window_shadow.color = Color32::from_black_alpha(100);

    // Popup shadow
    style.visuals.popup_shadow = style.visuals.window_shadow;

    // Minimal spacing
    style.spacing.item_spacing = Vec2::new(4.0, 4.0);
    style.spacing.window_margin = 8.0.into();
    style.spacing.button_padding = Vec2::new(8.0, 4.0);

    // Text styles
    let font_size = 14.0;
    style.text_styles.insert(
        TextStyle::Body,
        FontId::new(font_size, FontFamily::Proportional),
    );
    style.text_styles.insert(
        TextStyle::Button,
        FontId::new(font_size, FontFamily::Proportional),
    );
    style.text_styles.insert(
        TextStyle::Heading,
        FontId::new(12.0, FontFamily::Proportional),
    );
    style.text_styles.insert(
        TextStyle::Small,
        FontId::new(11.0, FontFamily::Proportional),
    );
    style.text_styles.insert(
        TextStyle::Monospace,
        FontId::new(font_size, FontFamily::Monospace),
    );

    style
}

/// Colors used throughout the UI
pub struct ThemeColors;

impl ThemeColors {
    pub const BACKGROUND: Color32 = Color32::from_rgb(30, 30, 35);
    pub const PANEL: Color32 = Color32::from_rgb(40, 40, 48);
    pub const ACCENT: Color32 = Color32::from_rgb(100, 149, 237);
    pub const TEXT: Color32 = Color32::from_rgb(230, 230, 230);
    pub const DIM_TEXT: Color32 = Color32::from_rgb(150, 150, 160);
    pub const SEPARATOR: Color32 = Color32::from_rgb(60, 60, 70);
    pub const HOVER: Color32 = Color32::from_rgb(60, 60, 75);
    pub const PIN_ICON: Color32 = Color32::from_rgb(255, 200, 50); // Gold
    pub const SHORTCUT_ICON: Color32 = Color32::from_rgb(255, 150, 50); // Orange
    pub const CLIPBOARD_ICON: Color32 = Color32::from_rgb(100, 200, 150); // Teal
    pub const SECTION_HEADER: Color32 = Color32::from_rgb(120, 120, 140);
}
