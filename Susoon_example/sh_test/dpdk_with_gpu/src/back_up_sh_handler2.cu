#include "sh_handler.h"

#define RING_BATCH_SIZE 8
#define DPDK_RING_SIZE (BATCH_SIZE * RING_BATCH_SIZE)
#define RTE_ETH_CRC_LEN 5
#define TOTAL_PKT_SIZE (PKT_SIZE + RTE_ETH_CRC_LEN)
#define ONELINE 6

#define GPU_TIME 1
#define MANI 0

unsigned char * pinned_pkt_buf;
unsigned char * tmp;
static int idx;
static unsigned int * pkt_cnt;
static unsigned int cur_pkt;

__global__ void print_gpu(unsigned char* d_pkt_buf)
{
	int i;
	START_RED
	printf("[GPU]:\n");
	for(i = 0; i < TOTAL_PKT_SIZE; i++)
	{
		if(i != 0 && i % ONELINE ==0)
			printf("\n");
		printf("%02x ", d_pkt_buf[i]);
	}
	printf("\n");
	END
}

__global__ void mani_pkt_gpu(unsigned char * d_pkt_buf, unsigned char * tmp, unsigned int *pkt_cnt, int size)
{
	atomicAdd(pkt_cnt, size);
	int i;
	// Swap mac
	for(i = 0; i < 6; i++){
		tmp[i] = d_pkt_buf[i];
		d_pkt_buf[i] = d_pkt_buf[i + 6];
		d_pkt_buf[i + 6] = tmp[i];
	}
	// Swap ip
	for(i = 26; i < 30; i++){
		tmp[i-26] = d_pkt_buf[i];
		d_pkt_buf[i] = d_pkt_buf[i + 4];
		d_pkt_buf[i + 4] = tmp[i-26];
	}
	// Swap port
	for(i = 34; i < 36; i++){
		tmp[i-34] = d_pkt_buf[i];
		d_pkt_buf[i] = d_pkt_buf[i + 2];
		d_pkt_buf[i + 2] = tmp[i-34];
	}
	//Manipulatate data
	for(i = 36; i < size; i++){
		d_pkt_buf[i] = 0;
	}
}

extern "C"
uint64_t monotonic_time() {
        struct timespec timespec;
        clock_gettime(CLOCK_MONOTONIC, &timespec);
        return timespec.tv_sec * ONE_SEC + timespec.tv_nsec;
}

extern "C"
int copy_to_gpu(unsigned char* buf, int size, float * total_time)
{
	cudaMemcpy(pinned_pkt_buf + (idx * BATCH_SIZE), buf, sizeof(unsigned char)*size, cudaMemcpyHostToDevice);

	idx++;
	if(idx == 512)
		idx = 0;

#if GPU_TIME
	
	mani_pkt_gpu<<<1,1>>>(pinned_pkt_buf + (idx * BATCH_SIZE), tmp, pkt_cnt, size);
	//print_gpu<<<1,1>>>(pinned_pkt_buf + (idx * BATCH_SIZE));
	cudaDeviceSynchronize();

	cudaMemcpy(buf, pinned_pkt_buf + (idx * BATCH_SIZE), sizeof(unsigned char) * size, cudaMemcpyDeviceToHost);
	cudaMemcpy(&cur_pkt, pkt_cnt, sizeof(unsigned int), cudaMemcpyDeviceToHost);
	cudaMemset(pkt_cnt, 0, sizeof(unsigned int));

	return cur_pkt;
#endif
}

extern "C"
void set_gpu_mem_for_dpdk(void)
{
	size_t pkt_buffer_size = DPDK_RING_SIZE;
	idx = 0;
	ASSERTRT(cudaMalloc((void**)&pinned_pkt_buf, pkt_buffer_size));
  	ASSERTRT(cudaMemset(pinned_pkt_buf, 1, pkt_buffer_size));

	ASSERTRT(cudaMalloc((void**)&tmp, sizeof(unsigned char) * 6));
  	ASSERTRT(cudaMemset(tmp, 0, 6));

	ASSERTRT(cudaMalloc((void**)&pkt_cnt, sizeof(unsigned int)));
  	ASSERTRT(cudaMemset(pkt_cnt, 0, sizeof(unsigned int)));

#if GPU_TIME
	//start = monotonic_time();
#endif

	START_GRN
	printf("[Done]____GPU mem set for dpdk____\n");
	END
}
