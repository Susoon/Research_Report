#include "sh_handler.h"

#define DPDK_RING_SIZE (BATCH_SIZE * 8)
#define RTE_ETH_CRC_LEN 5
#define TOTAL_PKT_SIZE (PKT_SIZE + RTE_ETH_CRC_LEN)
#define ONELINE 6

#define GPU_TIME 1
#define MANI 0

unsigned char * pinned_pkt_buf;
unsigned char * tmp;
static int idx;

static uint64_t recv_total;

static uint64_t start;
static uint64_t end;

extern "C"
uint64_t monotonic_time() {
        struct timespec timespec;
        clock_gettime(CLOCK_MONOTONIC, &timespec);
        return timespec.tv_sec * ONE_SEC + timespec.tv_nsec;
}

extern "C"
void copy_to_gpu(unsigned char* buf, int nb_rx)
{
	cudaMemcpy(pinned_pkt_buf + (idx * BATCH_SIZE), buf, sizeof(unsigned char)*BATCH_SIZE, cudaMemcpyHostToDevice);

	idx++;
	if(idx == 512)
		idx = 0;

#if GPU_TIME
	end = monotonic_time();
	recv_total += nb_rx;

	if(end - start >= ONE_SEC)
	{	
		printf("recv_total = %ld\n", recv_total);
		recv_total = 0;
		start = monotonic_time();
	}
#endif
}

extern "C"
void set_gpu_mem_for_dpdk(void)
{
	size_t pkt_buffer_size = DPDK_RING_SIZE;
	idx = 0;
	ASSERTRT(cudaMalloc((void**)&pinned_pkt_buf, pkt_buffer_size));
  	ASSERTRT(cudaMemset(pinned_pkt_buf, 0, pkt_buffer_size));

	ASSERTRT(cudaMalloc((void**)&tmp, sizeof(unsigned char) * 6));
  	ASSERTRT(cudaMemset(tmp, 0, 6));

#if GPU_TIME
	start = monotonic_time();
	
	recv_total = 0;
#endif

	START_GRN
	printf("[Done]____GPU mem set for dpdk____\n");
	END
}

