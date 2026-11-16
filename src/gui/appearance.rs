//! Local chat appearance preferences and bounded wallpaper decoding, owned by the worker.

use super::*;
use std::io::Read;

const APPEARANCE_FILE: &str = "chat_appearance.json";
const MAX_WALLPAPER_BYTES: u64 = 25 * 1024 * 1024;

/// User-selected chat background, independent of the light/dark interface palette.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(default)]
pub struct ChatAppearance {
    /// Opaque sRGB background; `None` selects the built-in gradient.
    pub color: Option<[u8; 3]>,
    /// Local image path. The image is never uploaded to Zalo.
    pub wallpaper: Option<String>,
    /// Black overlay strength, clamped to 0–0.8 when loaded.
    pub dim: f32,
    /// Show the decorative pattern on solid and default backgrounds.
    pub doodles: bool,
}

impl Default for ChatAppearance {
    fn default() -> Self {
        Self {
            color: None,
            wallpaper: None,
            dim: 0.15,
            doodles: true,
        }
    }
}

/// Decoded wallpaper ready for upload to the GUI's texture cache.
pub struct WallpaperImage {
    /// Original local path used to restore the background after a restart.
    pub path: String,
    /// Bounded, decoded pixels; decoding runs off the UI thread.
    pub image: egui::ColorImage,
}

/// Load local appearance preferences on the worker, treating a missing file as defaults.
///
/// # Errors
/// Returns a Vietnamese error when the preferences cannot be read or parsed.
pub(super) fn load_chat_appearance() -> Result<ChatAppearance, String> {
    load_chat_appearance_at(std::path::Path::new(APPEARANCE_FILE))
}

fn load_chat_appearance_at(path: &std::path::Path) -> Result<ChatAppearance, String> {
    let raw = match std::fs::read_to_string(path) {
        Ok(raw) => raw,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(ChatAppearance::default()),
        Err(_) => return Err("Không thể đọc cài đặt nền chat.".into()),
    };
    parse_chat_appearance(&raw)
}

fn parse_chat_appearance(raw: &str) -> Result<ChatAppearance, String> {
    let mut appearance: ChatAppearance = serde_json::from_str(raw).map_err(|_| {
        "Cài đặt nền chat không hợp lệ. Bạn có thể chọn lại trong Giao diện.".to_owned()
    })?;
    appearance.dim = if appearance.dim.is_finite() {
        appearance.dim.clamp(0.0, 0.8)
    } else {
        0.15
    };
    Ok(appearance)
}

/// Persist a snapshot on the worker, replacing the file only after a complete write.
///
/// # Errors
/// Returns a Vietnamese error when serialization, writing or replacement fails.
pub(super) fn save_chat_appearance(appearance: &ChatAppearance) -> Result<(), String> {
    save_chat_appearance_at(std::path::Path::new(APPEARANCE_FILE), appearance)
}

fn save_chat_appearance_at(
    path: &std::path::Path,
    appearance: &ChatAppearance,
) -> Result<(), String> {
    let raw = serde_json::to_vec_pretty(appearance)
        .map_err(|_| "Không thể lưu cài đặt nền chat.".to_owned())?;
    let tmp = path.with_extension("json.tmp");
    std::fs::write(&tmp, raw)
        .and_then(|_| std::fs::rename(&tmp, path))
        .map_err(|_| {
            "Không thể lưu cài đặt nền chat. Hãy kiểm tra quyền ghi thư mục ứng dụng.".into()
        })
}

/// Load a local image, bounding file size, decode allocation and the final texture dimensions.
///
/// # Errors
/// Returns a Vietnamese error for unreadable, oversized, unsupported or invalid images.
pub(super) fn load_chat_wallpaper(path: String) -> Result<WallpaperImage, String> {
    let file = std::fs::File::open(&path)
        .map_err(|_| "Không mở được ảnh nền. Hãy chọn lại ảnh trong Giao diện.".to_owned())?;
    let mut bytes = Vec::new();
    file.take(MAX_WALLPAPER_BYTES + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| "Không thể đọc ảnh nền.".to_owned())?;
    if bytes.len() as u64 > MAX_WALLPAPER_BYTES {
        return Err("Ảnh nền quá lớn. Vui lòng chọn ảnh nhỏ hơn 25 MB.".into());
    }
    Ok(WallpaperImage {
        path,
        image: decode_wallpaper(&bytes)?,
    })
}

