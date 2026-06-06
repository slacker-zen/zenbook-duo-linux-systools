use serde::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    env, fs,
    io::Write,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::Mutex,
    thread,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, State, WindowEvent, Wry,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ConfigFileView {
    id: String,
    title: String,
    path: String,
    writable: bool,
    entries: Vec<ConfigEntryView>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ConfigEntryView {
    key: String,
    value: String,
    kind: String,
    description: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct ConfigWriteEntry {
    key: String,
    value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct RuntimeStatus {
    matrix: HashMap<String, String>,
    sysstates: String,
    keyboard_backlight: KeyboardBacklightStatus,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct KeyboardBacklightStatus {
    built_in_percent: Option<u8>,
    detachable_level: Option<u8>,
    detachable_max: u8,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct DisplayBrightness {
    main: DisplayBrightnessScreen,
    lower: DisplayBrightnessScreen,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct DisplayBrightnessScreen {
    id: String,
    name: String,
    path: String,
    available: bool,
    percent: Option<u8>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
enum HelperKind {
    Matrix,
    Sysstates,
    Fnkeys,
}

impl HelperKind {
    fn as_str(&self) -> &'static str {
        match self {
            HelperKind::Matrix => "matrix",
            HelperKind::Sysstates => "sysstates",
            HelperKind::Fnkeys => "fnkeys",
        }
    }
}

#[derive(Default)]
struct AppState {
    configs: Mutex<Option<Vec<ConfigFileView>>>,
    status: Mutex<Option<RuntimeStatus>>,
    brightness: Mutex<Option<DisplayBrightness>>,
    tray: Mutex<Option<TrayMenuItems>>,
}

#[derive(Clone)]
struct TrayMenuItems {
    mode: MenuItem<Wry>,
    transport: MenuItem<Wry>,
    brightness: MenuItem<Wry>,
    keyboard: MenuItem<Wry>,
}

const DEFAULT_CONTROL_TIMEOUT: Duration = Duration::from_secs(20);

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .and_then(Path::parent)
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("."))
}

fn control_path() -> PathBuf {
    if let Ok(path) = env::var("ZENBOOK_DUO_CONTROL") {
        return PathBuf::from(path);
    }

    let installed = PathBuf::from("/usr/bin/zenbook-duo-control");
    if installed.exists() {
        installed
    } else {
        repo_root().join("control/zenbook-duo-control.sh")
    }
}

fn state_dir() -> PathBuf {
    if let Ok(path) = env::var("ZENBOOK_DUO_LOG_DIR") {
        return PathBuf::from(path);
    }
    if let Ok(path) = env::var("XDG_STATE_HOME") {
        return PathBuf::from(path).join("zenbook-duo");
    }
    if let Ok(home) = env::var("HOME") {
        return PathBuf::from(home).join(".local/state/zenbook-duo");
    }
    env::temp_dir().join("zenbook-duo")
}

fn log_path() -> PathBuf {
    state_dir().join("ui.log")
}

fn timestamp() -> String {
    let seconds = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0);
    seconds.to_string()
}

fn append_log(message: impl AsRef<str>) {
    let path = log_path();
    if let Some(parent) = path.parent() {
        let _ = fs::create_dir_all(parent);
    }

    if let Ok(mut file) = fs::OpenOptions::new().create(true).append(true).open(&path) {
        let _ = writeln!(file, "[{}] {}", timestamp(), message.as_ref());
    }
}

fn control_timeout() -> Duration {
    env::var("ZENBOOK_DUO_UI_COMMAND_TIMEOUT_SECONDS")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .filter(|seconds| *seconds > 0)
        .map(Duration::from_secs)
        .unwrap_or(DEFAULT_CONTROL_TIMEOUT)
}

fn display_args(args: &[String]) -> String {
    args.join(" ")
}

fn run_control(args: &[String]) -> Result<String, String> {
    let path = control_path();
    let mut command = if path.extension().is_some_and(|extension| extension == "sh") {
        let mut command = Command::new("bash");
        command.arg(&path);
        command
    } else {
        Command::new(&path)
    };

    let timeout = control_timeout();
    append_log(format!(
        "control start path={} args=\"{}\" timeout={}s",
        path.display(),
        display_args(args),
        timeout.as_secs()
    ));

    let mut child = command
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("Failed to run {}: {error}", path.display()))?;

    let started = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if started.elapsed() >= timeout => {
                let pid = child.id();
                let _ = child.kill();
                let _ = child.wait();
                let message = format!(
                    "Timed out after {}s running {} {}",
                    timeout.as_secs(),
                    path.display(),
                    display_args(args)
                );
                append_log(format!(
                    "control timeout pid={pid} args=\"{}\"",
                    display_args(args)
                ));
                return Err(message);
            }
            Ok(None) => thread::sleep(Duration::from_millis(50)),
            Err(error) => {
                append_log(format!(
                    "control wait failed args=\"{}\" error={error}",
                    display_args(args)
                ));
                return Err(format!("Failed waiting for {}: {error}", path.display()));
            }
        }
    }

    let output = child
        .wait_with_output()
        .map_err(|error| format!("Failed to read {} output: {error}", path.display()))?;
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    append_log(format!(
        "control done status={} elapsed_ms={} args=\"{}\" stdout=\"{}\" stderr=\"{}\"",
        output.status,
        started.elapsed().as_millis(),
        display_args(args),
        stdout.chars().take(500).collect::<String>(),
        stderr.chars().take(500).collect::<String>()
    ));

    if output.status.success() {
        Ok(stdout)
    } else {
        Err(if stderr.is_empty() { stdout } else { stderr })
    }
}

