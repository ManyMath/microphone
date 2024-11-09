//! C ABI for the `microphone_cli` package's native capture.
//!
//! Skeleton placeholder so the crate and workspace build; the capture
//! implementation follows.

/// Returns the ABI version. Bumped when the C ABI changes.
#[no_mangle]
pub extern "C" fn microphone_abi_version() -> u32 {
    1
}
