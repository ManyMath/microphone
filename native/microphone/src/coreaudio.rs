//! Minimal CoreAudio input binding via dlopen of AudioToolbox.framework.
//!
//! Same header-free pattern as the `sound` crate's output path: declare the
//! AudioQueue symbols we use and load them at runtime. AudioToolbox ships with
//! every macOS and iOS install, so consumers need no Xcode SDK linked at build
//! time.
//!
//! AudioQueue input is callback-driven; `PcmSource` is pull-driven. We bridge
//! them with a shared buffer: the input callback appends captured S16 frames to
//! a Mutex<Vec<i16>>, and `read` drains whatever has accumulated.

use std::os::raw::{c_int, c_void};
use std::sync::{Arc, Mutex};

use libloading::Library;

use crate::PcmSource;

const K_LINEAR_PCM: u32 = u32::from_be_bytes(*b"lpcm");
const K_PCM_FLAG_IS_SIGNED_INT: u32 = 0x4;
const K_PCM_FLAG_IS_PACKED: u32 = 0x8;

#[repr(C)]
#[derive(Clone, Copy)]
struct AudioStreamBasicDescription {
    sample_rate: f64,
    format_id: u32,
    format_flags: u32,
    bytes_per_packet: u32,
    frames_per_packet: u32,
    bytes_per_frame: u32,
    channels_per_frame: u32,
    bits_per_channel: u32,
    reserved: u32,
}

#[repr(C)]
struct AudioTimeStamp {
    sample_time: f64,
    host_time: u64,
    rate_scalar: f64,
    word_clock_time: u64,
    smpte_time: [u8; 24],
    flags: u32,
    reserved: u32,
}

#[repr(C)]
struct AudioQueueBuffer {
    audio_data_bytes_capacity: u32,
    audio_data: *mut c_void,
    audio_data_byte_size: u32,
    user_data: *mut c_void,
    packet_description_capacity: u32,
    packet_descriptions: *mut c_void,
    packet_description_count: u32,
}

type AudioQueueRef = *mut c_void;
type AudioQueueBufferRef = *mut AudioQueueBuffer;

// The input callback: (user_data, queue, buffer, start_time, num_packets,
// packet_descs). We ignore timing and packet descriptions for PCM.
type InputCallback = unsafe extern "C" fn(
    *mut c_void,
    AudioQueueRef,
    AudioQueueBufferRef,
    *const AudioTimeStamp,
    u32,
    *const c_void,
);

type FnNewInput = unsafe extern "C" fn(
    *const AudioStreamBasicDescription,
    Option<InputCallback>,
    *mut c_void,
    *mut c_void,
    *mut c_void,
    u32,
    *mut AudioQueueRef,
) -> c_int;
type FnAlloc = unsafe extern "C" fn(AudioQueueRef, u32, *mut AudioQueueBufferRef) -> c_int;
type FnEnqueue =
    unsafe extern "C" fn(AudioQueueRef, AudioQueueBufferRef, u32, *const c_void) -> c_int;
type FnStart = unsafe extern "C" fn(AudioQueueRef, *mut c_void) -> c_int;
type FnStop = unsafe extern "C" fn(AudioQueueRef, u8) -> c_int;
type FnDispose = unsafe extern "C" fn(AudioQueueRef, u8) -> c_int;
type FnFreeBuffer = unsafe extern "C" fn(AudioQueueRef, AudioQueueBufferRef) -> c_int;

pub struct CoreAudio {
    _lib: Library,
    new_input: FnNewInput,
    alloc: FnAlloc,
    enqueue: FnEnqueue,
    start: FnStart,
    stop: FnStop,
    dispose: FnDispose,
    free_buffer: FnFreeBuffer,
}

unsafe impl Send for CoreAudio {}
unsafe impl Sync for CoreAudio {}

impl CoreAudio {
    pub fn load() -> Result<CoreAudio, String> {
        // macOS resolves the absolute framework path; iOS resolves the short
        // name from the dyld shared cache. Try both.
        let candidates = [
            "/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox",
            "AudioToolbox.framework/AudioToolbox",
            "AudioToolbox",
        ];
        let mut last_err = String::new();
        let lib = candidates
            .iter()
            .find_map(|p| match unsafe { Library::new(p) } {
                Ok(l) => Some(l),
                Err(e) => {
                    last_err = format!("{p}: {e}");
                    None
                }
            })
            .ok_or_else(|| format!("failed to load AudioToolbox: {last_err}"))?;
        unsafe {
            macro_rules! sym {
                ($name:literal) => {
                    *lib.get($name).map_err(|e| {
                        format!("missing symbol {}: {e}", String::from_utf8_lossy($name))
                    })?
                };
            }
            Ok(CoreAudio {
                new_input: sym!(b"AudioQueueNewInput\0"),
                alloc: sym!(b"AudioQueueAllocateBuffer\0"),
                enqueue: sym!(b"AudioQueueEnqueueBuffer\0"),
                start: sym!(b"AudioQueueStart\0"),
                stop: sym!(b"AudioQueueStop\0"),
                dispose: sym!(b"AudioQueueDispose\0"),
                free_buffer: sym!(b"AudioQueueFreeBuffer\0"),
                _lib: lib,
            })
        }
    }
}

