#ifndef __RX_HANDLER_H_
#define __RX_HANDLER_H_

#include <stdio.h>
#include <stdlib.h>
#include <iostream>
#include <fstream>
#include <sstream>
#include <memory.h>
#include <cuda_runtime_api.h>
#include <cuda.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdarg.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <errno.h>
#include <netdb.h>
#include <malloc.h>
#include <getopt.h>
#include <arpa/inet.h>
#include <sys/ioctl.h>
#include <time.h>
#include <asm/types.h>

#include <linux/if_ether.h>
#include <linux/ip.h>
#include <linux/udp.h>
                                                                             
#include <icmp.cu.h>
#include <arp.h>
#include <linux/netdevice.h>   /* struct device, and other headers */
#include <linux/tcp.h>         /* struct tcphdr */
#include <linux/in6.h>
#include "packet_man.h"
#include "common.hpp"
#define ETH_ALEN  6 // YHOON
#define ARP_PAD_LEN 18 // YHOON
#define IP_HEADER_LEN 20

#ifndef TRUE
#define TRUE (1)
#endif

#ifndef FALSE
#define FALSE (0)
#endif

#ifndef ERROR
#define ERROR (-1)
#endif

#define NUM_TURN_rx_handler 2

enum mycopy_msg_level {
    MYCOPY_MSG_DEBUG = 1,
    MYCOPY_MSG_INFO,
    MYCOPY_MSG_WARN,
    MYCOPY_MSG_ERROR
};

static int my_msg_level = MYCOPY_MSG_ERROR;
static int my_enable_logging = 1;

static void my_msg(enum mycopy_msg_level lvl, const char* fmt, ...)
{
    if (-1 == my_enable_logging) {
        const char *env = getenv("MYCOPY_ENABLE_LOGGING");
        if (env)
            my_enable_logging = 1;
        else
            my_enable_logging = 0;

        env = getenv("MYCOPY_LOG_LEVEL");
        if (env)
            my_msg_level = atoi(env);
    }
    if (my_enable_logging) {
        if (lvl >= my_msg_level) {
            va_list ap;
            va_start(ap, fmt);
            vfprintf(stderr, fmt, ap);
        }
    }
}

#define my_dbg(FMT, ARGS...)  my_msg(MYCOPY_MSG_DEBUG, "DBG:  " FMT, ## ARGS)
#define my_dbgc(C, FMT, ARGS...)  do { static int my_dbg_cnt=(C); if (my_dbg_cnt) { my_dbg(FMT, ## ARGS); --my_dbg_cnt; }} while (0)
#define my_info(FMT, ARGS...) my_msg(MYCOPY_MSG_INFO,  "INFO: " FMT, ## ARGS)
#define my_warn(FMT, ARGS...) my_msg(MYCOPY_MSG_WARN,  "WARN: " FMT, ## ARGS)
#define my_err(FMT, ARGS...)  my_msg(MYCOPY_MSG_ERROR, "ERR:  " FMT, ## ARGS)

#define IXGBE_TDT(_i)   (0x06018 + ((_i) * 0x40))
#define IXGBE_RDT(_i)	(((_i) < 64) ? (0x01018 + ((_i) * 0x40)) : \
			 (0x0D018 + (((_i) - 64) * 0x40)))

enum arp_hrd_format
{
	arp_hrd_ethernet = 1
};

enum arp_opcode
{
	arp_op_request = 1, 
	arp_op_reply = 2, 
};

struct arphdr
{
  uint16_t ar_hrd;      /* hardware address format */
  uint16_t ar_pro;      /* protocol address format */
  uint8_t ar_hln;       /* hardware address length */
  uint8_t ar_pln;       /* protocol address length */
  uint16_t ar_op;       /* arp opcode */

  uint8_t ar_sha[ETH_ALEN]; /* sender hardware address */
  uint32_t ar_sip;      /* sender ip address */
  uint8_t ar_tha[ETH_ALEN]; /* targe hardware address */
  uint32_t ar_tip;      /* target ip address */

  uint8_t pad[ARP_PAD_LEN];
} __attribute__ ((packed));

__device__ unsigned char xlatcase[256];

__device__ uint32_t d_curr_of_processing_queue = 0;
__device__ uint32_t offset_for_rx = 512 * 0x1000;
__device__ static volatile uint8_t *tx_tail_for_queue_zero;
__device__ static volatile uint8_t *rx_tail_for_queue_zero;

#define IP_NEXT_PTR(iph) ((uint8_t *)iph + (iph->ihl << 2))

