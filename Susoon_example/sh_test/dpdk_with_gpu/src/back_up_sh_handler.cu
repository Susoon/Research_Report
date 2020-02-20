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

uint64_t start;
uint64_t end;

static uint64_t recv_total;

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

__global__ void mani_pkt_gpu(unsigned char * d_pkt_buf, unsigned char * tmp, uint64_t * recv_total, int size)
{
	*recv_total += 1;
	printf("recv_total = %ld\n", *recv_total);
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
void copy_to_gpu(unsigned char* buf, int size, float * total_time)
{
	cudaEvent_t go, stop;
	float time = 0;
	cudaEventCreate(&go);
	cudaEventCreate(&stop);

	cudaMemcpy(pinned_pkt_buf + (idx * BATCH_SIZE), buf, sizeof(unsigned char)*size, cudaMemcpyHostToDevice);

	idx++;
	if(idx == 512)
		idx = 0;

#if MANI
	cudaEventRecord(go, 0);
	//for(int i = 0; i < BATCH_NUM; i += PKT_SIZE)
	//{
//		mani_pkt_gpu<<<1,1>>>(pinned_pkt_buf + (idx * BATCH_SIZE), tmp, &recv_total, size);
//	}
	//print_gpu<<<1,1>>>(pinned_pkt_buf + (idx * BATCH_SIZE));
	cudaDeviceSynchronize();
	
	cudaEventRecord(stop, 0);
	cudaEventSynchronize(stop);
	cudaEventElapsedTime(&time, go, stop);
	
	cudaEventDestroy(go);
	cudaEventDestroy(stop);

	*total_time += time;
	time = 0;
	
	if(*total_time >= 10)
	{
		//printf("recv_total = %ld\n", recv_total);
		//printf("total_time = %f\n", *total_time);
		*total_time = 0;
		recv_total = 0;
	}

	cudaMemcpy(buf, pinned_pkt_buf + (idx * BATCH_SIZE), sizeof(unsigned char) * size, cudaMemcpyDeviceToHost);
#endif

#if GPU_TIME
	for(int i = 0; i < BATCH_NUM; i += PKT_SIZE)
	{
		mani_pkt_gpu<<<1,1>>>(pinned_pkt_buf + (idx * BATCH_SIZE) + i, tmp, &recv_total, size);
	}
	print_gpu<<<1,1>>>(pinned_pkt_buf + (idx * BATCH_SIZE));
	cudaDeviceSynchronize();
	end = monotonic_time();

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
  	ASSERTRT(cudaMemset(pinned_pkt_buf, 1, pkt_buffer_size));

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

__global__ void read_loop(void)
{
}

extern "C"
void read_handler(void)
{
	read_loop<<<1,1>>>();
	cudaDeviceSynchronize();
}

