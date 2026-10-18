//! Explicit ownership of the iOS process-wide AVAudioSession.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub(crate) enum SessionMode {
    Automatic,
    Application,
}

impl TryFrom<i32> for SessionMode {
    type Error = &'static str;
    fn try_from(value: i32) -> Result<Self, Self::Error> {
        match value {
            0 => Ok(Self::Automatic),
            1 => Ok(Self::Application),
            _ => Err("invalid audio session mode (expected 0 or 1)"),
        }
    }
}

impl SessionMode {
    #[cfg(any(target_os = "ios", test))]
    pub(crate) fn activate_if_automatic(
        self,
        activate: impl FnOnce() -> Result<(), String>,
    ) -> Result<(), String> {
        match self {
            Self::Automatic => activate(),
            Self::Application => Ok(()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn application_does_not_touch_session() {
        assert_eq!(
            SessionMode::Application.activate_if_automatic(|| panic!("session mutated")),
            Ok(())
        );
    }
    #[test]
    fn automatic_activates_and_propagates_failure() {
        let mut calls = 0;
        let result = SessionMode::Automatic.activate_if_automatic(|| {
            calls += 1;
            Err("activation denied".into())
        });
        assert_eq!(calls, 1);
        assert_eq!(result, Err("activation denied".into()));
        assert_eq!(
            SessionMode::Automatic.activate_if_automatic(|| Ok(())),
            Ok(())
        );
    }
    #[test]
    fn validates_abi_mode() {
        assert_eq!(SessionMode::try_from(0), Ok(SessionMode::Automatic));
        assert_eq!(SessionMode::try_from(1), Ok(SessionMode::Application));
        for mode in [-1, 2, i32::MAX] {
            assert!(SessionMode::try_from(mode).is_err());
        }
    }
    #[test]
    fn invalid_mode_fails_without_dereferencing_recorder() {
        let result = unsafe {
            crate::microphone_start_with_session_mode(
                std::ptr::null_mut(),
                44100,
                1,
                std::ptr::null(),
                -1,
            )
        };
        assert_eq!(result, 0);
        let error = unsafe { std::ffi::CStr::from_ptr(crate::microphone_last_error()) };
        assert!(error
            .to_str()
            .unwrap()
            .contains("invalid audio session mode"));
    }
}