__device__ void DumpARPPacket(struct arphdr *arph);
__device__ uint8_t * EthernetOutput(uint8_t *buf, uint16_t h_proto, unsigned char* src_haddr, unsigned char* dst_haddr, uint16_t iplen);
__device__ void DumpICMPPacket(const char* type, struct icmphdr *icmph, uint32_t saddr, uint32_t daddr);
__device__ void DumpICMPPacket(struct icmphdr *icmph, uint32_t saddr, uint32_t daddr);
__device__ void DumpICMPPacket(struct icmphdr *icmph, uint8_t* saddr, uint8_t* daddr);
__device__ void DumpPacket(uint8_t *buf, int len);
__device__ static int ARPOutput(uint8_t * d_tx_pkt_buffer, int opcode, uint32_t src_ip, uint32_t dst_ip, unsigned char *dst_haddr);
__device__ static int ProcessARPRequest(struct arphdr *arph, uint8_t* d_tx_pkt_buffer);
__device__ static int ProcessARPReply(struct arphdr *arph);
__device__ int ProcessARPPacket(unsigned char* d_tx_pkt_buffer, unsigned char *pkt_data, int len);

my_t my_open();

struct my {
	  int fd;
};


__global__ void clean_buffer(unsigned char* buffer, int size);

union ixgbe_adv_tx_desc {
	struct {
		__le64 buffer_addr; /* Address of descriptor's data buf */
		__le32 cmd_type_len;
		__le32 olinfo_status;
		// CKJUNG, 
		//__le32 tx_irq_trigger;
	} read;
	struct {
		__le64 rsvd; /* Reserved */
		__le32 nxtseq_seed;
		__le32 status;
	} wb;
};

union ixgbe_adv_rx_desc {
	struct {
		__le64 pkt_addr; /* Packet buffer address */
		__le64 hdr_addr; /* Header buffer address */
		// CKJUNG,
		//__le32 rx_irq_trigger;
	} read;
	struct {
		struct {
			union {
				__le32 data;
				struct {
					__le16 pkt_info; /* RSS, Pkt type */
					__le16 hdr_info; /* Splithdr, hdrlen */
				} hs_rss;
			} lo_dword;
			union {
				__le32 rss; /* RSS Hash */
				struct {
					__le16 ip_id; /* IP id */
					__le16 csum; /* Packet Checksum */
				} csum_ip;
			} hi_dword;
		} lower;
		struct {
			__le32 status_error; /* ext status/error */
			__le16 length; /* Packet length */
			__le16 vlan; /* VLAN tag */
		} upper;
	} wb;  /* writeback */
};


#define __force
typedef unsigned int u32;


__device__ static inline __sum16 csum_fold(unsigned int csum);
__device__ static inline __sum16 ip_fast_csum(const void *iph, unsigned int ihl);
__device__ uint8_t *IPOutputStandalone(unsigned char* d_tx_pkt_buffer, uint8_t protocol,uint16_t ip_id, uint32_t saddr, uint32_t daddr, uint16_t payloadlen);
__device__ static uint16_t ICMPChecksum(uint16_t *icmph, int len);
__device__ static int ICMPOutput(unsigned char* d_tx_pkt_buffer, uint32_t saddr, uint32_t daddr,uint8_t icmp_type, uint8_t icmp_code, uint16_t icmp_id, uint16_t icmp_seq, uint8_t *icmpd, uint16_t len);
__device__ static int ProcessICMPECHORequest(unsigned char* d_tx_pkt_buffer, struct iphdr *iph, int len);
__device__ int ProcessUDPPacket(struct iphdr *iph, int len);
__device__ int ProcessICMPPacket(unsigned char* d_tx_pkt_buffer, struct iphdr *iph, int len);
__device__ inline int ProcessIPv4Packet(unsigned char* d_tx_pkt_buffer, unsigned char *pkt_data, int len, int* pkt_size);


__device__ void send(unsigned char* d_pkt_buffer, volatile uint8_t* io_addr, volatile union ixgbe_adv_tx_desc* tx_desc, int t_index);
//__global__ void rx_handler(unsigned char* d_pkt_buffer, int* pkt_cnt, int* pkt_size, volatile uint8_t* io_addr, volatile union ixgbe_adv_tx_desc* tx_desc, struct pkt_buf *p_buf);


int tx_rx_ring_setup();
void yhoon_finalizer(void* ixgbe_bar0_host_addr, void* desc_addr);
void yhoon_initializer(int fd, void *ixgbe_bar0_host_addr, void *desc_addr, void **io_addr, void **tx_desc);



#endif
