#include "VectorSearch.h"
#include <faiss/IndexFlat.h>
#include <faiss/IndexIDMap.h>
#include <faiss/IndexScalarQuantizer.h>
#include <faiss/impl/IDSelector.h>
#include <faiss/invlists/OnDiskInvertedLists.h>
#include <faiss/index_io.h>
#include <omp.h>
#include <sys/mman.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <memory>
#include <stdexcept>

namespace {
constexpr int maximum_dimensions = 4096;
constexpr size_t maximum_batch = 32768;
constexpr size_t maximum_neighbors = 256;
constexpr int worker_threads = 2;
constexpr int training_iterations = 12;
constexpr int training_seed = 13;
constexpr size_t maximum_partition_probes = 96;

void report(char* buffer, size_t capacity, const char* message) {
    if (buffer && capacity) std::snprintf(buffer, capacity, "%s", message);
}
template <typename Action>
int checked(char* error, size_t capacity, Action action) {
    try {
        omp_set_num_threads(worker_threads);
        action();
        return 1;
    } catch (const std::exception& failure) { report(error, capacity, failure.what()); }
    catch (...) { report(error, capacity, "Vector index operation failed."); }
    return 0;
}
void validate_dimensions(int dimensions) {
    if (dimensions < 1 || dimensions > maximum_dimensions)
        throw std::invalid_argument("Invalid vector dimension.");
}
void validate_vectors(const float* values, size_t count, int dimensions) {
    if (!values || count == 0 || count > maximum_batch)
        throw std::invalid_argument("Invalid vector batch.");
    for (size_t i = 0; i < count * static_cast<size_t>(dimensions); ++i)
        if (!std::isfinite(values[i])) throw std::invalid_argument("Non-finite vector.");
}
}

struct SilliesVectorIndex { std::unique_ptr<faiss::Index> index; };

SilliesVectorIndex* svi_create(int dimensions, int partitions, const float* training,
                             size_t count, const char* backing_path, char* error, size_t capacity) {
    std::unique_ptr<SilliesVectorIndex> result;
    checked(error, capacity, [&] {
        validate_dimensions(dimensions);
        result = std::make_unique<SilliesVectorIndex>();
        if (partitions == 0) {
            auto index = std::make_unique<faiss::IndexIDMap2>(new faiss::IndexFlatIP(dimensions));
            index->own_fields = true;
            result->index = std::move(index);
            return;
        }
        if (partitions < 1 || partitions > 256 || !backing_path || count < size_t(partitions) * 39)
            throw std::invalid_argument("Insufficient index training data.");
        validate_vectors(training, count, dimensions);
        auto quantizer = std::make_unique<faiss::IndexFlatIP>(dimensions);
        auto index = std::make_unique<faiss::IndexIVFScalarQuantizer>(
            quantizer.get(), dimensions, partitions, faiss::ScalarQuantizer::QT_8bit,
            faiss::METRIC_INNER_PRODUCT);
        index->own_fields = true;
        quantizer.release();
        index->cp.niter = training_iterations;
        index->cp.seed = training_seed;
        index->train(static_cast<faiss::idx_t>(count), training);
        auto lists = std::make_unique<faiss::OnDiskInvertedLists>(index->nlist, index->code_size, backing_path);
        lists->prefetch_nthread = 1;
        index->replace_invlists(lists.release(), true);
        index->nprobe = std::min(maximum_partition_probes, index->nlist);
        result->index = std::move(index);
    });
    return result && result->index ? result.release() : nullptr;
}

SilliesVectorIndex* svi_open(const char* path, int dimensions, char* error, size_t capacity) {
    std::unique_ptr<SilliesVectorIndex> result;
    checked(error, capacity, [&] {
        validate_dimensions(dimensions);
        if (!path) throw std::invalid_argument("Missing index path.");
        result = std::make_unique<SilliesVectorIndex>();
        result->index.reset(faiss::read_index(path, faiss::IO_FLAG_ONDISK_SAME_DIR));
        if (result->index->d != dimensions) throw std::invalid_argument("Index dimension changed.");
        if (auto* ivf = dynamic_cast<faiss::IndexIVF*>(result->index.get())) {
            ivf->nprobe = std::min(maximum_partition_probes, ivf->nlist);
            if (auto* disk = dynamic_cast<faiss::OnDiskInvertedLists*>(ivf->invlists)) disk->prefetch_nthread = 1;
        }
    });
    return result && result->index && result->index->d == dimensions ? result.release() : nullptr;
}
void svi_close(SilliesVectorIndex* index) { delete index; }

int svi_add(SilliesVectorIndex* handle, const int64_t* ids, const float* vectors, size_t count,
            char* error, size_t capacity) {
    return checked(error, capacity, [&] {
        if (!handle || !ids) throw std::invalid_argument("Missing index or vector identities.");
        validate_vectors(vectors, count, handle->index->d);
        for (size_t i = 0; i < count; ++i) if (ids[i] <= 0) throw std::invalid_argument("Invalid vector identity.");
        handle->index->add_with_ids(static_cast<faiss::idx_t>(count), vectors, ids);
    });
}
int svi_remove(SilliesVectorIndex* handle, const int64_t* ids, size_t count, char* error, size_t capacity) {
    return checked(error, capacity, [&] {
        if (!handle || !ids || count > maximum_batch) throw std::invalid_argument("Invalid removal batch.");
        faiss::IDSelectorBatch selector(count, ids);
        handle->index->remove_ids(selector);
    });
}
int svi_search(SilliesVectorIndex* handle, const float* query, size_t count, int64_t* ids,
               float* scores, char* error, size_t capacity) {
    return checked(error, capacity, [&] {
        if (!handle || !ids || !scores || count == 0 || count > maximum_neighbors)
            throw std::invalid_argument("Invalid search request.");
        validate_vectors(query, 1, handle->index->d);
        handle->index->search(1, query, static_cast<faiss::idx_t>(count), scores, ids);
    });
}
int svi_checkpoint(SilliesVectorIndex* handle, const char* path, char* error, size_t capacity) {
    return checked(error, capacity, [&] {
        if (!handle || !path) throw std::invalid_argument("Invalid checkpoint destination.");
        if (auto* ivf = dynamic_cast<faiss::IndexIVF*>(handle->index.get())) {
            if (auto* disk = dynamic_cast<faiss::OnDiskInvertedLists*>(ivf->invlists)) {
                if (disk->totsize && msync(disk->ptr, disk->totsize, MS_SYNC) != 0)
                    throw std::runtime_error("Could not flush vector backing storage.");
            }
        }
        faiss::write_index(handle->index.get(), path);
    });
}
