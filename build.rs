// build.rs – only runs when the "tauri" feature is active.
fn main() {
    #[cfg(feature = "tauri")]
    tauri_build::build();
}
