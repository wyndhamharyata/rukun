mod app;
mod data;
mod pages;

use std::borrow::Cow;

use gpui_kit::component::{Theme, ThemeMode};
use gpui_kit::*;

/// GPUI Kit's own icons, plus the spec's checkmark.
struct Assets;

impl AssetSource for Assets {
    fn load(&self, path: &str) -> Result<Option<Cow<'static, [u8]>>> {
        if path == "rukun/check.svg" {
            return Ok(Some(Cow::Borrowed(include_bytes!(
                "../../../spec/icons/check.svg"
            ))));
        }
        gpui_kit::assets::Assets.load(path)
    }

    fn list(&self, path: &str) -> Result<Vec<SharedString>> {
        gpui_kit::assets::Assets.list(path)
    }
}

fn main() {
    application().with_assets(Assets).run(|cx| {
        init(cx);
        apply_theme(cx);

        let options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(Bounds::centered(
                None,
                size(px(1100.), px(720.)),
                cx,
            ))),
            window_min_size: Some(size(px(900.), px(600.))),
            titlebar: Some(TitlebarOptions {
                title: Some("Rukun".into()),
                appears_transparent: true,
                traffic_light_position: None,
            }),
            ..Default::default()
        };

        open_window(options, cx, |window, cx| cx.new(|cx| app::Rukun::new(window, cx)))
            .expect("the window opens");
    });
}

/// Dark, with the spec's colours for the text the inputs draw.
fn apply_theme(cx: &mut App) {
    Theme::change(ThemeMode::Dark, None, cx);
    let theme = Theme::global_mut(cx);
    theme.font_family = ".SystemUIFont".into();
    theme.font_size = px(13.);
    theme.colors.foreground = rgb(app::TEXT).into();
    theme.colors.muted_foreground = rgb(app::FAINT).into();
    theme.colors.caret = rgb(app::ACCENT).into();
    theme.colors.selection = rgba(app::SELECTED_ROW).into();
}
