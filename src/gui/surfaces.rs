//! Floating glass surfaces and a lightweight, resolution-independent chat wallpaper.

use super::*;

/// Build a legible floating surface, with a light-catching rim when vibrancy is active.
pub(super) fn floating_surface(pal: &ThemePalette, radius: f32) -> egui::Frame {
    let fill = if !pal.is_glass {
        pal.bg_sidebar
    } else if pal.is_dark {
        Color32::from_rgba_unmultiplied(29, 42, 44, 185)
    } else {
        Color32::from_rgba_unmultiplied(250, 255, 251, 150)
    };
    egui::Frame::none()
        .fill(fill)
        .rounding(Rounding::same(radius))
        .stroke(Stroke::new(1.0_f32, pal.border))
        .shadow(egui::epaint::Shadow {
            offset: Vec2::new(0.0, 3.0),
            blur: if pal.is_glass { 16.0 } else { 8.0 },
            spread: 0.0,
            color: Color32::from_black_alpha(if pal.is_dark { 24 } else { 12 }),
        })
}

/// Keep sidebar text inside its measured slot without splitting Vietnamese glyphs.
pub(super) fn paint_elided_text(
    painter: &egui::Painter,
    pos: Pos2,
    text: &str,
    width: f32,
    size: f32,
    color: Color32,
) {
    let mut job = egui::text::LayoutJob::simple_singleline(
        text.to_owned(),
        FontId::proportional(size),
        color,
    );
    job.wrap.max_width = width.max(0.0);
    job.wrap.max_rows = 1;
    job.wrap.break_anywhere = true;
    painter.galley(pos, painter.layout_job(job), color);
}

/// Paint a static sage gradient and sparse doodles without loading image assets or doing I/O.
pub(super) fn paint_chat_backdrop(
    painter: &egui::Painter,
    rect: Rect,
    pal: &ThemePalette,
    appearance: &ChatAppearance,
    wallpaper: Option<&TextureHandle>,
) {
    let alpha = if pal.is_glass { 150 } else { 255 };
    let colors = if pal.is_dark {
        [(43, 65, 48), (36, 58, 51), (29, 65, 61), (32, 52, 48)]
    } else {
        [
            (204, 221, 167),
            (183, 214, 175),
            (150, 197, 181),
            (182, 213, 177),
        ]
    };
    let mut mesh = egui::Mesh::default();
    for (pos, (r, g, b)) in [
        rect.left_top(),
        rect.right_top(),
        rect.right_bottom(),
        rect.left_bottom(),
    ]
    .into_iter()
    .zip(colors)
    {
        mesh.colored_vertex(pos, Color32::from_rgba_unmultiplied(r, g, b, alpha));
    }
    mesh.add_triangle(0, 1, 2);
    mesh.add_triangle(0, 2, 3);
    let painter = painter.with_clip_rect(rect);
    if let Some([r, g, b]) = appearance.color {
        painter.rect_filled(rect, Rounding::ZERO, Color32::from_rgb(r, g, b));
    } else {
        painter.add(egui::Shape::mesh(mesh));
    }
    if let Some(texture) = wallpaper {
        painter.image(
            texture.id(),
            rect,
            wallpaper_uv(rect.size(), texture.size_vec2()),
            Color32::WHITE,
        );
        painter.rect_filled(
            rect,
            Rounding::ZERO,
            Color32::from_black_alpha((appearance.dim.clamp(0.0, 0.8) * 255.0) as u8),
        );
        return;
    }
    if !appearance.doodles {
        return;
    }

    let ink = if pal.is_dark {
        Color32::from_rgba_unmultiplied(175, 220, 181, 4)
    } else {
        Color32::from_rgba_unmultiplied(53, 105, 74, 12)
    };
    let icons = [lucide::SEND, lucide::CLOUD, lucide::SMILE, lucide::STAR];
    let rows = (rect.height() / 104.0).ceil() as usize;
    let cols = (rect.width() / 116.0).ceil() as usize;
    for row in 0..=rows {
        for col in 0..=cols {
            let center = rect.min
                + Vec2::new(
                    col as f32 * 116.0 + if row % 2 == 0 { 26.0 } else { 80.0 },
                    row as f32 * 104.0 + 32.0,
                );
            draw_lucide_icon(
                &painter,
                center,
                icons[(row + col * 3) % icons.len()],
                26.0,
                ink,
            );
            painter.circle_stroke(
                center + Vec2::new(39.0, 37.0),
                3.0,
                Stroke::new(1.0_f32, ink),
            );
        }
    }
}
