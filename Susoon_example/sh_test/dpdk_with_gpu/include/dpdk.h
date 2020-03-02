#ifndef __DPDK_H_
#define __DPDK_H_

#include <stdio.h>
#include <unistd.h>
#include <sys/time.h>
#include <pthread.h>
#include <sched.h>

#include <rte_memory.h>
#include <rte_common.h>
#include <rte_eal.h>
#include <rte_lcore.h>
#include <rte_debug.h>
#include <rte_per_lcore.h>
#include <rte_mbuf.h>
#include <rte_launch.h>
#include <rte_ethdev.h>
#include <rte_ether.h>
#include "l2p.h"
#include "sh_handler.h"

#define NUM_MBUFS_DEFAULT 8192
#define MBUF_CACHE_SIZE 256
#define RX_DESC_DEFAULT 512
#define DEFAULT_PKT_BURST 64 // Increasing this number consumes memory very fast
#define LOOP_NUM 10
//#define RTE_ETH_FOREACH_DEV(p)  for(_p = 0; _p < pktgen.nb_ports; _p++)
#define 	rte_ctrlmbuf_data(m)   ((unsigned char *)((uint8_t*)(m)->buf_addr) + (m)->data_off)

l2p_t *l2p;

static struct rte_eth_conf default_port_conf = {
#if 0// RTE_VERSION <= RTE_VERSION_NUM(18, 5, 0, 0)  
	.rxmode = {                                    
		.mq_mode = ETH_MQ_RX_RSS,                    
		.max_rx_pkt_len = RTE_ETHER_MAX_LEN,             
		.split_hdr_size = 0,                         
//		.ignore_offload_bitfield = 1,                
		.offloads = (DEV_RX_OFFLOAD_QINQ_STRIP |      
				DEV_RX_OFFLOAD_CHECKSUM),             
	},                                             
	.rx_adv_conf = {                               
		.rss_conf = {                                
			.rss_key = NULL,                           
			.rss_hf = ETH_RSS_IP,                      
		},                                           
	},                                             
	.txmode = {                                    
		.mq_mode = ETH_MQ_TX_NONE,                   
	},                                             
#else                                            
rxmode : {       
		split_hdr_size : 0,
#if 0//RTE_VERSION < RTE_VERSION_NUM(18, 11, 0, 0)  
		.offloads = DEV_RX_OFFLOAD_CRC_STRIP,        
#endif                                           
	},                        
txmode : {                                    
mq_mode : ETH_MQ_TX_NONE,      
	}, 
#endif                       
};  

int launch_one_lcore(void *arg);
static __inline__ void start_lcore(l2p_t *l2p, uint16_t lid)
{
	l2p->stop[lid] = 0;
}


static __inline__ int32_t lcore_is_running(l2p_t *l2p, uint16_t lid)
{
	return l2p->stop[lid] == 0;
}

static void 
rx_loop(uint8_t lid);

typedef struct rte_eth_stats eth_stats_t;

typedef struct port_info{
	eth_stats_t prev_stats;
	eth_stats_t curr_stats;
}port_info_t;

typedef struct ck_dpdk{
	port_info_t info[RTE_MAX_LCORE];
}ck_dpdk_t;

/* Allocated the ck_dpdk structure for global use */
ck_dpdk_t ck_dpdk; 

void rte_timer_setup(void);
static void * _timer_thread(void*);

void dpdk_handler(int argc, char **argv);
int launch_one_lcore(void *arg __rte_unused);
static void rx_loop(uint8_t lid);
static void * _timer_thread(void *nothing);
void rte_timer_setup(void);

#endif

