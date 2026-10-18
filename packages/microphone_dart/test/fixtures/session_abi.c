#include <stdint.h>
#include <stddef.h>
static int marker;
void* microphone_recorder_new(void) { return &marker; }
void microphone_recorder_free(void* r) { (void)r; }
uint64_t microphone_start(void* r, uint32_t rate, uint32_t channels, const char* device) { (void)r; (void)rate; (void)channels; (void)device; marker=10; return 0; }
#ifdef SESSION_ABI
uint64_t microphone_start_with_session_mode(void* r, uint32_t rate, uint32_t channels, const char* device, int32_t mode) { (void)r; (void)rate; (void)channels; (void)device; marker=mode==1 ? 11 : 12; return 0; }
#endif
const char* microphone_last_error(void) { return marker==10 ? "automatic entry" : marker==11 ? "application entry" : "unexpected entry"; }
intptr_t microphone_read(void* r,uint64_t id,int16_t* p,size_t n) { return 0; }
#define QUERY(name) int32_t name(void* r,uint64_t id) { return 0; }
QUERY(microphone_sample_rate)
QUERY(microphone_channels)
QUERY(microphone_pause)
QUERY(microphone_resume)
QUERY(microphone_stop)
QUERY(microphone_recording_free)
int32_t microphone_device_count(void) { return 0; }
int32_t microphone_device_id(int32_t i,char* p,size_t n) { return -1; }
int32_t microphone_device_name(int32_t i,char* p,size_t n) { return -1; }
int32_t microphone_device_is_default(int32_t i) { return 0; }
