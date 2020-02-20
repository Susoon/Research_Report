#include "sh_handler.h"

#define RING_BATCH_SIZE 8
#define DPDK_RING_SIZE (BATCH_SIZE * RING_BATCH_SIZE)
#define RTE_ETH_CRC_LEN 5
#define TOTAL_PKT_SIZE (PKT_SIZE + RTE_ETH_CRC_LEN)
#define ONELINE 6
#define DUMP 0

unsigned char * rx_pkt_buf;
unsigned char * tx_pkt_buf;
static int idx;
static int * rx_pkt_cnt;
static int tx_idx;
static int * pkt_size;

static int * flag;

void check_error(cudaError_t err)
{	
	if(err == cudaSuccess)
		printf("Success!!!!!\n");
	else if(err == cudaErrorLaunchTimeout)
		printf("LaunchTimeout!!!!!!\n");
	else if(err == cudaErrorInvalidDevicePointer)
		printf("InvalidDevicePointer");
	else
		printf("Cannot find cause!!!!!!\n");
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
	cudaMemcpy(rx_pkt_buf + (idx * BATCH_SIZE), buf, sizeof(unsigned char)* PKT_SIZE * size, cudaMemcpyHostToDevice);

	check_error(cudaMemset(flag, 1, sizeof(int)));
	check_error(cudaMemcpy(pkt_size, &size, sizeof(int), cudaMemcpyHostToDevice));

	idx++;
	if(idx == 512)
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

	ASSERTRT(cudaMalloc((void**)&rx_pkt_cnt, sizeof(unsigned int)));
  	ASSERTRT(cudaMemset(rx_pkt_cnt, 0, sizeof(unsigned int)));

	ASSERTRT(cudaMalloc((void**)&pkt_size, sizeof(unsigned int)));
  	ASSERTRT(cudaMemset(pkt_size, 0, sizeof(unsigned int)));

	ASSERTRT(cudaMalloc((void**)&flag, sizeof(unsigned int)));
  	ASSERTRT(cudaMemset(flag, 0, sizeof(unsigned int)));

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

	return rx_cur_pkt;
}

extern "C"
void get_tx_buf(unsigned char* tx_buf)
{
	printf("get_tx_buf!!!!!\n");
	cudaMemcpy(tx_buf, tx_pkt_buf + (tx_idx * BATCH_SIZE), sizeof(unsigned char) * BATCH_SIZE, cudaMemcpyDeviceToHost);

	tx_idx++;
	if(tx_idx == RING_BATCH_SIZE)
		tx_idx = 0;
}

__global__ void gpu_monitoring_loop(unsigned char * rx_pkt_buf, unsigned char * tx_pkt_buf, int * rx_pkt_cnt, int * pkt_size, int * flag)
{
	int i = 0;
	volatile int infinity = 1;
	while(infinity)
	{
		/*
		printf("cur buf = %d\n", rx_pkt_buf[i * PKT_SIZE]);
		if(rx_pkt_buf[i * PKT_SIZE] == 0)
			continue;
		*/
		/*
		if(*flag)
			continue;
		*/

		//printf("rx_pkt_cnt = %d, pkt_size = %d\n", *rx_pkt_cnt, *pkt_size);
		atomicAdd(rx_pkt_cnt, *pkt_size);
		mani_pkt_gpu(rx_pkt_buf + (i * PKT_SIZE));
		memset(rx_pkt_buf + (i * PKT_SIZE), 0, PKT_SIZE); 		

		i++;
		if(i == DPDK_RING_SIZE / PKT_SIZE)
			i = 0;
			
		memcpy(tx_pkt_buf, rx_pkt_buf, PKT_SIZE);
		
		atomicAdd(flag, -1);

	}
}

extern "C"
void gpu_monitor(void)
{
	gpu_monitoring_loop<<<1,1>>>(rx_pkt_buf, tx_pkt_buf, rx_pkt_cnt, pkt_size, flag);
}

/*
extern "C"
void monitoring_loop(void){

#if 0
	int prev_pkt[2] = {0,}, cur_pkt[2] = {0,};
	double pkts[2];
	char units[] = {' ', 'K', 'M', 'G', 'T'};
	char pps[2][40];
	char bps[2][40];
	int buf_idx[512] = {0,};
	int p_size=0;
	int i, j;
#endif

	int buf_idx = 0;
	uint64_t last_stats_printed = monotonic_time();
	uint64_t time;
	bool copied_for_tx = false;
	
	while(true)                                           
	{
		buf_idx++;
		if(buf_idx == DPDK_RING_SIZE / PKT_SIZE)
			buf_idx = 0;

		if(rx_pkt_buf + (buf_idx * PKT_SIZE) == 0)
			continue;

		mani_pkt_gpu<<<1,1>>>(rx_pkt_buf + (buf_idx * PKT_SIZE), tmp, rx_pkt_cnt);
		time = monotonic_time();
		if(time - last_stats_printed > ONESEC){

			last_stats_printed = time;

			cudaError_t err = cudaMemcpy(&rx_cur_pkt, &rx_pkt_cnt, sizeof(int), cudaMemcpyDeviceToHost);
			cudaError_t err2 = cudaMemcpy(&tx_cur_pkt, &tx_pkt_cnt, sizeof(int), cudaMemcpyDeviceToHost);


			if(err != cudaSuccess || err2 != cudaSuccess)
			{
				printf("cudaMemcpy, pkt_cnt, error!\n");
			}
			system("clear");	
			printf("receive packet total : %d\n", rx_cur_pkt);
		
			cudaMemcpy(&tx_pkt_buf,  	

#if 0
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
#endif                                                                 
}
*/
