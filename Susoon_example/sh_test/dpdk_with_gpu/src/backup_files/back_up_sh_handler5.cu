#include "sh_handler.h"

#define BLOCK_NUM 64
#define THREAD_NUM BLOCK_NUM
#define RING_SIZE ((uint64_t)PKT_BATCH_SIZE * BLOCK_NUM)

#define ONELINE 6

#define DUMP 0
#define TX 0

unsigned char * rx_pkt_buf;
unsigned char * tx_pkt_buf;
static int idx;
int * rx_pkt_cnt;

int tx_idx;

int * pkt_batch_num;

extern "C"
int monotonic_time() {
        struct timespec timespec;
        clock_gettime(CLOCK_MONOTONIC, &timespec);
        return timespec.tv_sec * ONE_SEC + timespec.tv_nsec;
}

__global__ void gpu_monitor(unsigned char * rx_pkt_buf, int * rx_pkt_cnt, int * pkt_batch_num);

#if DUMP

__global__ void print_gpu(unsigned char* d_pkt_buf, int * pkt_num)
{
	int i;
	int total_pkt_num = *pkt_num * PKT_SIZE;
	START_RED
	printf("[GPU]: pkt_num = %d\n", *pkt_num);
	for(i = 0; i < total_pkt_num; i++)
	{
		if(i != 0 && i % ONELINE == 0)
			printf("\n");
		if(i != 0 && i % PKT_SIZE == 0)
			printf("\n");
		printf("%02x ", d_pkt_buf[i]);
	}
	printf("\n\n");
	END
}

#endif

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
int copy_to_gpu(unsigned char* buf, int pkt_num)
{

	ASSERTRT(cudaMemcpy(rx_pkt_buf + (idx * PKT_BATCH_SIZE), buf, sizeof(unsigned char) * pkt_num * PKT_SIZE, cudaMemcpyHostToDevice));

	cudaMemcpy(pkt_batch_num + idx, &pkt_num, sizeof(int), cudaMemcpyHostToDevice);
#if 0
	cudaStream_t stream;
	ASSERTRT(cudaStreamCreateWithFlags(&stream, cudaStreamNonBlocking));
	gpu_monitor<<<1, THREAD_NUM, 0, stream>>>(rx_pkt_buf, rx_pkt_cnt, pkt_batch_num);
	cudaDeviceSynchronize();
	cudaStreamDestroy(stream);
#endif

#if DUMP
	print_gpu<<<1,1>>>(rx_pkt_buf + (idx * PKT_BATCH_SIZE), pkt_batch_num + idx);
	cudaDeviceSynchronize();
#endif

	idx++;
	if(idx == BLOCK_NUM)
		idx = 0;
	
	return 1;
}

extern "C"
void set_gpu_mem_for_dpdk(void)
{
	idx = 0;
	tx_idx = 0;

	START_BLU
	printf("RING_SIZE = %d\n", RING_SIZE);
	printf("PKT_SIZE = %d, PKT_BATCH = %d + %d\n", PKT_SIZE, PKT_BATCH - RX_NB, RX_NB);
	END

	ASSERTRT(cudaMalloc((void**)&rx_pkt_buf, RING_SIZE));
  	ASSERTRT(cudaMemset(rx_pkt_buf, 0, RING_SIZE));

//	ASSERTRT(cudaMalloc((void**)&tx_pkt_buf, RING_SIZE));
// 	ASSERTRT(cudaMemset(tx_pkt_buf, 0, RING_SIZE));

	ASSERTRT(cudaMalloc((void**)&rx_pkt_cnt, sizeof(int)));
  	ASSERTRT(cudaMemset(rx_pkt_cnt, 0, sizeof(int)));

	ASSERTRT(cudaMalloc((void**)&pkt_batch_num, sizeof(int) * BLOCK_NUM));
  	ASSERTRT(cudaMemset(pkt_batch_num, 0, sizeof(int) * BLOCK_NUM));

	START_GRN
	printf("[Done]____GPU mem set for dpdk____\n");
	END
}

extern "C"
int get_rx_cnt(void)
{
	int rx_cur_pkt = 0;

	cudaMemcpy(&rx_cur_pkt, rx_pkt_cnt, sizeof(int), cudaMemcpyDeviceToHost);

	cudaMemset(rx_pkt_cnt, 0, sizeof(int));	
	printf("rx_cur_pkt = %d\n", rx_cur_pkt);

	return rx_cur_pkt;
}

extern "C"
int get_tx_buf(unsigned char* tx_buf)
{
	int tx_cur_pkt = 0;

	cudaMemcpy(tx_buf, tx_pkt_buf + (tx_idx * PKT_BATCH_SIZE), sizeof(unsigned char) * PKT_BATCH_SIZE, cudaMemcpyDeviceToHost);

//	cudaMemcpy(&tx_cur_pkt, pkt_batch_num + tx_idx, sizeof(int), cudaMemcpyDeviceToHost);

	tx_idx++;
	if(tx_idx == BLOCK_NUM)
		tx_idx = 0;

	return tx_cur_pkt;
}

__global__ void gpu_monitor(unsigned char * rx_pkt_buf, int * rx_pkt_cnt, int * pkt_batch_num)
{
	int mem_index = PKT_BATCH_SIZE * threadIdx.x;

	__syncthreads();
	if(pkt_batch_num[threadIdx.x] != 0 && rx_pkt_buf[mem_index + ((pkt_batch_num[threadIdx.x] - 1) * PKT_SIZE)] != 0)
	{
		__syncthreads();
		rx_pkt_buf[mem_index + ((pkt_batch_num[threadIdx.x] - 1) * PKT_SIZE)] = 0;

		__syncthreads();
		atomicAdd(rx_pkt_cnt, pkt_batch_num[threadIdx.x]);
		
#if TX
		__syncthreads();
		memcpy(tx_pkt_buf + mem_index, rx_pkt_buf + mem_index, PKT_BATCH_SIZE);
/*
		for(int i = 0; i < pkt_batch_num[threadIdx.x]; i++)
		{
			__syncthreads();
			mani_pkt_gpu(tx_pkt_buf + mem_index + i * PKT_SIZE);
		}
*/
#endif
		__syncthreads();
		memset(pkt_batch_num + threadIdx.x, 0, sizeof(int));
		
	}
}

#if 0
__global__ void gpu_mani_loop(unsigned char * tx_pkt_buf,int * pkt_batch_num)
{
	__syncthreads();
	if(pkt_batch_num[threadIdx.x] != 0 && rx_pkt_buf[mem_index + ((pkt_batch_num[threadIdx.x] - 1) * PKT_SIZE)] != 0)
	{
		__syncthreads();
		memcpy(tx_pkt_buf + mem_index, rx_pkt_buf + mem_index, PKT_BATCH_SIZE);

		__syncthreads();
		mani_pkt_gpu(tx_pkt_buf + mem_index + i * PKT_SIZE);
	}
}	
#endif

extern "C"
void gpu_monitor_loop(void)
{
	cudaStream_t stream;
	ASSERTRT(cudaStreamCreateWithFlags(&stream, cudaStreamNonBlocking));
	while(true)
	{
		gpu_monitor<<<1, THREAD_NUM, 0, stream>>>(rx_pkt_buf, rx_pkt_cnt, pkt_batch_num);
		cudaDeviceSynchronize();
	}
}