fn fetch_configs() -> Result<Vec<ConfigFileView>, String> {
    let output = run_control(&[
        String::from("config"),
        String::from("list"),
        String::from("--json"),
    ])?;
    serde_json::from_str(&output).map_err(|error| format!("Invalid control config JSON: {error}"))
}

fn fetch_status() -> Result<RuntimeStatus, String> {
    let output = run_control(&[String::from("status"), String::from("--json")])?;
    serde_json::from_str(&output).map_err(|error| format!("Invalid control status JSON: {error}"))
}

fn fetch_brightness() -> Result<DisplayBrightness, String> {
    let output = run_control(&[
        String::from("display"),
        String::from("brightness"),
        String::from("--json"),
    ])?;
    serde_json::from_str(&output)
        .map_err(|error| format!("Invalid control brightness JSON: {error}"))
}

fn refresh_configs_cache(state: &AppState) -> Result<Vec<ConfigFileView>, String> {
    let configs = fetch_configs()?;
    *state.configs.lock().map_err(|error| error.to_string())? = Some(configs.clone());
    Ok(configs)
}

fn refresh_status_cache(state: &AppState) -> Result<RuntimeStatus, String> {
    let status = fetch_status()?;
    *state.status.lock().map_err(|error| error.to_string())? = Some(status.clone());
    Ok(status)
}

fn refresh_brightness_cache(state: &AppState) -> Result<DisplayBrightness, String> {
    let brightness = fetch_brightness()?;
    *state.brightness.lock().map_err(|error| error.to_string())? = Some(brightness.clone());
    Ok(brightness)
}

fn refresh_live_cache(state: &AppState) {
    if let Err(error) = refresh_status_cache(state) {
        append_log(format!("status refresh failed: {error}"));
    }
    if let Err(error) = refresh_brightness_cache(state) {
        append_log(format!("brightness refresh failed: {error}"));
    }
}

fn update_tray_state(app: &AppHandle) {
    let state = app.state::<AppState>();
    let items = match state.tray.lock().ok().and_then(|items| items.clone()) {
        Some(items) => items,
        None => return,
    };

    let status = state.status.lock().ok().and_then(|status| status.clone());
    let brightness = state
        .brightness
        .lock()
        .ok()
        .and_then(|brightness| brightness.clone());

    let mode = status
        .as_ref()
        .and_then(|status| status.matrix.get("physical_mode"))
        .map(String::as_str)
        .unwrap_or("unknown");
    let transport = status
        .as_ref()
        .and_then(|status| status.matrix.get("transport"))
        .map(String::as_str)
        .unwrap_or("unknown");
    let brightness_text = brightness
        .map(|brightness| {
            format!(
                "Brightness: main {}%, lower {}%",
                brightness
                    .main
                    .percent
                    .map(|value| value.to_string())
                    .unwrap_or_else(|| String::from("n/a")),
                brightness
                    .lower
                    .percent
                    .map(|value| value.to_string())
                    .unwrap_or_else(|| String::from("n/a"))
            )
        })
        .unwrap_or_else(|| String::from("Brightness: unknown"));
    let keyboard_text = status
        .as_ref()
        .map(|status| {
            format!(
                "Keyboard lights: built-in {}, detachable {}",
                status
                    .keyboard_backlight
                    .built_in_percent
                    .map(|value| format!("{value}%"))
                    .unwrap_or_else(|| String::from("n/a")),
                status
                    .keyboard_backlight
                    .detachable_level
                    .map(|value| format!("{value}/{}", status.keyboard_backlight.detachable_max))
                    .unwrap_or_else(|| String::from("n/a"))
            )
        })
        .unwrap_or_else(|| String::from("Keyboard lights: unknown"));

    let _ = items.mode.set_text(format!("Mode: {mode}"));
    let _ = items.transport.set_text(format!("Transport: {transport}"));
    let _ = items.brightness.set_text(brightness_text);
    let _ = items.keyboard.set_text(keyboard_text);
}

