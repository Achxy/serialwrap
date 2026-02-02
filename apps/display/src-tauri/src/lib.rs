mod commands;
mod state;

use std::sync::Arc;
use state::AppState;

pub fn run() {
    let state = Arc::new(AppState::new());

    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::new().build())
        .manage(state)
        .invoke_handler(tauri::generate_handler![
            commands::list_usb_devices,
            commands::wait_for_connection,
            commands::disconnect,
            commands::start_display,
            commands::stop_display,
            commands::toggle_fullscreen,
            commands::get_display_stats,
            commands::get_connection_status,
            commands::get_negotiated_params,
            commands::get_settings,
            commands::save_settings,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
