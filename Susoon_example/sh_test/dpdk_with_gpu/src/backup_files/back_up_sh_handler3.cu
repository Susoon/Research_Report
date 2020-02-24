#include "sh_handler.h"

#define RING_BATCH_SIZE 8
#define DPDK_RING_SIZE (BATCH_SIZE * RING_BATCH_SIZE)
#define RTE_ETH_CRC_LEN 5
#define TOTAL_PKT_SIZE (PKT_SIZE + RTE_ETH_CRC_LEN)
#define ONELINE 6
#define DUMP 0

unsigned char * pinned_pkt_buf;
unsigned char * tmp;
static int idx;
static unsigned int * pkt_cnt;
static unsigned int cur_pkt;

__global__ void print_gpu(unsigned char* d_pkt_buf)
{
	if(d_pkt_buf[PKT_SIZE - 1] != 0)
		return;
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

__global__ void mani_pkt_gpu(unsigned char * d_pkt_buf, unsigned char * tmp, unsigned int *pkt_cnt, int size)
{
	atomicAdd(pkt_cnt, size);
	printf("MANI!!!\n");

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
int copy_to_gpu(unsigned char* buf, int size)
{
	cudaMemcpy(pinned_pkt_buf + (idx * BATCH_SIZE), buf, sizeof(unsigned char)* PKT_SIZE * size, cudaMemcpyHostToDevice);

	idx++;
	if(idx == 512)
		idx = 0;

	mani_pkt_gpu<<<1,1>>>(pinned_pkt_buf + (idx * BATCH_SIZE), tmp, pkt_cnt, size);
#if DUMP
	print_gpu<<<1,1>>>(pinned_pkt_buf + (idx * BATCH_SIZE));
#endif
	cudaDeviceSynchronize();

	cudaMemcpy(buf, pinned_pkt_buf + (idx * BATCH_SIZE), sizeof(unsigned char) * size, cudaMemcpyDeviceToHost);
	cudaMemcpy(&cur_pkt, pkt_cnt, sizeof(unsigned int), cudaMemcpyDeviceToHost);
	cudaMemset(pkt_cnt, 0, sizeof(unsigned int));

	return cur_pkt;
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

	START_GRN
	printf("[Done]____GPU mem set for dpdk____\n");
	END
}

__global__ void monitoring_loop(unsigned char * d_pkt_buf, int ){
	START_GRN
		printf("Control is returned to CPU! :)\n");
	END
	int prev_pkt[2] = {0,}, cur_pkt[2] = {0,};
	double pkts[2];
	char units[] = {' ', 'K', 'M', 'G', 'T'};
	char pps[2][40];
	char bps[2][40];
	int buf_idx[512] = {0,};
	int p_size=0;
	int i, j;

	uint64_t last_stats_printed = monotonic_time();
	uint64_t time;
	
	while(true)                                           
	{
		time = monotonic_time();
		if(time - last_stats_printed > 1000 * 1000 * 1000){

			last_stats_printed = time;

			cudaError_t err = cudaMemcpy(&cur_pkt[0], &pkt_cnt[0], sizeof(int), cudaMemcpyDeviceToHost);
			cudaError_t err2 = cudaMemcpy(&cur_pkt[1], &pkt_cnt[1], sizeof(int), cudaMemcpyDeviceToHost);
			cudaError_t err3 = cudaMemcpy(&p_size, pkt_size, sizeof(int), cudaMemcpyDeviceToHost);
			cudaError_t err4 = cudaMemcpy(buf_idx, (p_buf->rx_buf_idx), sizeof(int)*512, cudaMemcpyDeviceToHost);


			// CKJUNG, 18.08.07 For check
			//printf("Error-code of cudaMemcpy: %d\n", err);
			//if(err != cudaSuccess || err2 != cudaSuccess || err3 != cudaSuccess || err4 != cudaSuccess || err5 != cudaSuccess)
			if(err != cudaSuccess || err2 != cudaSuccess || err3 != cudaSuccess || err4 != cudaSuccess)
			{
				printf("cudaMemcpy, pkt_cnt or buf_idx, error!\n");
			}
			system("clear");	
#if 0
			printf("[CKJUNG] buf #0\n");
			for(i = 0; i < 1024; i++){
				printf("%d ", data[i]);
			}
			printf("\n\n");
#endif
			for(i = 0; i < 2; i++){
				double tmp_pps;
				double tmp;
				//double batch;
				if (prev_pkt[i] != cur_pkt[i]){ // If we got a traffic flow
					pkts[i] = (double)(cur_pkt[i] - prev_pkt[i]);

#if 0
					if(i == 0)
						printf("RX_pkts: %d\n", (int)pkts[i]); 
					else
						printf("TX_pkts: %d\n", (int)pkts[i]); 
#endif
					tmp = tmp_pps = pkts[i];
					//batch = tmp/BATCH;
					for(j = 0; tmp >= 1000 && j < sizeof(units)/sizeof(char) -1; j++)
						tmp /= 1000;
					sprintf(pps[i],"%.3lf %c" ,tmp, units[j]);
#if TX
					p_size = PKT_SIZE;
#endif

					//tmp = pkts[i] * p_size * 8; // Bytes -> Bits
					tmp = pkts[i] * p_size * 8 + tmp_pps * 20 * 8; // Add IFG also, 20.01.15, CKJUNG
					for(j = 0; tmp >= 1000 && j < sizeof(units)/sizeof(char) -1; j++)
						tmp /= 1000;
					sprintf(bps[i],"%.3lf %c" ,tmp, units[j]);

					if(i == 0)
						printf("[RX] pps: %spps %sbps, pkt_size: %d \n", pps[i], bps[i], p_size);
					else{
						printf("[TX] pps: %spps %sbps, pkt_size: %d \n", pps[i], bps[i], p_size);
					}
				}else{
					if(i == 0)
						printf("[RX] pps: None\n");
					else
						printf("[TX] pps: None\n");
				}
			}
			for(i = 0; i<512; i++)
			{
				if(i % 32 ==0)
					printf("\n");
				if(buf_idx[i] == 1){
					START_GRN
						printf("%d ", buf_idx[i]);
					END
				}else if(buf_idx[i] == 2){
					START_RED
						printf("%d ", buf_idx[i]);
					END
				}else if(buf_idx[i] == 3){
					START_BLU
						printf("%d ", buf_idx[i]);
					END
				}else{
					printf("%d ", buf_idx[i]);
				}
			}
			printf("\n");

			prev_pkt[0] = cur_pkt[0];
			prev_pkt[1] = cur_pkt[1];
		}
		//sleep(1); 
	}                                                                  
}

