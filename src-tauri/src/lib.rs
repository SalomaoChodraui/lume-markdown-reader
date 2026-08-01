use serde::Serialize;
use std::{
    fs,
    path::{Path, PathBuf},
    sync::Mutex,
    time::UNIX_EPOCH,
};
use tauri::{Emitter, Manager};

#[derive(Default)]
struct OpenRequestState {
    inner: Mutex<OpenRequestInner>,
}

#[derive(Default)]
struct OpenRequestInner {
    frontend_ready: bool,
    pending_paths: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct MarkdownFile {
    content: String,
    last_modified: u64,
    name: String,
    path: String,
    source_path: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct OpenMarkdownResult {
    files: Vec<MarkdownFile>,
    kind: &'static str,
    name: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct RefreshedMarkdown {
    content: String,
    last_modified: u64,
}

fn is_markdown(path: &Path) -> bool {
    path.extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|extension| {
            matches!(
                extension.to_ascii_lowercase().as_str(),
                "md" | "markdown" | "mdown"
            )
        })
}

fn modified_millis(metadata: &fs::Metadata) -> u64 {
    metadata
        .modified()
        .ok()
        .and_then(|modified| modified.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or_default()
}

fn display_name(path: &Path) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.to_string_lossy().into_owned())
}

fn read_markdown(path: &Path, relative_path: String) -> Result<MarkdownFile, String> {
    if !is_markdown(path) {
        return Err("Esse arquivo não parece ser Markdown.".into());
    }

    let bytes = fs::read(path).map_err(|error| format!("Não consegui ler o arquivo: {error}"))?;
    let metadata =
        fs::metadata(path).map_err(|error| format!("Não consegui acessar o arquivo: {error}"))?;

    Ok(MarkdownFile {
        content: String::from_utf8_lossy(&bytes).into_owned(),
        last_modified: modified_millis(&metadata),
        name: display_name(path),
        path: relative_path,
        source_path: path.to_string_lossy().into_owned(),
    })
}

fn collect_markdown(
    root: &Path,
    directory: &Path,
    files: &mut Vec<MarkdownFile>,
) -> Result<(), String> {
    let entries =
        fs::read_dir(directory).map_err(|error| format!("Não consegui ler a pasta: {error}"))?;

    for entry in entries {
        let entry = entry.map_err(|error| format!("Não consegui ler um item: {error}"))?;
        let file_type = entry
            .file_type()
            .map_err(|error| format!("Não consegui identificar um item: {error}"))?;
        let path = entry.path();

        if file_type.is_dir() {
            collect_markdown(root, &path, files)?;
        } else if file_type.is_file() && is_markdown(&path) {
            let relative_path = path
                .strip_prefix(root)
                .unwrap_or(&path)
                .to_string_lossy()
                .replace('\\', "/");
            files.push(read_markdown(&path, relative_path)?);
        }
    }

    Ok(())
}

#[tauri::command]
fn open_markdown_path(path: String) -> Result<OpenMarkdownResult, String> {
    let source = PathBuf::from(&path);
    let metadata =
        fs::metadata(&source).map_err(|error| format!("Não consegui abrir o caminho: {error}"))?;

    if metadata.is_dir() {
        let mut files = Vec::new();
        collect_markdown(&source, &source, &mut files)?;
        files.sort_by_key(|file| file.path.to_lowercase());
        Ok(OpenMarkdownResult {
            files,
            kind: "folder",
            name: display_name(&source),
        })
    } else {
        let name = display_name(&source);
        Ok(OpenMarkdownResult {
            files: vec![read_markdown(&source, name.clone())?],
            kind: "file",
            name: "Arquivo avulso".into(),
        })
    }
}

#[tauri::command]
fn refresh_markdown_file(path: String) -> Result<RefreshedMarkdown, String> {
    let source = PathBuf::from(path);
    if !is_markdown(&source) {
        return Err("Esse arquivo não parece ser Markdown.".into());
    }

    let bytes =
        fs::read(&source).map_err(|error| format!("Não consegui atualizar o arquivo: {error}"))?;
    let metadata = fs::metadata(&source)
        .map_err(|error| format!("Não consegui atualizar o arquivo: {error}"))?;

    Ok(RefreshedMarkdown {
        content: String::from_utf8_lossy(&bytes).into_owned(),
        last_modified: modified_millis(&metadata),
    })
}

#[tauri::command]
fn frontend_ready(state: tauri::State<'_, OpenRequestState>) -> Vec<String> {
    let mut state = state.inner.lock().expect("open request state poisoned");
    state.frontend_ready = true;
    std::mem::take(&mut state.pending_paths)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let app = tauri::Builder::default()
        .manage(OpenRequestState::default())
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            frontend_ready,
            open_markdown_path,
            refresh_markdown_file
        ])
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building Lume");

    app.run(|app_handle, event| {
        #[cfg(target_os = "macos")]
        if let tauri::RunEvent::Opened { urls } = event {
            let paths: Vec<String> = urls
                .into_iter()
                .filter_map(|url| url.to_file_path().ok())
                .filter(|path| is_markdown(path))
                .map(|path| path.to_string_lossy().into_owned())
                .collect();

            if paths.is_empty() {
                return;
            }

            let should_emit = {
                let state = app_handle.state::<OpenRequestState>();
                let mut state = state.inner.lock().expect("open request state poisoned");
                if state.frontend_ready {
                    true
                } else {
                    state.pending_paths.extend(paths.clone());
                    false
                }
            };

            if should_emit {
                let _ = app_handle.emit("open-markdown-files", paths);
            }
            if let Some(window) = app_handle.get_webview_window("main") {
                let _ = window.show();
                let _ = window.set_focus();
            }
        }
    });
}
