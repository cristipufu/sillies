#include "VectorSearch.h"
#include <faiss/IndexFlat.h>
#include <faiss/IndexScalarQuantizer.h>
#include <faiss/invlists/OnDiskInvertedLists.h>
#include <faiss/index_io.h>
#include <omp.h>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <memory>
#include <random>
#include <vector>
#include <sys/resource.h>

using Clock = std::chrono::steady_clock;
static double elapsed(Clock::time_point start) { return std::chrono::duration<double>(Clock::now()-start).count(); }
static constexpr int dimension=384, groupCount=256, trainingCount=16384, blockSize=2048, queryCount=100, neighbors=10;
static std::vector<float> centers() {
  std::mt19937 generator(42); std::normal_distribution<float> noise;
  std::vector<float> result(groupCount*dimension);
  for(auto& value: result) value=noise(generator);
  return result;
}
static void vectors(std::vector<float>& output, int start, int count, const std::vector<float>& means) {
  output.resize(count*dimension);
  for(int i=0;i<count;i++) {
    std::mt19937 generator(start+i+101); std::normal_distribution<float> noise(0,1.3f);
    double norm=0; int group=(start+i)%groupCount;
    for(int d=0;d<dimension;d++) {float value=means[group*dimension+d]+noise(generator); output[i*dimension+d]=value; norm+=value*value;}
    float scale=1.0/std::sqrt(norm);
    for(int d=0;d<dimension;d++) output[i*dimension+d]*=scale;
  }
}

int main() {
  omp_set_num_threads(2);
  auto means=centers(); std::vector<float> queries; vectors(queries,1000000,queryCount,means);
  auto loaded=std::unique_ptr<faiss::Index>(faiss::read_index("build/vault-redesign-analysis/probe.index",faiss::IO_FLAG_READ_ONLY));
  auto* ivf=dynamic_cast<faiss::IndexIVF*>(loaded.get());
  if (!ivf || loaded->ntotal!=1000000 || loaded->d!=dimension) return 2;
  char error[512] = {};
  auto* production=svi_open("build/vault-redesign-analysis/probe.index",dimension,error,sizeof(error));
  if(!production) {fprintf(stderr,"%s\n",error);return 3;}
  std::vector<std::vector<faiss::idx_t>> expected;
  for(int probe: {96,0,96,0}) {
    ivf->nprobe=probe;
    std::vector<double> latency;
    for(int q=0;q<queryCount;q++) {
      std::vector<float> distances(256);std::vector<faiss::idx_t> found(256);
      auto started=Clock::now();
      if(probe) loaded->search(1,queries.data()+q*dimension,256,distances.data(),found.data());
      else if(!svi_search(production,queries.data()+q*dimension,256,found.data(),distances.data(),error,sizeof(error))) {fprintf(stderr,"%s\n",error);return 4;}
      if(probe && expected.size()<queryCount) expected.push_back(found);
      if(!probe && found!=expected[q]) {fprintf(stderr,"Large-index candidates changed\n");return 5;}
      latency.push_back(elapsed(started)*1000);
    }
    auto ordered=latency;std::sort(ordered.begin(),ordered.end());
    printf("{\"vectors\":1000000,\"candidates\":256,\"probes\":%d,\"medianMilliseconds\":%.3f,\"p95Milliseconds\":%.3f,\"samplesMilliseconds\":[",probe,ordered[queryCount/2],ordered[94]);
    for(size_t i=0;i<latency.size();i++) printf("%s%.3f",i?",":"",latency[i]);
    printf("]}\n");fflush(stdout);
  }
  svi_close(production);
}
