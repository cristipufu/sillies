#ifndef SILLIES_WOOF_ARCHIVE_H
#define SILLIES_WOOF_ARCHIVE_H

#include <stddef.h>
#include <stdint.h>

// Uses the macOS system zlib. The caller owns both bounded buffers.
int sillies_woof_inflate(const uint8_t *input, size_t input_size,
                       uint8_t *output, size_t output_size);
uint32_t sillies_woof_crc32(const uint8_t *input, size_t input_size);

#endif
