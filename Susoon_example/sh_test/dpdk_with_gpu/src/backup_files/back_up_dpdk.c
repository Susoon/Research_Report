#include "dpdk.h"

#define ONELINE 6
#define DUMP 0
#define BATCH_DUMP 0
#define SWAP 0
#define SEND 0
#define BATCH 1
#define RX_LOOP_CNT 1
#define PTHREAD_CNT 0
#define CPU_LOAD 1

#if CPU_LOAD 

#if PTHREAD_CNT
void *cpu_monitoring_loop(void *data)
{
	int start;
	int end;

	int rx_pkt_cnt = 1;

	start = monotonic_time();
	
	while(1)
	{
		end = monotonic_time();
		if(end - start >= ONE_SEC)
		{
			rx_pkt_cnt = get_rx_cnt();
			printf("PTHREAD : rx_pkt_cnt = %d\n", rx_pkt_cnt);
			start = end;
		}
	}
}
#endif

static void copy_to_arr(struct rte_mbuf * buf[], unsigned char * batch_buf, int size)
{
	unsigned char* tmp;
	for(int i = 0; i < size; i++)
	{
		tmp = (rte_ctrlmbuf_data(buf[i]));
		memcpy(batch_buf + (i * PKT_SIZE), tmp, PKT_SIZE);
	}
}


static void copy_to_struct(struct rte_mbuf * buf[], unsigned char * batch_buf, int size)
{
	unsigned char* tmp;
	for(int i = 0; i < size; i++)
	{
		tmp = (rte_ctrlmbuf_data(buf[i]));
		memcpy(tmp, batch_buf + (i * PKT_SIZE), PKT_SIZE);
	}
}

static void print_pkt(unsigned char * ptr)
{
	START_GRN
	printf("batch_ pkt_dump: \n");
	for(int i = 0; i < PKT_BATCH_SIZE; i++){
		if(i != 0 && i % ONELINE == 0)
			printf("\n");
		if(i != 0 && i % PKT_SIZE == 0)
			printf("\n\n");
		printf("%02x ", ptr[i]);
	}
	printf("\n\n");
	END
}

