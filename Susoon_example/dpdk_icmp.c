#include <stdio.h>
#include <unistd.h>
#include <sys/time.h>

#include <rte_memory.h>
#include <rte_launch.h>
#include <rte_eal.h>
#include <rte_lcore.h>
#include <rte_debug.h>
#include <rte_per_lcore.h>
#include <rte_mbuf.h>
#include <rte_ethdev.h>

#if 0
//I'm not sure if I need these macros.
#define NUM_MBUFS_DEFAULT 8192 //2^13
#define MBUF_CACHE_SIZE 256
#define RX_DESC_DEFAULT	512
#define TX_DESC_DEFAULT 512
#define DEFAULT_PKT_BURST 64
#define LOOP_NUM 10
#define rte_ctrlmbuf_data(m) ((unsigned char *)((uint8_t*)(m)->buf_addr) + (m)->data_off)
#endif

int initializer();
int simple_handler();
int loop();

int
initializer()
{
	
}

int
main()
{

}
