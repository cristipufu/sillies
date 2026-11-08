#include "CWoofArchive.h"
#include <limits.h>
#include <zlib.h>

int sillies_woof_inflate(const uint8_t *input, size_t input_size,
                       uint8_t *output, size_t output_size) {
    if (input == NULL || output == NULL || input_size > UINT_MAX ||
        output_size == 0 || output_size > UINT_MAX) {
        return 0;
    }
    z_stream stream = {0};
    stream.next_in = (Bytef *)input;
    stream.avail_in = (uInt)input_size;
    stream.next_out = output;
    stream.avail_out = (uInt)output_size;
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) {
        return 0;
    }
    int status = inflate(&stream, Z_FINISH);
    int valid = status == Z_STREAM_END && stream.total_in == input_size &&
                stream.total_out == output_size;
    inflateEnd(&stream);
    return valid;
}

uint32_t sillies_woof_crc32(const uint8_t *input, size_t input_size) {
    uLong checksum = crc32(0L, Z_NULL, 0);
    while (input_size > 0) {
        uInt count = input_size > UINT_MAX ? UINT_MAX : (uInt)input_size;
        checksum = crc32(checksum, input, count);
        input += count;
        input_size -= count;
    }
    return (uint32_t)checksum;
}
