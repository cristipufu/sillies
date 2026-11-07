#pragma once
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif
typedef struct SilliesVectorIndex SilliesVectorIndex;

// All operations are serialized by the owning helper. Errors never cross the C boundary.
SilliesVectorIndex* svi_create(int dimensions, int partitions, const float* training,
                             size_t training_count, const char* backing_path,
                             char* error, size_t error_capacity);
SilliesVectorIndex* svi_open(const char* index_path, int dimensions,
                           char* error, size_t error_capacity);
void svi_close(SilliesVectorIndex* index);
int svi_add(SilliesVectorIndex* index, const int64_t* ids, const float* vectors,
            size_t count, char* error, size_t error_capacity);
int svi_remove(SilliesVectorIndex* index, const int64_t* ids, size_t count,
               char* error, size_t error_capacity);
int svi_search(SilliesVectorIndex* index, const float* query, size_t count,
               int64_t* ids, float* scores, char* error, size_t error_capacity);
int svi_checkpoint(SilliesVectorIndex* index, const char* path,
                   char* error, size_t error_capacity);
#ifdef __cplusplus
}
#endif
