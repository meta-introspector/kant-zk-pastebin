use wasm_bindgen::prelude::*;
use web_sys::{console, window, Document, HtmlElement};

// A macro to provide `println!(..)`-style syntax for `console.log` logging.
macro_rules! console_log {
    ($($t:tt)*) => (console::log_1(&format!($($t)*).into()))
}

#[wasm_bindgen(start)]
pub fn run() -> Result<(), JsValue> {
    console_log!("WASM module started.");

    let window = window().expect("no global `window` exists");
    let document = window.document().expect("should have a document on window");

    // Get buttons and add event listeners
    let save_config_button = get_element_by_id::<HtmlElement>(&document, "saveConfig")?;
    let save_config_closure = Closure::wrap(Box::new(move || {
        console_log!("Save Config button clicked");
        // TODO: Implement save_config
    }) as Box<dyn FnMut()>);
    save_config_button.set_onclick(Some(save_config_closure.as_ref().unchecked_ref()));
    save_config_closure.forget();

    let paste_form = get_element_by_id::<HtmlElement>(&document, "pasteForm")?;
    let paste_form_closure = Closure::wrap(Box::new(move |event: web_sys::Event| {
        event.prevent_default();
        console_log!("Share button clicked");
        // TODO: Implement create_paste
    }) as Box<dyn FnMut(_)>);
    paste_form.set_onsubmit(Some(paste_form_closure.as_ref().unchecked_ref()));
    paste_form_closure.forget();

    let split_button = get_element_by_id::<HtmlElement>(&document, "splitForChat")?;
    let split_closure = Closure::wrap(Box::new(move || {
        console_log!("Split button clicked");
        // TODO: Implement split_for_chat
    }) as Box<dyn FnMut()>);
    split_button.set_onclick(Some(split_closure.as_ref().unchecked_ref()));
    split_closure.forget();

    let copy_all_button = get_element_by_id::<HtmlElement>(&document, "copyAllChunks")?;
    let copy_all_closure = Closure::wrap(Box::new(move || {
        console_log!("Copy All Chunks button clicked");
        // TODO: Implement copy_all_chunks
    }) as Box<dyn FnMut()>);
    copy_all_button.set_onclick(Some(copy_all_closure.as_ref().unchecked_ref()));
    copy_all_closure.forget();

    // TODO: Implement initDB and loadPastes

    Ok(())
}

fn get_element_by_id<T: wasm_bindgen::JsCast>(document: &Document, id: &str) -> Result<T, JsValue> {
    document
        .get_element_by_id(id)
        .expect(&format!("element with id '{}' not found", id))
        .dyn_into::<T>()
        .map_err(|_| JsValue::from_str(&format!("element with id '{}' is not of the expected type", id)))
}