fn spawn_slots(app: AppHandle) {
    let live_app = app.clone();
    thread::spawn(move || loop {
        let state = live_app.state::<AppState>();
        refresh_live_cache(&state);
        thread::sleep(Duration::from_millis(2500));
    });

    let config_app = app.clone();
    thread::spawn(move || loop {
        let state = config_app.state::<AppState>();
        let _ = refresh_configs_cache(&state);
        thread::sleep(Duration::from_secs(15));
    });

    thread::spawn(move || loop {
        if let Some(window) = app.get_webview_window("main") {
            let tray_app = app.clone();
            let _ = window.run_on_main_thread(move || update_tray_state(&tray_app));
        }
        thread::sleep(Duration::from_secs(5));
    });
}

fn refresh_all_caches(state: &AppState) {
    refresh_live_cache(state);
    let _ = refresh_configs_cache(state);
}

fn refresh_all_caches_once(app: AppHandle) {
    thread::spawn(move || {
        let state = app.state::<AppState>();
        refresh_all_caches(&state);
        if let Some(window) = app.get_webview_window("main") {
            let tray_app = app.clone();
            let _ = window.run_on_main_thread(move || update_tray_state(&tray_app));
        }
    });
}

fn write_temp_json(entries: &[ConfigWriteEntry]) -> Result<PathBuf, String> {
    let mut path = env::temp_dir();
    path.push(format!("zenbook-duo-ui-config-{}.json", std::process::id()));
    let content = serde_json::to_string(entries).map_err(|error| error.to_string())?;
    fs::write(&path, content).map_err(|error| format!("Failed to write temp JSON: {error}"))?;
    Ok(path)
}

#[tauri::command]
fn read_configs(state: State<'_, AppState>) -> Result<Vec<ConfigFileView>, String> {
    if let Some(configs) = state
        .configs
        .lock()
        .map_err(|error| error.to_string())?
        .clone()
    {
        Ok(configs)
    } else {
        refresh_configs_cache(&state)
    }
}

#[tauri::command]
fn write_config(
    state: State<'_, AppState>,
    file_id: String,
    entries: Vec<ConfigWriteEntry>,
) -> Result<(), String> {
    let entries_path = write_temp_json(&entries)?;
    let result = run_control(&[
        String::from("config"),
        String::from("write"),
        file_id,
        entries_path.display().to_string(),
    ]);
    let _ = fs::remove_file(entries_path);
    result?;
    let _ = refresh_configs_cache(&state);
    Ok(())
}

#[tauri::command]
fn run_helper(
    state: State<'_, AppState>,
    helper: HelperKind,
    args: Vec<String>,
) -> Result<String, String> {
    let mut control_args = vec![String::from("action"), helper.as_str().to_string()];
    control_args.extend(args);
    let result = run_control(&control_args)?;
    refresh_live_cache(&state);
    Ok(result)
}

#[tauri::command]
fn runtime_status(state: State<'_, AppState>) -> Result<RuntimeStatus, String> {
    if let Some(status) = state
        .status
        .lock()
        .map_err(|error| error.to_string())?
        .clone()
    {
        Ok(status)
    } else {
        refresh_status_cache(&state)
    }
}

#[tauri::command]
fn display_brightness(state: State<'_, AppState>) -> Result<DisplayBrightness, String> {
    if let Some(brightness) = state
        .brightness
        .lock()
        .map_err(|error| error.to_string())?
        .clone()
    {
        Ok(brightness)
    } else {
        refresh_brightness_cache(&state)
    }
}

