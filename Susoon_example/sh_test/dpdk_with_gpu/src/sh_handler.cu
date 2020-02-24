#include "sh_handler.h"

#define RING_BATCH_NUM 512
#define DPDK_RING_SIZE (BATCH_SIZE * RING_BATCH_NUM)

#define ONELINE 6

#define DUMP 0
#define TX 0

unsigned char * rx_pkt_buf;
unsigned char * tx_pkt_buf;
static int idx;
int * rx_pkt_cnt;
int tx_idx;

int * batch_size;

extern "C"
int monotonic_time() {
        struct timespec timespec;
        clock_gettime(CLOCK_MONOTONIC, &timespec);
        return timespec.tv_sec * ONE_SEC + timespec.tv_nsec;
}

__global__ void print_gpu(unsigned char* d_pkt_buf)
{
	int i;
	START_RED
	printf("[GPU]:\n");
	for(i = 0; i < BATCH_SIZE; i++)
	{
		if(i != 0 && i % ONELINE == 0)
			printf("\n");
		if(i != 0 && i % PKT_SIZE == 0)
			printf("\n");
		printf("%02x ", d_pkt_buf[i]);
	}
	printf("\n");
	END
}

__device__ void mani_pkt_gpu(unsigned char * d_pkt_buf)
{
	int i;
	unsigned char tmp[6] = { 0 };

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
	for(i = 36; i < PKT_SIZE; i++){
		d_pkt_buf[i] = 0;
	}
}

extern "C"
void copy_to_gpu(unsigned char* buf, int size)
{
	cudaMemcpy(rx_pkt_buf + (idx * BATCH_SIZE), buf, sizeof(unsigned char)* size, cudaMemcpyHostToDevice);

	cudaMemcpy(batch_size, &size, sizeof(int), cudaMemcpyHostToDevice);

#if DUMP
	print_gpu<<<1,1>>>(rx_pkt_buf + (idx * BATCH_SIZE));
	cudaDeviceSynchronize();
#endif

	idx++;
	if(idx == RING_BATCH_NUM)
		idx = 0;
}

extern "C"
void set_gpu_mem_for_dpdk(void)
{
	idx = 0;
	tx_idx = 0;

	printf("DPDK_RING_SIZE = %d\n",DPDK_RING_SIZE);

	ASSERTRT(cudaMalloc((void**)&rx_pkt_buf, DPDK_RING_SIZE));
  	ASSERTRT(cudaMemset(rx_pkt_buf, 0, DPDK_RING_SIZE));

	ASSERTRT(cudaMalloc((void**)&tx_pkt_buf, DPDK_RING_SIZE));
  	ASSERTRT(cudaMemset(tx_pkt_buf, 0, DPDK_RING_SIZE));

	ASSERTRT(cudaMalloc((void**)&rx_pkt_cnt, sizeof(int)));
  	ASSERTRT(cudaMemset(rx_pkt_cnt, 0, sizeof(int)));

	ASSERTRT(cudaMalloc((void**)&batch_size, sizeof(int)));
  	ASSERTRT(cudaMemset(batch_size, 0, sizeof(int)));

	START_GRN
	printf("[Done]____GPU mem set for dpdk____\n");
	END
}

extern "C"
int get_rx_cnt(void)
{
	int rx_cur_pkt = 0;
	static int turn = 0;

	ASSERTRT(cudaMemcpy(&rx_cur_pkt, rx_pkt_cnt, sizeof(int), cudaMemcpyDeviceToHost));

	cudaMemset(rx_pkt_cnt, 0, sizeof(int));	
	turn++;

	return rx_cur_pkt;
}

extern "C"
void get_tx_buf(unsigned char* tx_buf)
{
	printf("get_tx_buf!!!!!\n");

	cudaMemcpy(tx_buf, tx_pkt_buf + (tx_idx * BATCH_SIZE), sizeof(unsigned char) * BATCH_SIZE, cudaMemcpyDeviceToHost);

	tx_idx++;
	if(tx_idx == RING_BATCH_NUM)
		tx_idx = 0;
}

__global__ void gpu_monitor(unsigned char * rx_pkt_buf, unsigned char * tx_pkt_buf, int * rx_pkt_cnt, int * batch_size)
{
	int mem_index = BATCH_SIZE * threadIdx.x;

	__syncthreads();
	if(rx_pkt_buf[mem_index] != 0)
	{
		__syncthreads();
		rx_pkt_buf[mem_index] = 0;

		__syncthreads();
		atomicAdd(rx_pkt_cnt, *batch_size);
#if TX
		__syncthreads();
		mani_pkt_gpu(rx_pkt_buf + mem_index);
				
		__syncthreads();
		memcpy(tx_pkt_buf + mem_index, rx_pkt_buf + mem_index, BATCH_SIZE);
#endif
	}
}

extern "C"
void gpu_monitor_loop(void)
{
	cudaStream_t stream;
	ASSERTRT(cudaStreamCreateWithFlags(&stream, cudaStreamNonBlocking));
	while(true)
	{
		gpu_monitor<<<1, RING_BATCH_NUM, 0, stream>>>(rx_pkt_buf, tx_pkt_buf, rx_pkt_cnt, batch_size);
		cudaDeviceSynchronize();
	}
}