fn decode_wallpaper(bytes: &[u8]) -> Result<egui::ColorImage, String> {
    let mut reader = image::ImageReader::new(std::io::Cursor::new(bytes))
        .with_guessed_format()
        .map_err(|_| "Không nhận diện được ảnh nền.".to_owned())?;
    let mut limits = image::Limits::default();
    limits.max_image_width = Some(8192);
    limits.max_image_height = Some(8192);
    limits.max_alloc = Some(128 * 1024 * 1024);
    reader.limits(limits);
    let image = reader.decode().map_err(|_| {
        "Không đọc được ảnh nền. Hãy chọn ảnh PNG, JPG hoặc GIF tối đa 8192 × 8192.".to_owned()
    })?;
    let image = image.thumbnail(2048, 2048).to_rgba8();
    Ok(egui::ColorImage::from_rgba_unmultiplied(
        [image.width() as usize, image.height() as usize],
        image.as_raw(),
    ))
}

/// Center-crop an image to fill the canvas while preserving its aspect ratio.
pub(super) fn wallpaper_uv(canvas: Vec2, image: Vec2) -> Rect {
    let canvas_aspect = canvas.x.max(1.0) / canvas.y.max(1.0);
    let image_aspect = image.x.max(1.0) / image.y.max(1.0);
    let visible = if image_aspect > canvas_aspect {
        Vec2::new(canvas_aspect / image_aspect, 1.0)
    } else {
        Vec2::new(1.0, image_aspect / canvas_aspect)
    };
    Rect::from_center_size(Pos2::new(0.5, 0.5), visible)
}

impl ZaloGuiApp {
    /// Debounce edits so dragging a color or dimming slider does not flood the worker.
    pub(super) fn queue_appearance_save(&mut self) {
        self.appearance_save_at = Some(std::time::Instant::now());
    }

    /// Send an appearance action, returning false and showing a toast if the worker is unavailable.
    pub(super) fn send_appearance_command(&mut self, command: WorkerCmd) -> bool {
        if WORKER_TX.get().map(|tx| tx.send(command).is_ok()) == Some(true) {
            true
        } else {
            self.show_toast("Chưa thể thay đổi nền chat. Hãy khởi động lại ứng dụng.");
            false
        }
    }

