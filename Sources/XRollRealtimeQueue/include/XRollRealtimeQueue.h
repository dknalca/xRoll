#ifndef XROLL_REALTIME_QUEUE_H
#define XROLL_REALTIME_QUEUE_H

#include <stdbool.h>
#include <stdint.h>

typedef struct XRollRealtimeQueue XRollRealtimeQueue;

XRollRealtimeQueue *xroll_realtime_queue_create(uint32_t capacity);
void xroll_realtime_queue_destroy(XRollRealtimeQueue *queue);
bool xroll_realtime_queue_push(XRollRealtimeQueue *queue, uint64_t host_time, const uint8_t *bytes, uint16_t length);
bool xroll_realtime_queue_pop(XRollRealtimeQueue *queue, uint64_t *host_time, uint8_t *bytes, uint16_t *length);
uint64_t xroll_realtime_queue_dropped(const XRollRealtimeQueue *queue);
bool xroll_realtime_queue_mark_consumer_waiting(XRollRealtimeQueue *queue);
bool xroll_realtime_queue_consumer_needs_wake(XRollRealtimeQueue *queue);
void xroll_realtime_queue_clear_consumer_waiting(XRollRealtimeQueue *queue);

#endif