static void rx_loop(uint8_t lid)
{
	struct rte_mbuf *buf[DEFAULT_PKT_BURST];
	struct rte_mbuf *tx_buf[PKT_BATCH_SIZE];
	uint16_t nb_rx;
	uint16_t nb_tx;
	int ret;
	unsigned int i, j;
	uint64_t gpu_recv = 0;
	uint64_t cpu_recv = 0;
	uint64_t gpu_send = 0;
	uint64_t copy_cnt = 0;
	unsigned char* ptr;
	unsigned char* tx_ptr;
	unsigned char* tmp_mac;
	unsigned char* tmp_ip;
	unsigned char* tmp_port;

	unsigned char* rx_batch_buf;
	unsigned char* tx_batch_buf;
	struct rte_mbuf* tx_batch_buf_struct;
	unsigned int b_idx = 0;	

	int start;
	int end = 0;

	tmp_mac = (unsigned char*)malloc(6);
	tmp_ip = (unsigned char*)malloc(4);
	tmp_port = (unsigned char*)malloc(2);
	
	rx_batch_buf = (unsigned char*)malloc(sizeof(unsigned char) * PKT_BATCH_SIZE);
	tx_batch_buf = (unsigned char*)malloc(sizeof(unsigned char) * PKT_BATCH_SIZE);
	tx_batch_buf_struct = (struct rte_mbuf*)malloc(sizeof(struct rte_mbuf) * PKT_BATCH_SIZE);


	start_lcore(l2p, lid);
	
	start = monotonic_time();

	while(lcore_is_running(l2p, lid)){

		/* Params, 
		 * (1) port_id
		 * (2) queue_id
		 * (3) rx_pkts
		 * (4) nb_pkts
		*/
		nb_rx = rte_eth_rx_burst(0, 0, buf, DEFAULT_PKT_BURST);
		if(nb_rx > 0){
			//printf("nb_rx: %d\n", nb_rx);
		// [TODO] Need to modify here.
			ptr = (rte_ctrlmbuf_data(buf[0]));
#if BATCH
			copy_to_arr(buf, rx_batch_buf + (b_idx * PKT_SIZE), nb_rx);

			cpu_recv += nb_rx;
			b_idx += nb_rx;
			if(b_idx >= PKT_BATCH - RX_NB)
			{
#if BATCH_DUMP
				print_pkt(rx_batch_buf);
#endif
				copy_cnt += copy_to_gpu(rx_batch_buf, b_idx); 
				b_idx = 0;
				memset(rx_batch_buf, 0, PKT_BATCH_SIZE);
			}
#else
			copy_to_arr(buf, rx_batch_buf, nb_rx);

			copy_to_gpu(rx_batch_buf, nb_rx); 
			memset(rx_batch_buf, 0, PKT_BATCH_SIZE);
#endif
			end = monotonic_time();
#if RX_LOOP_CNT
			if(end - start > ONE_SEC)
			{
				gpu_recv = get_rx_cnt();
				printf("RX LOOP : gpu_recv = %ld, cpu_recv = %ld, copy_cnt = %ld\n", gpu_recv, cpu_recv, copy_cnt);
				start = end;
				gpu_recv = 0;
				cpu_recv = 0;
				copy_cnt = 0;
			}
#endif

#if DUMP
			START_GRN
			printf("pkt_dump: \n");
			for(i = 0; i < buf[0]->pkt_len + ETHER_CRC_LEN; i++){
				//printf("%02x ", (rte_ctrlmbuf_data(buf[0]))[i]);
				if(i != 0 && i % ONELINE == 0)
					printf("\n");
				printf("%02x ", ptr[i]);
			}
			printf("\n\n");
			END

#endif /* if DUMP */

#if SWAP
			// Swap mac
			for(i = 0; i < 6; i++){
				tmp_mac[i] = ptr[i];
				ptr[i] = ptr[i + 6];
				ptr[i + 6] = tmp_mac[i];
			}
			// Swap ip
			for(i = 26; i < 30; i++){
				tmp_ip[i-26] = ptr[i];
				ptr[i] = ptr[i + 4];
				ptr[i + 4] = tmp_ip[i-26];
			}
			// Swap port
			for(i = 34; i < 36; i++){
				tmp_port[i-34] = ptr[i];
				ptr[i] = ptr[i + 2];
				ptr[i + 2] = tmp_port[i-34];
			}
#endif /* if SWAP */

#if DUMP
			START_YLW
			printf("\n[After] pkt_dump: \n");
			for(i = 0; i < buf[0]->pkt_len + ETHER_CRC_LEN; i++){
				//printf("%02x ", (rte_ctrlmbuf_data(buf[0]))[i]);
				if(i != 0 && i % ONELINE == 0)
					printf("\n");
				printf("%02x ", ptr[i]);
			}
			printf("\n\n");
			END
#endif
		}

#if SEND
		nb_tx = get_tx_buf(tx_batch_buf);
		copy_to_struct(tx_batch_buf_struct, tx_batch_buf, nb_tx);
		gpu_send += nb_tx;
		ret = rte_eth_tx_burst(0, 0, buf, nb_rx);
#endif

		for(i = 0; i < nb_rx; i++)
			rte_pktmbuf_free(buf[i]);
	}
	printf("End of rx_loop!! from lid: %d\n", lid);
}


int launch_one_lcore(void *arg __rte_unused)
{
	uint8_t lid = rte_lcore_id();
	rx_loop(lid);
	return 0;
}

