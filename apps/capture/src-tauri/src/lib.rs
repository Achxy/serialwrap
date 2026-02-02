mod commands;
mod state;

use std::sync::Arc;
use state::AppState;

pub fn run() {
    let state = Arc::new(AppState::new());

    tauri::Builder::default()
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(tauri_plugin_updater::Builder::new().build())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_process::init())
        .manage(state)
        .invoke_handler(tauri::generate_handler![
            commands::list_displays,
            commands::list_usb_devices,
            commands::connect_transport,
            commands::disconnect_transport,
            commands::get_connection_status,
            commands::create_virtual_display,
            commands::destroy_virtual_display,
            commands::start_streaming,
            commands::stop_streaming,
            commands::get_stream_stats,
            commands::get_settings,
            commands::save_settings,
            commands::get_debug_info,
            commands::get_last_error,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
