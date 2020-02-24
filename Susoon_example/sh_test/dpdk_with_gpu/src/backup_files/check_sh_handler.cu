#include "sh_handler.h"

#define DPDK_RING_SIZE 2 * 1024 * 1024 //2MB
#define PKT_SIZE 64
#define RTE_ETH_CRC_LEN 4
#define TOTAL_PKT_SIZE (PKT_SIZE + RTE_ETH_CRC_LEN)

#define ONELINE 6

#define RING_CHECK 0

unsigned char * pinned_pkt_buf;
unsigned char * tmp;
unsigned char * cpy_buf;
static int idx;

__global__ void Check_gpu(void)
{
	printf("\n\n\n\n\n\n");
	printf("____________GPU function is called______________\n");
	printf("\n\n\n\n\n\n");
}

void Check_buf(unsigned char * buf)
{
	printf("\n%dth pkt_dump: \n", idx);
	for(int i = 0; i < DPDK_RING_SIZE; i +=  0x1000)
	{
		if(i % (0x1000 * 32) == 0)
			printf("\n");
		if(i / 0x1000 == idx)
			START_GRN
		printf("%02x ", buf[i]);
		END
	}
	printf("\n");
}

void Dump_fct(unsigned char * buf, int size)
{
	printf("%dth pkt_dump: \n", idx);
	for(int i = 0; i < TOTAL_PKT_SIZE; i++){
		if(i != 0 && i % ONELINE == 0)
			printf("\n");
		printf("%02x ", buf[i]);
		}
	printf("\n");
}

__global__ void print_gpu(unsigned char* d_pkt_buf)
{
	int i;
	START_RED
	printf("[GPU]:\n");
	for(i = 0; i < TOTAL_PKT_SIZE; i++)
	{
		if(i != 0 && i % ONELINE == 0)
			printf("\n");
		printf("%02x ", d_pkt_buf[i]);
	}
	printf("\n");
	END
}

#if RING_CHECK

extern "C" 
void copy_to_gpu(unsigned char* buf, int size)
{
	memcpy(pinned_pkt_buf + (idx * 0x1000), buf, size);

	//Dump_fct(pinned_pkt_buf, size);
	print_gpu<<<1,1>>>(pinned_pkt_buf + (idx * 0x1000));
	
	Check_buf(pinned_pkt_buf);	
	memcpy(pinned_pkt_buf + (idx * 0x1000), zero_arr, size);

	idx++;
	if(idx == 512)
		idx = 0;
}


extern "C"
void set_gpu_mem_for_dpdk(void)
{
	size_t pkt_buffer_size = DPDK_RING_SIZE;
	idx = 0;

	pinned_pkt_buf = (unsigned char*)calloc(pkt_buffer_size, sizeof(unsigned char));
	zero_arr = (unsigned char*)calloc(pkt_buffer_size, sizeof(unsigned char));

	START_GRN
	printf("[Done]____GPU mem set for dpdk____\n");
	END
}

#else

extern "C"
void copy_to_gpu(unsigned char* buf, int size)
{
	cudaMemcpy(pinned_pkt_buf + (idx * 0x1000), buf, sizeof(unsigned char)*size, cudaMemcpyHostToDevice);
	
	print_gpu<<<1,1>>>(pinned_pkt_buf + (idx * 0x1000));
	cudaDeviceSynchronize();

	idx++;
	if(idx == 512)
		idx = 0;
	cudaMemcpy(buf, pinned_pkt_buf + (idx * 0x1000), sizeof(unsigned char) * size, cudaMemcpyDeviceToHost);
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

	cpy_buf = (unsigned char*)calloc(pkt_buffer_size, sizeof(unsigned char));

	START_GRN
	printf("[Done]____GPU mem set for dpdk____\n");
	END
}

#endif

extern "C"
void cudasynch(void)
{
	cudaDeviceSynchronize();
}

