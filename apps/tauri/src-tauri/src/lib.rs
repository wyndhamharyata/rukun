use tauri::window::Color;
use tauri::{TitleBarStyle, WebviewUrl, WebviewWindowBuilder};

// The shared React app prints the spec's lines through this, to stdout, where the harness reads.
#[tauri::command]
fn testapp_print(text: String) {
    println!("{text}");
}

#[tauri::command]
fn testapp_quit(app: tauri::AppHandle) {
    app.exit(0);
}

// The harness's settings, from the test app spec, for window.testapp.
fn testapp_script() -> String {
    let get = |name: &str| std::env::var(name).unwrap_or_default();
    let seconds = get("TESTAPP_SCROLL_SECONDS").parse::<f64>().unwrap_or(20.0);
    let settings = serde_json::json!({
        "page": get("TESTAPP_PAGE"),
        "mark": get("TESTAPP_MARK") == "1",
        "scroll": get("TESTAPP_SCROLL") == "1",
        "scrollSeconds": seconds,
    });

    format!(
        "window.testapp = {{ settings: {settings}, \
         print: (text) => window.__TAURI_INTERNALS__.invoke('testapp_print', {{ text }}), \
         quit: () => window.__TAURI_INTERNALS__.invoke('testapp_quit') }};"
    )
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![testapp_print, testapp_quit])
        .setup(|app| {
            WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
                .title("Rukun")
                .inner_size(1100.0, 720.0)
                .min_inner_size(900.0, 600.0)
                .title_bar_style(TitleBarStyle::Overlay)
                .hidden_title(true)
                .background_color(Color(0x12, 0x12, 0x14, 0xff))
                .theme(Some(tauri::Theme::Dark))
                .initialization_script(&testapp_script())
                .build()?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
