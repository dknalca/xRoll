#include "XRollRealtimeQueue.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

enum { XROLL_MAX_PACKET_BYTES = 256 };

typedef struct {
    _Atomic uint64_t sequence;
    uint64_t host_time;
    uint64_t callback_host_time;
    uint16_t length;
    uint8_t bytes[XROLL_MAX_PACKET_BYTES];
} XRollRealtimeQueueCell;

struct XRollRealtimeQueue {
    uint64_t mask;
    XRollRealtimeQueueCell *cells;
    _Atomic uint64_t enqueue_position;
    _Atomic uint64_t dequeue_position;
    _Atomic uint64_t dropped;
    _Atomic bool consumer_waiting;
};

static uint64_t next_power_of_two(uint32_t value) {
    uint64_t result = 2;
    while (result < value) { result <<= 1; }
    return result;
}

XRollRealtimeQueue *xroll_realtime_queue_create(uint32_t capacity) {
    uint64_t count = next_power_of_two(capacity);
    XRollRealtimeQueue *queue = calloc(1, sizeof(XRollRealtimeQueue));
    if (!queue) { return NULL; }
    queue->cells = calloc(count, sizeof(XRollRealtimeQueueCell));
    if (!queue->cells) { free(queue); return NULL; }
    queue->mask = count - 1;
    for (uint64_t index = 0; index < count; index++) {
        atomic_init(&queue->cells[index].sequence, index);
    }
    atomic_init(&queue->enqueue_position, 0);
    atomic_init(&queue->dequeue_position, 0);
    atomic_init(&queue->dropped, 0);
    atomic_init(&queue->consumer_waiting, false);
    return queue;
}

void xroll_realtime_queue_destroy(XRollRealtimeQueue *queue) {
    if (!queue) { return; }
    free(queue->cells);
    free(queue);
}

bool xroll_realtime_queue_push(XRollRealtimeQueue *queue, uint64_t host_time, uint64_t callback_host_time, const uint8_t *bytes, uint16_t length) {
    if (!queue || !bytes || length == 0 || length > XROLL_MAX_PACKET_BYTES) { return false; }
    XRollRealtimeQueueCell *cell;
    uint64_t position = atomic_load_explicit(&queue->enqueue_position, memory_order_relaxed);
    for (;;) {
        cell = &queue->cells[position & queue->mask];
        uint64_t sequence = atomic_load_explicit(&cell->sequence, memory_order_acquire);
        intptr_t difference = (intptr_t)(sequence - position);
        if (difference == 0) {
            if (atomic_compare_exchange_weak_explicit(&queue->enqueue_position, &position, position + 1, memory_order_relaxed, memory_order_relaxed)) { break; }
        } else if (difference < 0) {
            atomic_fetch_add_explicit(&queue->dropped, 1, memory_order_relaxed);
            return false;
        } else {
            position = atomic_load_explicit(&queue->enqueue_position, memory_order_relaxed);
        }
    }
    cell->host_time = host_time;
    cell->callback_host_time = callback_host_time;
    cell->length = length;
    memcpy(cell->bytes, bytes, length);
    atomic_store_explicit(&cell->sequence, position + 1, memory_order_release);
    return true;
}

bool xroll_realtime_queue_pop(XRollRealtimeQueue *queue, uint64_t *host_time, uint64_t *callback_host_time, uint8_t *bytes, uint16_t *length) {
    if (!queue || !host_time || !callback_host_time || !bytes || !length) { return false; }
    XRollRealtimeQueueCell *cell;
    uint64_t position = atomic_load_explicit(&queue->dequeue_position, memory_order_relaxed);
    for (;;) {
        cell = &queue->cells[position & queue->mask];
        uint64_t sequence = atomic_load_explicit(&cell->sequence, memory_order_acquire);
        intptr_t difference = (intptr_t)(sequence - (position + 1));
        if (difference == 0) {
            if (atomic_compare_exchange_weak_explicit(&queue->dequeue_position, &position, position + 1, memory_order_relaxed, memory_order_relaxed)) { break; }
        } else if (difference < 0) {
            return false;
        } else {
            position = atomic_load_explicit(&queue->dequeue_position, memory_order_relaxed);
        }
    }
    *host_time = cell->host_time;
    *callback_host_time = cell->callback_host_time;
    *length = cell->length;
    memcpy(bytes, cell->bytes, cell->length);
    atomic_store_explicit(&cell->sequence, position + queue->mask + 1, memory_order_release);
    return true;
}

uint64_t xroll_realtime_queue_dropped(const XRollRealtimeQueue *queue) {
    return queue ? atomic_load_explicit(&queue->dropped, memory_order_relaxed) : 0;
}

bool xroll_realtime_queue_mark_consumer_waiting(XRollRealtimeQueue *queue) {
    if (!queue) { return false; }
    atomic_store_explicit(&queue->consumer_waiting, true, memory_order_release);
    return true;
}

bool xroll_realtime_queue_consumer_needs_wake(XRollRealtimeQueue *queue) {
    if (!queue) { return false; }
    return atomic_exchange_explicit(&queue->consumer_waiting, false, memory_order_acq_rel);
}

void xroll_realtime_queue_clear_consumer_waiting(XRollRealtimeQueue *queue) {
    if (queue) { atomic_store_explicit(&queue->consumer_waiting, false, memory_order_release); }
}
