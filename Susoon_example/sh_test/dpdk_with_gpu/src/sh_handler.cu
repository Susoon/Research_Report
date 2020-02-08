#include "sh_handler.h"

#define DPDK_RING_SIZE 4 * 1024 * 1024 //4MB
#define PKT_SIZE 64
#define RTE_ETH_CRC_LEN 4
#define TOTAL_PKT_SIZE (PKT_SIZE + RTE_ETH_CRC_LEN)

#define ORIGIN 0

#define ONELINE 6

__device__ unsigned char * dev_pkt_buf;
unsigned char * host_buf_ptr;

/*
__device__ uint8_t tmp_pkt[60] = {\
0x00, 0x1b, 0x21, 0xbc, 0x11, 0x52, 0xa0, 0x36, 0x9f, 0x03, 0x13, 0x86, 0x08, 0x00, 0x45, 0x10,\
0x00, 0x2e, 0x00, 0x00, 0x40, 0x00, 0x40, 0x11, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x03, 0x0a, 0x00,\
0x00, 0x04, 0x04, 0xd2, 0x04, 0xd2, 0x00, 0x1a, 0x2c, 0xd6, 0x6f, 0x98, 0x26, 0x35, 0x02, 0xc9,\
0x83, 0xd7, 0x8b, 0xc3, 0xf7, 0xb5, 0x20, 0x8d, 0x48, 0x8d, 0xc0, 0x36};
*/

/* Suhwan pinning buffer 02/06 */
extern "C"
int sh_pin_buffer(void)
{
	int ret = 0;
	int retcode;

	retcode = cudaHostAlloc((void**)&dev_pkt_buf, sizeof(unsigned char) * TOTAL_PKT_SIZE, cudaHostAllocDefault);
	//cudaHostGetDevicePointer(&host_buf_ptr, dev_pkt_buf, 0);
	if(retcode == cudaErrorMemoryAllocation)
	{
		ret = errno;
		printf("cudaHostAlloc error (errno=%d)\n", ret);
	}

    return ret;
}

__global__ void print_gpu(unsigned char* d_pkt_buf)
{
	int i;
	printf("[GPU]:\n");
	for(i = 0; i < TOTAL_PKT_SIZE; i++)
	{
		if(i != 0 && i % ONELINE == 0)
			printf("\n");
		printf("%02x ", d_pkt_buf[i]);
	}
	printf("\n");
}

#if ORIGIN

extern "C"
void copy_to_gpu(unsigned char* buf, int size)
{
	unsigned char * d_pkt_buf;
	cudaMalloc((void**)&d_pkt_buf, sizeof(unsigned char)*1500);
	printf("____1__________copy_to_gpu____\n");
	cudaMemcpy(d_pkt_buf+(512*0x1000)+(0x1000), buf, sizeof(unsigned char)*size, cudaMemcpyHostToDevice);
	print_gpu<<<1,1>>>(d_pkt_buf+(512*0x1000)+(0x1000));
	printf("____2__________copy_to_gpu____\n");
}

extern "C"
void set_gpu_mem_for_dpdk(void)
{
	size_t _pkt_buffer_size = DPDK_RING_SIZE;// 4MB, for rx,tx ring
	size_t pkt_buffer_size = (_pkt_buffer_size + GPU_PAGE_SIZE - 1) & GPU_PAGE_MASK;
	
	ASSERTRT(cudaMalloc((void**)&dev_pkt_buf, pkt_buffer_size));
	ASSERTRT(cudaMemset(dev_pkt_buf, 0, pkt_buffer_size));

	START_GRN
	printf("[Done]____GPU mem set for dpdk__\n");
	END
}

#else

extern "C"
void copy_to_pinned_buffer(unsigned char * d_pkt_buf, int size)
{
	printf("___1___________copy_to_pinned_buffer___\n");
	cudaMemcpy(host_buf_ptr, d_pkt_buf, size, cudaMemcpyDeviceToDevice);		
	printf("___2___________copy_to_pinned_buffer___\n");
}

extern "C" 
void copy_to_gpu(unsigned char* buf, int size)
{
	unsigned char * d_pkt_buf;
	cudaMalloc((void**)&d_pkt_buf, sizeof(unsigned char) * TOTAL_PKT_SIZE);
	printf("____1__________copy_to_gpu____\n");
	cudaMemcpy(d_pkt_buf, buf, sizeof(unsigned char)*size, cudaMemcpyHostToDevice);
	print_gpu<<<1,1>>>(d_pkt_buf);
	copy_to_pinned_buffer(d_pkt_buf, size);
	printf("____2__________copy_to_gpu____\n");
}

extern "C" 
void set_gpu_mem_for_dpdk(void)
{
	size_t pkt_buffer_size = TOTAL_PKT_SIZE;

	cudaHostGetDevicePointer((void**)&dev_pkt_buf, (void*)host_buf_ptr, 0);

	ASSERTRT(cudaMalloc((void**)&host_buf_ptr, pkt_buffer_size));
	ASSERTRT(cudaMemset(host_buf_ptr, 0, pkt_buffer_size));

	START_GRN
	printf("[Done]____GPU mem set for dpdk__\n");
	END
}

__global__ void print_pinned_buffer(unsigned char * d_pkt_buf)
{
	int i;
	printf("[Pinned Buffer]:\n");
	for(i = 0; i < TOTAL_PKT_SIZE; i++)
	{
		if(i != 0 && i % ONELINE == 0)
			printf("\n");
		printf("%02x ", d_pkt_buf[i]);
	}
	printf("\n");
}

#endif

__device__ void read_loop(void)
{
	while(1)
	{
		START_YLW
		printf("____________Dump Packet in GPU____________\n");
		END
		print_pinned_buffer<<<1,1>>>(dev_pkt_buf);
	}

}

