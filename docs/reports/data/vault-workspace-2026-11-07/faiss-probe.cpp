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
int main(int argc,char** argv) {
  if(argc!=3) return 2;
  int count=std::stoi(argv[1]); std::string directory=argv[2];
  omp_set_num_threads(2);
  auto means=centers(); std::vector<float> training; vectors(training,count+queryCount,trainingCount,means);
  faiss::IndexFlatIP quantizer(dimension);
  faiss::IndexIVFScalarQuantizer index(&quantizer,dimension,256,faiss::ScalarQuantizer::QT_8bit,faiss::METRIC_INNER_PRODUCT);
  index.cp.niter=12; index.cp.seed=13;
  auto started=Clock::now(); index.train(trainingCount,training.data()); double trainSeconds=elapsed(started);
  training.clear(); training.shrink_to_fit();
  std::string backing=directory+"/probe.ivfdata";
  auto* disk=new faiss::OnDiskInvertedLists(index.nlist,index.code_size,backing.c_str()); disk->prefetch_nthread=1;
  index.replace_invlists(disk,true);
  std::vector<float> block; std::vector<faiss::idx_t> ids(blockSize);
  started=Clock::now();
  for(int start=0;start<count;start+=blockSize) {
    int size=std::min(blockSize,count-start); vectors(block,start,size,means);
    for(int i=0;i<size;i++) ids[i]=start+i;
    index.add_with_ids(size,block.data(),ids.data());
  }
  double buildSeconds=elapsed(started);
  std::string file=directory+"/probe.index"; faiss::write_index(&index,file.c_str());
  std::vector<float> queries; vectors(queries,count,queryCount,means);
  std::vector<float> exactDistances(queryCount*neighbors,-INFINITY);
  std::vector<faiss::idx_t> exactIDs(queryCount*neighbors,-1);
  // Exact reference, in bounded batches; no all-vector array is retained.
  started=Clock::now();
  for(int start=0;start<count;start+=blockSize) {
    int size=std::min(blockSize,count-start); vectors(block,start,size,means);
    faiss::IndexFlatIP reference(dimension); reference.add(size,block.data());
    std::vector<float> distances(queryCount*neighbors); std::vector<faiss::idx_t> found(queryCount*neighbors);
    reference.search(queryCount,queries.data(),neighbors,distances.data(),found.data());
    for(int q=0;q<queryCount;q++) for(int rank=0;rank<neighbors;rank++) {
      int offset=q*neighbors;
      for(int at=0;at<neighbors;at++) if(distances[offset+rank]>exactDistances[offset+at]) {
        for(int move=neighbors-1;move>at;move--) {exactDistances[offset+move]=exactDistances[offset+move-1];exactIDs[offset+move]=exactIDs[offset+move-1];}
        exactDistances[offset+at]=distances[offset+rank];exactIDs[offset+at]=start+found[offset+rank];break;
      }
    }
  }
  double exactSeconds=elapsed(started);
  auto loaded=std::unique_ptr<faiss::Index>(faiss::read_index(file.c_str(),faiss::IO_FLAG_READ_ONLY));
  auto* ivf=dynamic_cast<faiss::IndexIVF*>(loaded.get()); ivf->nprobe=24;
  std::vector<double> latency;
  int hits=0;
  for(int q=0;q<queryCount;q++) {
    std::vector<float> distances(neighbors); std::vector<faiss::idx_t> found(neighbors);
    started=Clock::now(); loaded->search(1,queries.data()+q*dimension,neighbors,distances.data(),found.data()); latency.push_back(elapsed(started)*1000);
    for(auto id:found) for(int j=0;j<neighbors;j++) if(exactIDs[q*neighbors+j]==id) {hits++;break;}
  }
  std::sort(latency.begin(),latency.end()); struct rusage memory;getrusage(RUSAGE_SELF,&memory);
  printf("{\"vectors\":%d,\"dimensions\":%d,\"recallAt10\":%.4f,\"p50ms\":%.3f,\"p95ms\":%.3f,\"trainSeconds\":%.3f,\"buildSeconds\":%.3f,\"exactSeconds\":%.3f,\"peakRSSBytes\":%ld}\n",count,dimension,double(hits)/(queryCount*neighbors),latency[queryCount/2],latency[queryCount*95/100],trainSeconds,buildSeconds,exactSeconds,memory.ru_maxrss);
}