    /// Render background controls and a live preview without reading local files on the UI thread.
    pub(super) fn render_chat_appearance_settings(
        &mut self,
        ui: &mut egui::Ui,
        pal: &ThemePalette,
    ) {
        if !self.appearance_loaded {
            ui.horizontal(|ui| {
                ui.spinner();
                ui.label("Đang tải cài đặt nền chat…");
            });
            return;
        }
        ui.label(
            RichText::new("Nền cuộc trò chuyện")
                .color(pal.text_primary)
                .size(13.5)
                .strong(),
        );
        ui.add_space(6.0);
        egui::Frame::none()
            .fill(pal.bg_elevated)
            .stroke(Stroke::new(1.0_f32, pal.border))
            .rounding(Rounding::same(14.0))
            .inner_margin(Margin::symmetric(14.0, 12.0))
            .show(ui, |ui| {
                ui.label(
                    RichText::new(
                        "Chọn màu hoặc dùng ảnh của bạn. Khung Liquid Glass được giữ nguyên.",
                    )
                    .size(12.0)
                    .color(pal.text_secondary),
                );
                ui.add_space(8.0);
                let mut chosen_color = None;
                ui.horizontal_wrapped(|ui| {
                    ui.label("Màu nền");
                    let mut rgb = self.chat_appearance.color.unwrap_or_else(|| {
                        let [r, g, b, _] = pal.bg_chat_canvas.to_srgba_unmultiplied();
                        [r, g, b]
                    });
                    if ui.color_edit_button_srgb(&mut rgb).changed() {
                        chosen_color = Some(rgb);
                    }
                    for color in [
                        [188, 211, 175],
                        [207, 225, 239],
                        [229, 218, 238],
                        [236, 224, 204],
                        [42, 51, 62],
                    ] {
                        if ui
                            .add(
                                egui::Button::new("  ")
                                    .min_size(Vec2::splat(25.0))
                                    .fill(Color32::from_rgb(color[0], color[1], color[2]))
                                    .rounding(Rounding::same(12.5)),
                            )
                            .on_hover_text(format!(
                                "#{:02X}{:02X}{:02X}",
                                color[0], color[1], color[2]
                            ))
                            .clicked()
                        {
                            chosen_color = Some(color);
                        }
                    }
                });
                if let Some(color) = chosen_color {
                    self.chat_appearance.color = Some(color);
                    self.chat_appearance.wallpaper = None;
                    self.chat_wallpaper = None;
                    self.wallpaper_request_id = self.wallpaper_request_id.wrapping_add(1);
                    self.wallpaper_loading = false;
                    self.queue_appearance_save();
                }
                ui.add_space(8.0);
                ui.horizontal_wrapped(|ui| {
                    if ui
                        .add_enabled(!self.wallpaper_loading, egui::Button::new("Chọn ảnh nền…"))
                        .clicked()
                    {
                        self.wallpaper_request_id = self.wallpaper_request_id.wrapping_add(1);
                        self.wallpaper_loading =
                            self.send_appearance_command(WorkerCmd::LoadChatWallpaper {
                                request_id: self.wallpaper_request_id,
                                path: None,
                            });
                    }
                    if ui.button("Khôi phục mặc định").clicked() {
                        self.chat_appearance = ChatAppearance::default();
                        self.chat_wallpaper = None;
                        self.wallpaper_request_id = self.wallpaper_request_id.wrapping_add(1);
                        self.wallpaper_loading = false;
                        self.queue_appearance_save();
                    }
                    if self.wallpaper_loading {
                        ui.spinner();
                        ui.label("Đang mở ảnh…");
                    }
                });
                if let Some(path) = &self.chat_appearance.wallpaper {
                    let name = std::path::Path::new(path)
                        .file_name()
                        .unwrap_or_default()
                        .to_string_lossy();
                    ui.label(
                        RichText::new(format!("Ảnh nền: {name}"))
                            .size(12.0)
                            .color(pal.text_secondary),
                    );
                    if ui
                        .add(
                            egui::Slider::new(&mut self.chat_appearance.dim, 0.0..=0.8)
                                .text("Làm tối ảnh nền")
                                .show_value(false),
                        )
                        .changed()
                    {
                        self.queue_appearance_save();
                    }
                } else if ui
                    .checkbox(&mut self.chat_appearance.doodles, "Hiện họa tiết nền")
                    .changed()
                {
                    self.queue_appearance_save();
                }
                ui.label(
                    RichText::new("PNG, JPG hoặc GIF · tối đa 25 MB · chỉ lưu trên máy của bạn")
                        .size(11.0)
                        .color(pal.text_muted),
                );
                let (rect, _) =
                    ui.allocate_exact_size(Vec2::new(ui.available_width(), 76.0), Sense::hover());
                paint_chat_backdrop(
                    ui.painter(),
                    rect,
                    pal,
                    &self.chat_appearance,
                    self.chat_wallpaper.as_ref(),
                );
                let sample =
                    Rect::from_min_size(rect.min + Vec2::new(12.0, 19.0), Vec2::new(160.0, 36.0));
                ui.painter()
                    .rect_filled(sample, Rounding::same(16.0), pal.bubble_in_bg);
                ui.painter().text(
                    sample.center(),
                    egui::Align2::CENTER_CENTER,
                    "Xem trước nền chat",
                    FontId::proportional(12.0),
                    pal.bubble_in_text,
                );
            });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn appearance_survives_restart_and_replaces_previous_preferences() {
        let path = std::env::temp_dir().join(format!(
            "ctdozlite-appearance-{}-{}.json",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        assert!(load_chat_appearance_at(&path).unwrap().color.is_none());
        let mut appearance = ChatAppearance {
            color: Some([30, 60, 90]),
            wallpaper: Some("sample.png".into()),
            ..Default::default()
        };
        save_chat_appearance_at(&path, &appearance).unwrap();
        let restored = load_chat_appearance_at(&path).unwrap();
        assert_eq!(restored.color, appearance.color);
        assert_eq!(restored.wallpaper, appearance.wallpaper);
        appearance.color = Some([100, 90, 80]);
        appearance.wallpaper = None;
        save_chat_appearance_at(&path, &appearance).unwrap();
        let restored = load_chat_appearance_at(&path).unwrap();
        assert_eq!(restored.color, appearance.color);
        assert!(restored.wallpaper.is_none());
        std::fs::remove_file(path).unwrap();
    }

    #[test]
    fn appearance_restores_defaults_when_fields_are_absent() {
        let appearance = parse_chat_appearance("{}").unwrap();
        assert!(appearance.color.is_none());
        assert!(appearance.wallpaper.is_none());
        assert!(appearance.doodles);
        assert_eq!(appearance.dim, 0.15);
    }

    #[test]
    fn appearance_preserves_custom_background_and_clamps_dim() {
        let appearance = parse_chat_appearance(
            r#"{"color":[34,90,120],"wallpaper":"sample.png","dim":5,"doodles":false}"#,
        )
        .unwrap();
        assert_eq!(appearance.color, Some([34, 90, 120]));
        assert_eq!(appearance.wallpaper.as_deref(), Some("sample.png"));
        assert_eq!(appearance.dim, 0.8);
        assert!(!appearance.doodles);
        let roundtrip =
            parse_chat_appearance(&serde_json::to_string(&appearance).unwrap()).unwrap();
        assert_eq!(roundtrip.color, appearance.color);
        assert_eq!(roundtrip.wallpaper, appearance.wallpaper);
        assert!(parse_chat_appearance("broken").is_err());
    }

    #[test]
    fn wallpaper_crop_fills_canvas_without_stretching() {
        let wide = wallpaper_uv(Vec2::new(100.0, 100.0), Vec2::new(200.0, 100.0));
        assert_eq!(
            wide,
            Rect::from_min_max(Pos2::new(0.25, 0.0), Pos2::new(0.75, 1.0))
        );
        let tall = wallpaper_uv(Vec2::new(100.0, 100.0), Vec2::new(100.0, 200.0));
        assert_eq!(
            tall,
            Rect::from_min_max(Pos2::new(0.0, 0.25), Pos2::new(1.0, 0.75))
        );
    }

    #[test]
    fn wallpaper_decode_rejects_invalid_data_and_bounds_texture() {
        assert!(decode_wallpaper(b"not an image").is_err());
        let image = image::RgbaImage::from_pixel(2400, 1200, image::Rgba([30, 80, 100, 255]));
        let mut encoded = std::io::Cursor::new(Vec::new());
        image
            .write_to(&mut encoded, image::ImageFormat::Png)
            .unwrap();
        let decoded = decode_wallpaper(encoded.get_ref()).unwrap();
        assert_eq!(decoded.size, [2048, 1024]);
        assert_eq!(decoded.pixels[0], Color32::from_rgb(30, 80, 100));
        let oversized = image::RgbaImage::new(8193, 1);
        let mut encoded = std::io::Cursor::new(Vec::new());
        oversized
            .write_to(&mut encoded, image::ImageFormat::Png)
            .unwrap();
        assert!(decode_wallpaper(encoded.get_ref()).is_err());
    }
}