void dpdk_handler(int argc, char **argv)
{
	int ret;
	struct rte_mempool *mbuf_pool;
	uint32_t sid; // Socket id
	int i;

	pthread_t thread;
	int thread_id;

#if PTHREAD_CNT	
	thread_id = pthread_create(&thread, NULL, cpu_monitoring_loop, NULL); 
#endif

	if((l2p = l2p_create()) == NULL)
		printf("Unable to create l2p\n");

	/* Initialize the Environment Abstraction Layer (EAL). */
	// This function is to be executed on the MASTER lcore only.
	ret = rte_eal_init(argc, argv);
	if(ret < 0)
		rte_exit(EXIT_FAILURE, "Error with EAL initialization.\n");

	/* Check if at least one port is available. */
  if(rte_eth_dev_count_total() == 0)
	 	rte_exit(EXIT_FAILURE, "Error: No port available.\n");
	/* Configure the Ethernet device */
	/* Params,
	 * (1) port id
	 * (2) nb_rx_queue
	 * (3) nb_tx_queue
	 * (4) eth_conf (The pointer to the configuration data to be used)
	 */
	ret = rte_eth_dev_configure(0, 1, 1, &default_port_conf);

	if(ret < 0)
		rte_exit(EXIT_FAILURE, "Cannot configure device: port %d.\n", 0);

	sid = rte_lcore_to_socket_id(1); // lcore 1

	/* Create a new mempool in memory to hold the mbufs. */
	/* Params,
	 * (1) The name of the mbuf pool.
	 * (2) The number of elements in the mbuf pool.
	 * (3) Size of per-core object cache. 
	 * (4) Size of the application private are between the rte_mbuf structure and the data buffer.
	 * (5) Size of data buffer in each mbuf.
	 * (6) The socket identifier where the memory should be allocated.
	*/
	mbuf_pool = rte_pktmbuf_pool_create("MBUF_POOL", NUM_MBUFS_DEFAULT, MBUF_CACHE_SIZE, 0, RTE_MBUF_DEFAULT_BUF_SIZE, sid);
	if(mbuf_pool == NULL)
		rte_exit(EXIT_FAILURE, "Cannot create mbuf pool\n");

	/* Allocate and set up RX queues. */
	/* Params,
	 * (1) port_id
	 * (2) rx_queue_id
	 * (3) nb_rx_desc
	 * (4) socket _id
	 * (5) rx_conf (The pointer to the configuration data to be used)
	 * (6) mb_pool (The pointer to the memory pool)
	*/
	ret = rte_eth_rx_queue_setup(0, 0, RX_DESC_DEFAULT, sid, NULL, mbuf_pool);
	if(ret)
		rte_exit(EXIT_FAILURE, "RX : Cannot init port %"PRIu8 "\n", 0);

	ret = rte_eth_tx_queue_setup(0, 0, RX_DESC_DEFAULT, sid, NULL);
	if(ret)
		rte_exit(EXIT_FAILURE, "TX : Cannot init port %"PRIu8 "\n", 0);



	/* Stats bindings (if more than one queue) */
	/* Params, 
	 * (1) port_id
	 * (2) rx_queue_id
	 * (3) stat_idx
	*/
	rte_eth_dev_set_rx_queue_stats_mapping(0, 0, 1);

	/* Display the port MAC address. */
	struct ether_addr addr;
	rte_eth_macaddr_get(0, &addr);
	printf("\n[CKJUNG]  Port %u: MAC=%02" PRIx8 ":%02" PRIx8 ":%02" PRIx8":%02" PRIx8 ":%02" PRIx8 ":%02" PRIx8 ", RXdesc/queue=%d\n", 0, addr.addr_bytes[0], addr.addr_bytes[1], addr.addr_bytes[2],addr.addr_bytes[3], addr.addr_bytes[4], addr.addr_bytes[5],RX_DESC_DEFAULT);

	/* Launch core job (Receiving pkt infinitely */
	/* Params, 
	 * (1) The function to be called
	 * (2) arg (arg for the function)
	 * (3) slave_id (The identifier of the lcore on which the function should be executed)
	*/
	if(rte_eal_remote_launch(launch_one_lcore, NULL, 1) < 0)
		rte_exit(EXIT_FAILURE, "Could not launch capture process on lcore %d.\n", 0);

	/* Start the port once everything is ready. */
	ret = rte_eth_dev_start(0);
	if(ret)
		rte_exit(EXIT_FAILURE, "Cannot start port %"PRIu8 "\n", 0);

	/* Enable RX in promiscuous mode for the Ethernet device. */
	 //rte_eth_promiscuous_enable(0);
	 //printf("[CKJUNG] <Enable promiscuous mode> \n");

	/* Write down previous stats */
	rte_eth_stats_get(0, &(ck_dpdk.info[0].prev_stats));

	//rte_timer_setup();

	/* Wait for all of the cores to stop running and exit. */
	ret = rte_eal_wait_lcore(1);
	if(ret < 0)
		rte_exit(EXIT_FAILURE, "Core %d did not stop correctly. \n", 1);

	RTE_ETH_FOREACH_DEV(i) {
		rte_eth_dev_stop(i);
		//rte_delay_us_sleep(100 * 1000);
		rte_eth_dev_close(i);
	}
}