/// Passed as the AudioQueue user_data. Holds the captured-sample sink and the
/// re-enqueue entry point the callback needs to recycle each buffer.
struct Sink {
    samples: Mutex<Vec<i16>>,
    enqueue: FnEnqueue,
}

unsafe impl Send for Sink {}
unsafe impl Sync for Sink {}

pub struct CoreAudioCapture {
    ca: *const CoreAudio,
    queue: AudioQueueRef,
    sink: Arc<Sink>,
    buffers: Vec<AudioQueueBufferRef>,
    channels: u32,
}

// The queue and buffers are only touched from the owning capture thread and the
// AudioQueue's own callback thread, which CoreAudio serializes; the shared
// sample buffer is behind a Mutex.
unsafe impl Send for CoreAudioCapture {}
unsafe impl Sync for CoreAudioCapture {}

const RING_BUFFERS: u32 = 4;
const FRAMES_PER_BUFFER: u32 = 2048;

impl CoreAudioCapture {
    pub fn open(ca: &CoreAudio, channels: u32, rate: u32) -> Result<Self, String> {
        let channels = channels.max(1);
        let bytes_per_frame = channels * 2;
        let asbd = AudioStreamBasicDescription {
            sample_rate: rate as f64,
            format_id: K_LINEAR_PCM,
            format_flags: K_PCM_FLAG_IS_SIGNED_INT | K_PCM_FLAG_IS_PACKED,
            bytes_per_packet: bytes_per_frame,
            frames_per_packet: 1,
            bytes_per_frame,
            channels_per_frame: channels,
            bits_per_channel: 16,
            reserved: 0,
        };
        let sink = Arc::new(Sink {
            samples: Mutex::new(Vec::new()),
            enqueue: ca.enqueue,
        });
        // The callback receives a raw pointer to the Sink; keep it alive via the
        // Arc stored on the capture struct.
        let user_data = Arc::as_ptr(&sink) as *mut c_void;
        unsafe {
            let mut queue: AudioQueueRef = std::ptr::null_mut();
            let rc = (ca.new_input)(
                &asbd,
                Some(input_cb),
                user_data,
                std::ptr::null_mut(),
                std::ptr::null_mut(),
                0,
                &mut queue,
            );
            if rc != 0 {
                return Err(format!("AudioQueueNewInput: {rc}"));
            }
            let buffer_bytes = FRAMES_PER_BUFFER * bytes_per_frame;
            let mut buffers = Vec::with_capacity(RING_BUFFERS as usize);
            for _ in 0..RING_BUFFERS {
                let mut buf: AudioQueueBufferRef = std::ptr::null_mut();
                let rc = (ca.alloc)(queue, buffer_bytes, &mut buf);
                if rc != 0 {
                    (ca.dispose)(queue, 1);
                    return Err(format!("AudioQueueAllocateBuffer: {rc}"));
                }
                (ca.enqueue)(queue, buf, 0, std::ptr::null());
                buffers.push(buf);
            }
            let rc = (ca.start)(queue, std::ptr::null_mut());
            if rc != 0 {
                (ca.dispose)(queue, 1);
                return Err(format!("AudioQueueStart: {rc}"));
            }
            Ok(CoreAudioCapture {
                ca: ca as *const CoreAudio,
                queue,
                sink,
                buffers,
                channels,
            })
        }
    }
}

/// Called by AudioQueue on its own thread when a buffer of input is ready.
unsafe extern "C" fn input_cb(
    user_data: *mut c_void,
    _queue: AudioQueueRef,
    buf: AudioQueueBufferRef,
    _start_time: *const AudioTimeStamp,
    _num_packets: u32,
    _packet_descs: *const c_void,
) {
    let sink = &*(user_data as *const Sink);
    let byte_size = (*buf).audio_data_byte_size as usize;
    let data = (*buf).audio_data as *const i16;
    let n = byte_size / 2;
    if n > 0 && !data.is_null() {
        let slice = std::slice::from_raw_parts(data, n);
        if let Ok(mut samples) = sink.samples.lock() {
            samples.extend_from_slice(slice);
        }
    }
    // Recycle the buffer so the device keeps capturing.
    (sink.enqueue)(_queue, buf, 0, std::ptr::null());
}

impl PcmSource for CoreAudioCapture {
    fn read(&self, max: usize) -> Result<Vec<i16>, String> {
        let mut samples = self.sink.samples.lock().map_err(|e| e.to_string())?;
        if samples.is_empty() || max == 0 {
            return Ok(Vec::new());
        }
        if samples.len() <= max {
            return Ok(std::mem::take(&mut *samples));
        }
        // Take the first `max` and keep the remainder for the next call.
        let rest = samples.split_off(max);
        let out = std::mem::replace(&mut *samples, rest);
        Ok(out)
    }

    fn channels(&self) -> u32 {
        self.channels
    }
}

impl Drop for CoreAudioCapture {
    fn drop(&mut self) {
        unsafe {
            let ca = &*self.ca;
            (ca.stop)(self.queue, 1);
            for buf in self.buffers.drain(..) {
                (ca.free_buffer)(self.queue, buf);
            }
            (ca.dispose)(self.queue, 1);
        }
        // Keep the Sink alive until after the queue is disposed so the callback
        // cannot deref a freed pointer mid-stop.
        let _ = &self.sink;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn loads_audiotoolbox() {
        CoreAudio::load().expect("AudioToolbox loads on this host");
    }
}
