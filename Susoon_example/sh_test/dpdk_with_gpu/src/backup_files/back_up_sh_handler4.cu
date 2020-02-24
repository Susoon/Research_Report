#include "sh_handler.h"

#define RING_BATCH_NUM 8
#define DPDK_RING_SIZE (BATCH_SIZE * RING_BATCH_NUM)
#define RTE_ETH_CRC_LEN 5
#define TOTAL_PKT_SIZE (PKT_SIZE + RTE_ETH_CRC_LEN)
#define ONELINE 6
#define DUMP 0

unsigned char * rx_pkt_buf;
unsigned char * tx_pkt_buf;
static int idx;
int * rx_pkt_cnt;
int tx_idx;
int * batch_size;

int leastPriority;
int greatestPriority;

static int count = 0;

__global__ void test(void)
{
	printf("Test!!!!!\n");
}

void gpu_test(void)
{
	printf("gputest!!!!!!!!!!!\n");
	cudaStream_t stream;
	cudaStreamCreateWithPriority(&stream, cudaStreamNonBlocking, greatestPriority);
	test<<<1,1,0,stream>>>();
}

void check_error(cudaError_t err)
{	
	if(err == cudaSuccess)
	{
		count++;
//		printf("%dth success!!!!\n", count);
	}
	else
	{
//		printf("%s!!!!!!\n", cudaGetErrorName(err));
	}
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
uint64_t monotonic_time() {
        struct timespec timespec;
        clock_gettime(CLOCK_MONOTONIC, &timespec);
        return timespec.tv_sec * ONE_SEC + timespec.tv_nsec;
}

extern "C"
void copy_to_gpu(unsigned char* buf, int size)
{
	//printf("rx_pkt_buf copy\n");
	check_error(cudaMemcpy(rx_pkt_buf + (idx * BATCH_SIZE), buf, sizeof(unsigned char)* PKT_SIZE * size, cudaMemcpyHostToDevice));

//	printf("size copy\n");
	check_error(cudaMemcpy(batch_size, &size, sizeof(int), cudaMemcpyHostToDevice));

	idx++;
	if(idx == RING_BATCH_NUM)
		idx = 0;

#if DUMP
	print_gpu<<<1,1>>>(rx_pkt_buf + (idx * BATCH_SIZE));
	cudaDeviceSynchronize();
#endif
}

extern "C"
void set_gpu_mem_for_dpdk(void)
{
	size_t pkt_buffer_size = DPDK_RING_SIZE;

	idx = 0;
	tx_idx = 0;

	ASSERTRT(cudaMalloc((void**)&rx_pkt_buf, pkt_buffer_size));
  	ASSERTRT(cudaMemset(rx_pkt_buf, 0, pkt_buffer_size));

	ASSERTRT(cudaMalloc((void**)&tx_pkt_buf, pkt_buffer_size));
  	ASSERTRT(cudaMemset(tx_pkt_buf, 0, pkt_buffer_size));

	ASSERTRT(cudaMalloc((void**)&rx_pkt_cnt, sizeof(int)));
  	ASSERTRT(cudaMemset(rx_pkt_cnt, 0, sizeof(int)));

	ASSERTRT(cudaMalloc((void**)&batch_size, sizeof(int)));
  	ASSERTRT(cudaMemset(batch_size, 0, sizeof(int)));

	cudaDeviceGetStreamPriorityRange(&leastPriority, &greatestPriority);

	START_GRN
	printf("[Done]____GPU mem set for dpdk____\n");
	END
}

extern "C"
int get_rx_cnt(void)
{
	int rx_cur_pkt = tx_idx;
	printf("rx_cur_pkt copy\n");
	printf("Before memcpy, rx_cur_pkt = %d\n", rx_cur_pkt);
	ASSERTRT(cudaMemcpy(&rx_cur_pkt, rx_pkt_cnt, sizeof(int), cudaMemcpyDeviceToHost));
	printf("After memcpy, rx_cur_pkt = %d\n", rx_cur_pkt);

	gpu_test();

//	printf("rx_pkt_cnt memset\n");
	check_error(cudaMemset(rx_pkt_cnt, 0, sizeof(int)));	
	tx_idx++;

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

__global__ void gpu_monitoring_loop(unsigned char * rx_pkt_buf, unsigned char * tx_pkt_buf, int * rx_pkt_cnt, int * batch_size)
{
	int mem_index = BATCH_SIZE * threadIdx.x;

	__syncthreads();
#if 1
	while(true)
	{
#if 0
		__syncthreads();
		if(rx_pkt_buf[mem_index] != 0)
		{
			__syncthreads();
			rx_pkt_buf[mem_index] = 0;

			__syncthreads();
			atomicAdd(rx_pkt_cnt, BATCH_SIZE);

			//printf("in the loop rx_pkt_cnt = %d\n", *rx_pkt_cnt);
			//mani_pkt_gpu(rx_pkt_buf + (i * PKT_SIZE));
			//memset(rx_pkt_buf + (i * PKT_SIZE), 0, PKT_SIZE); 		
					
			//memcpy(tx_pkt_buf, rx_pkt_buf, PKT_SIZE);
		}
#endif
	}
#endif
}

extern "C"
void gpu_monitor(void)
{
	cudaStream_t stream;
	ASSERTRT(cudaStreamCreateWithFlags(&stream, cudaStreamNonBlocking));
	gpu_monitoring_loop<<<1, RING_BATCH_NUM, 0, stream>>>(rx_pkt_buf, tx_pkt_buf, rx_pkt_cnt, batch_size);
}