#[tauri::command]
fn step_display_brightness(
    state: State<'_, AppState>,
    target: String,
    increment: u8,
) -> Result<DisplayBrightness, String> {
    let output = run_control(&[
        String::from("display"),
        String::from("brightness"),
        String::from("step"),
        target,
        increment.to_string(),
    ])?;
    let brightness: DisplayBrightness = serde_json::from_str(&output)
        .map_err(|error| format!("Invalid control brightness JSON: {error}"))?;
    *state.brightness.lock().map_err(|error| error.to_string())? = Some(brightness.clone());
    Ok(brightness)
}

#[tauri::command]
fn set_display_brightness(
    state: State<'_, AppState>,
    target: String,
    percent: u8,
) -> Result<DisplayBrightness, String> {
    let output = run_control(&[
        String::from("display"),
        String::from("brightness"),
        String::from("set"),
        target,
        percent.to_string(),
    ])?;
    let brightness: DisplayBrightness = serde_json::from_str(&output)
        .map_err(|error| format!("Invalid control brightness JSON: {error}"))?;
    *state.brightness.lock().map_err(|error| error.to_string())? = Some(brightness.clone());
    Ok(brightness)
}

fn show_main_window(app: &tauri::AppHandle) {
    refresh_all_caches_once(app.clone());
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

fn run_tray_action(helper: &str, args: &[&str]) {
    let mut control_args = vec![String::from("action"), helper.to_string()];
    control_args.extend(args.iter().map(|arg| arg.to_string()));
    thread::spawn(move || {
        if let Err(error) = run_control(&control_args) {
            append_log(format!("tray action failed: {error}"));
        }
    });
}

fn build_tray(app: &tauri::App) -> tauri::Result<()> {
    let show = MenuItem::with_id(app, "show", "Open Zenbook Utility", true, None::<&str>)?;
    let mode = MenuItem::with_id(app, "state_mode", "Mode: unknown", false, None::<&str>)?;
    let transport = MenuItem::with_id(
        app,
        "state_transport",
        "Transport: unknown",
        false,
        None::<&str>,
    )?;
    let brightness = MenuItem::with_id(
        app,
        "state_brightness",
        "Brightness: unknown",
        false,
        None::<&str>,
    )?;
    let keyboard = MenuItem::with_id(
        app,
        "state_keyboard",
        "Keyboard lights: unknown",
        false,
        None::<&str>,
    )?;
    let reconcile = MenuItem::with_id(app, "reconcile", "Reconcile Matrix", true, None::<&str>)?;
    let attached = MenuItem::with_id(app, "attached", "Apply Attached Layout", true, None::<&str>)?;
    let detached = MenuItem::with_id(app, "detached", "Apply Detached Layout", true, None::<&str>)?;
    let light_off = MenuItem::with_id(
        app,
        "light_off",
        "All Keyboard Lights Off",
        true,
        None::<&str>,
    )?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let separator = PredefinedMenuItem::separator(app)?;
    let menu = Menu::with_items(
        app,
        &[
            &mode,
            &transport,
            &brightness,
            &keyboard,
            &separator,
            &show,
            &separator,
            &reconcile,
            &attached,
            &detached,
            &light_off,
            &separator,
            &quit,
        ],
    )?;

    let icon = app
        .default_window_icon()
        .cloned()
        .expect("application icon is configured");

    TrayIconBuilder::with_id("zenbook-duo")
        .tooltip("Zenbook Duo Utility")
        .icon(icon)
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                show_main_window(&tray.app_handle());
            }
        })
        .on_menu_event(|app, event| match event.id.as_ref() {
            "show" => show_main_window(app),
            "reconcile" => run_tray_action("matrix", &["reconcile"]),
            "attached" => run_tray_action("sysstates", &["display", "attached"]),
            "detached" => run_tray_action("sysstates", &["display", "detached"]),
            "light_off" => run_tray_action("sysstates", &["light-off"]),
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;

    if let Ok(mut tray) = app.state::<AppState>().tray.lock() {
        *tray = Some(TrayMenuItems {
            mode,
            transport,
            brightness,
            keyboard,
        });
    }

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    append_log("ui starting");
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(AppState::default())
        .setup(|app| {
            build_tray(app)?;
            spawn_slots(app.handle().clone());
            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .invoke_handler(tauri::generate_handler![
            read_configs,
            write_config,
            run_helper,
            runtime_status,
            display_brightness,
            step_display_brightness,
            set_display_brightness
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
