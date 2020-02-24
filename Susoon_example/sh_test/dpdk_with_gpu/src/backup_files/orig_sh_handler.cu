#include "sh_handler.h"

#define DPDK_RING_SIZE 2 * 1024 * 1024 //2MB
#define PKT_SIZE 64
#define RTE_ETH_CRC_LEN 4
#define TOTAL_PKT_SIZE (PKT_SIZE + RTE_ETH_CRC_LEN)

#define ONELINE 6

unsigned char * pinned_pkt_buf;
static int idx;

/*
__device__ uint8_t tmp_pkt[60] = {\
0x00, 0x1b, 0x21, 0xbc, 0x11, 0x52, 0xa0, 0x36, 0x9f, 0x03, 0x13, 0x86, 0x08, 0x00, 0x45, 0x10,\
0x00, 0x2e, 0x00, 0x00, 0x40, 0x00, 0x40, 0x11, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x03, 0x0a, 0x00,\
0x00, 0x04, 0x04, 0xd2, 0x04, 0xd2, 0x00, 0x1a, 0x2c, 0xd6, 0x6f, 0x98, 0x26, 0x35, 0x02, 0xc9,\
0x83, 0xd7, 0x8b, 0xc3, 0xf7, 0xb5, 0x20, 0x8d, 0x48, 0x8d, 0xc0, 0x36};
*/

/* Suhwan pinning buffer 02/06 */

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


int sh_pin_buffer(void)
{
	int ret = 0;
	int retcode;

	retcode = cudaHostAlloc((void**)&pinned_pkt_buf, sizeof(unsigned char) * TOTAL_PKT_SIZE, cudaHostAllocDefault);
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

void copy_to_pinned_buffer(unsigned char * d_pkt_buf, int size)
{
	printf("___1___________copy_to_pinned_buffer___\n");
	cudaMemcpy(pinned_pkt_buf, d_pkt_buf, size, cudaMemcpyDeviceToDevice);		
	printf("___2___________copy_to_pinned_buffer___\n");
}

#if 0
extern "C" 
void copy_to_gpu(unsigned char* buf, int size)
{
	unsigned char * d_pkt_buf;
	cudaMalloc((void**)&d_pkt_buf, sizeof(unsigned char) * size);
	//printf("____1__________copy_to_gpu____\n");
	cudaMemcpy(d_pkt_buf, buf, sizeof(unsigned char)*size, cudaMemcpyHostToDevice);
	print_gpu<<<1,1>>>(d_pkt_buf);
	//printf("____2__________copy_to_gpu____\n");
	cudaFree(d_pkt_buf);
}
#endif

extern "C" 
void copy_to_gpu(unsigned char* buf, int size)
{
	//printf("____1__________copy_to_gpu____\n");
	cudaMemcpy(pinned_pkt_buf + (idx * 0x1000), buf, sizeof(unsigned char)*size, cudaMemcpyHostToDevice);
	//Dump_fct(buf, size);	
	print_gpu<<<1,1>>>(pinned_pkt_buf + (idx * 0x1000));
	idx++;
	if(idx == 512)
		idx = 0;
	//printf("____2__________copy_to_gpu____\n");
}

extern "C"
void set_gpu_mem_for_dpdk(void)
{
	size_t pkt_buffer_size = DPDK_RING_SIZE;
	idx = 0;
	ASSERTRT(cudaMalloc((void**)&pinned_pkt_buf, pkt_buffer_size));
  	ASSERTRT(cudaMemset(pinned_pkt_buf, 0, pkt_buffer_size));

	//pinned_pkt_buf = d_pkt_buf;
	//printf("pinned_pkt_buf = %p\n", pinned_pkt_buf);
	START_GRN
	printf("[Done]____GPU mem set for dpdk____\n");
	END
}

__device__ void print_pinned_buffer(unsigned char* d_pkt_buf)
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

__global__ void read_loop(unsigned char* d_pkt_buf)
{
	while(1)
	{
		print_pinned_buffer(d_pkt_buf);
	}

}

extern "C"
void read_handler(void)
{

  //set_gpu_mem_for_dpdk();
  sh_pin_buffer();
  read_loop<<<1,1>>>(pinned_pkt_buf);
}
