use std::ffi::CString;
use core::ffi::CStr;
use core::ffi::c_char;

#[no_mangle]  // Ensures the function name isn't mangled by Rust's name mangling
pub extern "C" fn add_two_integers(a: i32, b: i32) -> i32 {
    a + b
}

#[no_mangle]  // Ensures the function name isn't mangled by Rust's name mangling
pub extern "C" fn subtract_two_integers(a: i32, b: i32) -> i32 {
    a - b
}

fn get_c_string(str: String) -> *const c_char {
    let c_string = CString::new(str).expect("CString::new failed");
    c_string.into_raw() // .as_ptr
}

#[no_mangle]  // Ensures the function name isn't mangled by Rust's name mangling
pub extern "C" fn get_ohai() -> *const c_char {
    get_c_string(String::from("ohai"))
}

#[no_mangle]  // Ensures the function name isn't mangled by Rust's name mangling
pub extern "C" fn say_hi(name: *const c_char) -> *const c_char {
    let cstr = unsafe { CStr::from_ptr(name) };
    let name = String::from_utf8_lossy(cstr.to_bytes()).to_string();
    let hi_msg = format!("Hi, {}!", name);
    return get_c_string(hi_msg);
}