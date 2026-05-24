use crate::model::PasteIndex;
use std::path::Path;
use std::fs::File;
use std::io::Read;

pub fn load_search_dirs() -> Vec<String> {
    vec!["/mnt/data1/spool/uucp/pastebin".to_string()]
}

pub fn load_paste_entries_from_dirs(_dirs: &[String]) -> Vec<PasteIndex> {
    Vec::new()
}

pub fn load_pastes_with_content(_dirs: &[String]) -> Vec<(PasteIndex, String)> {
    Vec::new()
}

pub fn read_workspace_paths() -> Vec<String> {
    Vec::new()
}
