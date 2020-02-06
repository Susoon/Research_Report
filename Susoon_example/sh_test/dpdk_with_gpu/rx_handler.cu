#include "rx_handler.h"
#include "gdnio.h"
#include "packet_man.h"
#include "common.hpp"
#include "mydrv/mydrv.h"
#include "pkts.h"

#define PKT_SIZE 64

#define OUT cout
using namespace std;

unsigned char* d_pkt_buffer;
// 19.09.02. CKJUNG
unsigned char* gtx_desc;
struct pkt_buf *p_buf;
int *pkt_cnt;
int *pkt_size;          
unsigned int *ctr; // used in ipsec? 19.06.27      

static int idx;

void *ixgbe_bar0_host_addr, *io_addr, *tx_desc, *rx_desc, *tx_desc_addr,  *rx_desc_addr;
uint64_t *gddr_dma_addr;

/*
__device__ uint8_t tmp_pkt[60] = {\
0x00, 0x1b, 0x21, 0xbc, 0x11, 0x52, 0xa0, 0x36, 0x9f, 0x03, 0x13, 0x86, 0x08, 0x00, 0x45, 0x10,\
0x00, 0x2e, 0x00, 0x00, 0x40, 0x00, 0x40, 0x11, 0x00, 0x00, 0x0a, 0x00, 0x00, 0x03, 0x0a, 0x00,\
0x00, 0x04, 0x04, 0xd2, 0x04, 0xd2, 0x00, 0x1a, 0x2c, 0xd6, 0x6f, 0x98, 0x26, 0x35, 0x02, 0xc9,\
0x83, 0xd7, 0x8b, 0xc3, 0xf7, 0xb5, 0x20, 0x8d, 0x48, 0x8d, 0xc0, 0x36};
*/


// CKJUNG, 18.10.29. 
__device__ void DumpPacket_raw(unsigned char* buf, int len)
{
	int i;

	START_YLW
	printf("[START]___________________________________________\n");
	END
	printf("DumpPkt_____________________________________HEX___\n");
	for(i = 0; i < len; i++)
	{
		if(i % 16 == 0)
			printf("\n");

		printf("%02x ", buf[i]);
	}
	printf("\n____________________________________________HEX___\n\n");

#if 0
	 printf("[START]_____DumpPkt__char___\n");   
	  for(i = 0; i < len; i++)                
			 {                                       
				    if(i % 16 == 0)                       
							     printf("\n");                       
						                                         
						   printf("%02c ", buf[i]);              
							  }                                       
	printf("\n\n[END]_____DumpPkt__char___\n"); 
#endif
#if 0
	printf("DumpPkt_____________________________________DEC___\n");
	for(i = 0; i < len; i++)
	{
		if(i % 16 == 0)
			printf("\n");

		if(buf[i]>='a' && buf[i]<='z'){
			printf("%02d ", xlatcase[buf[i]]);
		}else{
			printf("%02d ", buf[i]);
		}
	}
	printf("\n____________________________________________DEC___\n");
#endif
	START_YLW
	printf("[END]___________________________________________\n\n\n");
	END

}




__device__ void DumpARPPacket(struct arphdr *arph)
//void DumpARPPacket(struct arphdr *arph)
{
	uint8_t *t;

	printf("ARP header: \n");
	printf("Hardware type: %d (len: %d), "
			"protocol type: %d (len: %d), opcode: %d\n", 
			//ntohs(arph->ar_hrd), arph->ar_hln, 
			NTOHS(arph->ar_hrd), arph->ar_hln, 
			//ntohs(arph->ar_pro), arph->ar_pln, ntohs(arph->ar_op));
			NTOHS(arph->ar_pro), arph->ar_pln, NTOHS(arph->ar_op));
	t = (uint8_t *)&arph->ar_sip;
	printf("Sender IP: %u.%u.%u.%u, "
			"haddr: %02X:%02X:%02X:%02X:%02X:%02X\n", 
			t[0], t[1], t[2], t[3], 
			arph->ar_sha[0], arph->ar_sha[1], arph->ar_sha[2], 
			arph->ar_sha[3], arph->ar_sha[4], arph->ar_sha[5]);
	t = (uint8_t *)&arph->ar_tip;
	printf("Target IP: %u.%u.%u.%u, "
			"haddr: %02X:%02X:%02X:%02X:%02X:%02X\n", 
			t[0], t[1], t[2], t[3], 
			arph->ar_tha[0], arph->ar_tha[1], arph->ar_tha[2], 
			arph->ar_tha[3], arph->ar_tha[4], arph->ar_tha[5]);
}

__device__ uint8_t * EthernetOutput(uint8_t *buf, uint16_t h_proto, unsigned char* src_haddr, unsigned char* dst_haddr, uint16_t iplen)
{
	struct ethhdr *ethh;
	int i;

	ethh = (struct ethhdr *)buf;

#if 0
	printf("dst_hwaddr: %02X:%02X:%02X:%02X:%02X:%02X\n",
				dst_haddr[0], dst_haddr[1], 
				dst_haddr[2], dst_haddr[3], 
				dst_haddr[4], dst_haddr[5]);
	printf("src_hwaddr: %02X:%02X:%02X:%02X:%02X:%02X\n",
				src_haddr[0], src_haddr[1], 
				src_haddr[2], src_haddr[3], 
				src_haddr[4], src_haddr[5]);
#endif

	for (i = 0; i < ETH_ALEN; i++) {
		ethh->h_source[i] = src_haddr[i];
		ethh->h_dest[i] = dst_haddr[i];
	}
	ethh->h_proto = HTONS(h_proto);

	return (uint8_t *)(ethh + 1);
}

__device__ void 
DumpICMPPacket(const char* type, struct icmphdr *icmph, uint32_t saddr, uint32_t daddr)
{
  uint8_t* _saddr = (uint8_t*) &saddr;
  uint8_t* _daddr = (uint8_t*) &daddr;

	printf("ICMP header: \n");
  printf("Type: %d, "
      "Code: %d, ID: %d, Sequence: %d\n", 
      icmph->icmp_type, icmph->icmp_code,
      NTOHS(ICMP_ECHO_GET_ID(icmph)), NTOHS(ICMP_ECHO_GET_SEQ(icmph)));

  printf("Sender IP: %u.%u.%u.%u\n",
      *_saddr++, *_saddr++, *_saddr++, *_saddr);
  printf("Target IP: %u.%u.%u.%u\n",
      *_daddr++, *_daddr++, *_daddr++, *_daddr);

  printf("%s--------------------------------------------\n", type);
  for(int i=0; i<64; i+=2) {
    printf("%x ", *(((uint8_t*)icmph) + i));
    printf("%x ", *(((uint8_t*)icmph) + i+1));
    if(i%20==0)
      printf("\n");
  }
  printf("\n--------------------------------------------\n");
}

__device__ void 
DumpICMPPacket(struct icmphdr *icmph, uint32_t saddr, uint32_t daddr)
{
  uint8_t* _saddr = (uint8_t*) &saddr;
  uint8_t* _daddr = (uint8_t*) &daddr;

	printf("ICMP header: \n");
  printf("Type: %d, "
      "Code: %d, ID: %d, Sequence: %d\n", 
      icmph->icmp_type, icmph->icmp_code,
      NTOHS(ICMP_ECHO_GET_ID(icmph)), NTOHS(ICMP_ECHO_GET_SEQ(icmph)));

  printf("Sender IP: %u.%u.%u.%u\n",
      *_saddr++, *_saddr++, *_saddr++, *_saddr);
  printf("Target IP: %u.%u.%u.%u\n",
      *_daddr++, *_daddr++, *_daddr++, *_daddr);

  printf("--------------------------------------------\n");
  for(int i=0; i<100; i+=2) {
    printf("%x ", *(((uint8_t*)icmph) + i));
    printf("%x ", *(((uint8_t*)icmph) + i+1));
    if(i%20==0)
      printf("\n");
  }
  printf("\n--------------------------------------------\n");
}

__device__ void 
DumpICMPPacket(struct icmphdr *icmph, uint8_t* saddr, uint8_t* daddr)
{
	printf("\nICMP header: \n");
  printf("Type: %d, "
      "Code: %d, ID: %d, Sequence: %d\n", 
      icmph->icmp_type, icmph->icmp_code,
      NTOHS(ICMP_ECHO_GET_ID(icmph)), NTOHS(ICMP_ECHO_GET_SEQ(icmph)));
	printf("ICMP_checksum: 0x%x\n", icmph->icmp_checksum);
  printf("Sender IP: %u.%u.%u.%u\n",
      *saddr++, *saddr++, *saddr++, *saddr);
  printf("Target IP: %u.%u.%u.%u\n",
      *daddr++, *daddr++, *daddr++, *daddr);
}

__device__ void DumpPacket(uint8_t *buf, int len)
//void DumpPacket(uint8_t *buf, int len)
{
  printf("\n\n\n<<<DumpPacket>>>----------------------------------------\n");
	struct ethhdr *ethh;
	struct iphdr *iph;
	struct udphdr *udph;
	//struct tcphdr *tcph;
	uint8_t *t;

	ethh = (struct ethhdr *)buf;
	//if (ntohs(ethh->h_proto) != ETH_P_IP) {
	if (NTOHS(ethh->h_proto) != ETH_P_IP) {
		printf("%02X:%02X:%02X:%02X:%02X:%02X -> %02X:%02X:%02X:%02X:%02X:%02X ",
				ethh->h_source[0],
				ethh->h_source[1],
				ethh->h_source[2],
				ethh->h_source[3],
				ethh->h_source[4],
				ethh->h_source[5],
				ethh->h_dest[0],
				ethh->h_dest[1],
				ethh->h_dest[2],
				ethh->h_dest[3],
				ethh->h_dest[4],
				ethh->h_dest[5]);

		//printf("protocol %04hx  \n", ntohs(ethh->h_proto));
		printf("protocol %04hx  \n", NTOHS(ethh->h_proto));

    //if(ntohs(ethh->h_proto) == ETH_P_ARP)
    if(NTOHS(ethh->h_proto) == ETH_P_ARP)
      DumpARPPacket((struct arphdr *) (ethh + 1));
	//	goto done;
	}

	iph = (struct iphdr *)(ethh + 1);
	udph = (struct udphdr *)((uint32_t *)iph + iph->ihl);
	//tcph = (struct tcphdr *)((uint32_t *)iph + iph->ihl);

	t = (uint8_t *)&iph->saddr;
	printf("%u.%u.%u.%u", t[0], t[1], t[2], t[3]);
	if (iph->protocol == IPPROTO_TCP || iph->protocol == IPPROTO_UDP)
		//printf("(%d)", ntohs(udph->source));
		printf("(%d)", NTOHS(udph->source));

	printf(" -> ");

	t = (uint8_t *)&iph->daddr;
	printf("%u.%u.%u.%u", t[0], t[1], t[2], t[3]);
	if (iph->protocol == IPPROTO_TCP || iph->protocol == IPPROTO_UDP)
		//printf("(%d)", ntohs(udph->dest));
		printf("(%d)", NTOHS(udph->dest));
	else if (iph->protocol == IPPROTO_ICMP){
		struct icmphdr *icmph = (struct icmphdr *) IP_NEXT_PTR(iph);
		DumpICMPPacket(icmph, (uint8_t*)&(iph->saddr), (uint8_t*)&(iph->daddr));
	}

	//printf(" IP_ID=%d", ntohs(iph->id));
	printf(" IP_ID=%d", NTOHS(iph->id));
	printf(" TTL=%d ", iph->ttl);

	switch (iph->protocol) {
	case IPPROTO_TCP:
		printf("TCP ");
		break;
	case IPPROTO_UDP:
		printf("UDP ");
		break;
	default:
		printf("protocol %d ", iph->protocol);
		goto done;
	}
done:
	printf("len=%d\n", len);
  printf("<<<DumpPacket>>>-----------------------------------END--\n");

}

__device__ static int ARPOutput(uint8_t * d_tx_pkt_buffer, int opcode, uint32_t src_ip, uint32_t dst_ip, unsigned char *dst_haddr)
{
	if (!dst_haddr)
		return -1;

  //printf("\n\n\n[%s][%d] Enters\n", __FUNCTION__, __LINE__);
  // ckjung: 00:1b:21:bc:11:52
  //uint8_t src_haddr[ETH_ALEN] = {0x00, 0x1b, 0x21, 0xbc, 0x11, 0x52};
  uint8_t src_haddr[ETH_ALEN] = {0xa0, 0x36, 0x9f, 0x03, 0x13, 0x86};
	struct arphdr *arph = 
    (struct arphdr *)(uintptr_t)EthernetOutput(d_tx_pkt_buffer, ETH_P_ARP, src_haddr, dst_haddr, sizeof(struct arphdr));

	if (!arph) {
    printf("ERROR\n");
		return -1;
	}
	/* Fill arp header */
	arph->ar_hrd = HTONS(arp_hrd_ethernet);
	arph->ar_pro = HTONS(ETH_P_IP);
	arph->ar_hln = ETH_ALEN;
	arph->ar_pln = 4;
	arph->ar_op = HTONS(opcode);

	/* Fill arp body */
#if 0 // HONESTCHOI : TODO
	arph->ar_sip = CONFIG.eths[nif].ip_addr;
#endif 
	arph->ar_sip = src_ip;
	arph->ar_tip = dst_ip;

#if 0 // HONESTCHOI : TODO
	memcpy(arph->ar_sha, CONFIG.eths[nif].haddr, arph->ar_hln);
	if (target_haddr) {
		memcpy(arph->ar_tha, target_haddr, arph->ar_hln);
	} else {
		memcpy(arph->ar_tha, dst_haddr, arph->ar_hln);
	}
#endif
  for(int i=0; i<arph->ar_hln; i++) {
    arph->ar_sha[i] = src_haddr[i];
    arph->ar_tha[i] = dst_haddr[i];
  }
	//memcpy(arph->ar_sha, src_haddr, arph->ar_hln);
  //memcpy(arph->ar_tha, dst_haddr, arph->ar_hln);
	memset(arph->pad, 0, ARP_PAD_LEN);

#if 0
	DumpARPPacket(arph);
#endif

	return 0;
}

__device__ static int ProcessARPRequest(struct arphdr *arph, uint8_t* d_tx_pkt_buffer)
{
  //printf("[%s][%d] Enters", __FUNCTION__, __LINE__);
	ARPOutput(d_tx_pkt_buffer, arp_op_reply, arph->ar_tip, arph->ar_sip, arph->ar_sha);
  return 0;
}

// TODO
__device__ static int ProcessARPReply(struct arphdr *arph)
{
  //DumpARPPacket(arph);
	//unsigned char *temp;
	return 0;
}

__device__ int ProcessARPPacket(unsigned char* d_tx_pkt_buffer, unsigned char *pkt_data, int len)
{
	struct arphdr *arph = (struct arphdr *)(pkt_data + sizeof(struct ethhdr));

  switch (NTOHS(arph->ar_op)) {
    case arp_op_request:
      //printf("[%s][%d] arp_op_request\n", __FUNCTION__, __LINE__);
      ProcessARPRequest(arph, d_tx_pkt_buffer);
      break;

    case arp_op_reply:
      //printf("[%s][%d] arp_op_reply\n", __FUNCTION__, __LINE__);
      // TODO
      ProcessARPReply(arph);
      break;

    default:
      printf("[%s][%d] ERROR. KNOWN OP CODE (%d)\n", __FUNCTION__, __LINE__, NTOHS(arph->ar_op));
      //DumpPacket(pkt_data, 1500);
      break;
  }

  return 1;
}

int my_pin_buffer(my_t g, unsigned long addr, size_t size, uint64_t p2p_token, uint32_t va_space, my_mh_t *handle, uint64_t *ret_dma_addr)
{
    int ret = 0;
    int retcode;

    struct MYDRV_IOC_PIN_BUFFER_PARAMS params;
    params.addr = addr;
    params.size = size;
    params.p2p_token = p2p_token;
    params.va_space = va_space;
    params.handle = 0;
    //params.buf_name = bname;

    retcode = ioctl(g->fd, MYDRV_IOC_PIN_BUFFER, &params);
    if (0 != retcode) {
        ret = errno;
        my_err("ioctl error (errno=%d)\n", ret);
    }
    *handle = params.handle;

		// 19.07.17. CKJUNG                                        
		START_YLW                                                  
			printf("[CKJUNG] ret_dma_addr: %p\n", params.ret_dma_addr);
		END                                                        

		*ret_dma_addr = params.ret_dma_addr;

    return ret;
}

int my_pin_desc(my_t g, unsigned long addr, size_t size, uint64_t p2p_token, uint32_t va_space, my_mh_t *handle)
{
    int ret = 0;
    int retcode;

    struct MYDRV_IOC_PIN_DESC_PARAMS params;
    params.addr = addr;
    params.size = size;
    params.p2p_token = p2p_token;
    params.va_space = va_space;
    params.handle = 0;
    //params.buf_name = bname;

    retcode = ioctl(g->fd, MYDRV_IOC_PIN_DESC, &params);
    if (0 != retcode) {
        ret = errno;
        my_err("ioctl error (errno=%d)\n", ret);
    }
    *handle = params.handle;
		return ret;
}

my_t my_open()
{
    my_t m = NULL;
    //const char *myinode = "/dev/mydrv";
    const char *myinode = "/dev/ixgbe";

    m = (my_t) calloc(1, sizeof(*m));
    if (!m) {
        //my_err("error while allocating memory\n");
        return NULL;
    }

    int fd = open(myinode, O_RDWR);
    if (-1 == fd ) {
        int ret = errno;
        //my_err("error opening driver (errno=%d/%s)\n", ret, strerror(ret));
        free(m);
        return NULL;
    }

    m->fd = fd;

    return m;
}

__device__ int clean_index;
__device__ int tx_index;
__device__ int sendable;


__global__ void clean_buffer(unsigned char* buffer, int size, struct pkt_buf *p_buf) 
{
  //for(int i=0; i<size; i++) {
	// CKJUNG 18.03.01
  for(int i=0; i<size; i++) {
    buffer[i] = 0;
  }

	// 19.06.25. Mapping "p_buf" to "d_pkt_buffer"
	p_buf->tx_buf = buffer;
	p_buf->rx_buf = p_buf->tx_buf + offset_for_rx;

#if 1
	for(int i=0; i<512; i++) {
		switch(PKT_SIZE){
			case 64:
				memcpy(&p_buf->tx_buf[0x1000 * i], pkt_60B, PKT_SIZE);
				break;
			case 128:
				memcpy(&p_buf->tx_buf[0x1000 * i], pkt_124B, PKT_SIZE);
				break;
			case 256:
				memcpy(&p_buf->tx_buf[0x1000 * i], pkt_252B, PKT_SIZE);
				break;
			case 512:
				memcpy(&p_buf->tx_buf[0x1000 * i], pkt_508B, PKT_SIZE);
				break;
			case 1024:
				memcpy(&p_buf->tx_buf[0x1000 * i], pkt_1020B, PKT_SIZE);
				break;
			case 1514:
				memcpy(&p_buf->tx_buf[0x1000 * i], pkt_1510B, PKT_SIZE);
				break;
		}
	}
#endif

	// Initialize "Tx" related indices.
	clean_index = 0;
	tx_index = 0;
	sendable = 1;

	printf("%p, %p\n", p_buf->tx_buf, buffer+(512*0x1000));
	
	START_GRN
		printf("[Done]____clean_buffer__\n");
	END

}

__device__ static inline __sum16 csum_fold(unsigned int csum)
{
	u32 sum = (__force u32)csum;;

	sum += (sum << 16);
	csum = (sum < csum);
	sum >>= 16;
	sum += csum;

	return (__force __sum16)~sum;
}

__device__ static inline __sum16 ip_fast_csum(const void *iph, unsigned int ihl)
{
	const unsigned int *word = (const unsigned int*) iph;
	const unsigned int *stop = word + ihl;
	unsigned int csum = 0;
	int carry;

  uint32_t tmp = 0;
  memcpy(&tmp, (uint16_t*)&word[0], 4);
  csum = tmp;
  memcpy(&tmp, (uint16_t*)&word[1], 4);
	csum += tmp;
	carry = (csum < tmp);
	csum += carry;

  memcpy(&tmp, (uint16_t*)&word[2], 4);
	csum += tmp;
	carry = (csum < tmp);
	csum += carry;

  memcpy(&tmp, (uint16_t*)&word[3], 4);
	csum += tmp;
	carry = (csum < tmp);
	csum += carry;

	word += 4;
	do {
    memcpy(&tmp, (uint16_t*)word, 4);
		csum += tmp;
		carry = (csum < tmp);
		csum += carry;
		word++;
	} while (word != stop);

	return csum_fold(csum);
}

__device__ uint8_t *IPOutputStandalone(unsigned char* d_tx_pkt_buffer, uint8_t protocol,uint16_t ip_id, uint32_t saddr, uint32_t daddr, uint16_t payloadlen)
{
	struct iphdr *iph;
	//int nif;
	//unsigned char * haddr;
	//int rc = -1;

// TODO: when daddr is not known yet.
// This should be done with handling arp reply
#if 0
	nif = GetOutputInterface(daddr);
	if (nif < 0)
		return NULL;

	haddr = GetDestinationHWaddr(daddr);
	if (!haddr) {
#if 0
		uint8_t *da = (uint8_t *)&daddr;
		TRACE_INFO("[WARNING] The destination IP %u.%u.%u.%u "
				"is not in ARP table!\n",
				da[0], da[1], da[2], da[3]);
#endif
		RequestARP(mtcp, daddr, nif, mtcp->cur_ts);
		return NULL;
	}
#endif

  //TODO for now, statically sets mac addrs
  //uint8_t src_haddr[ETH_ALEN] = {0x00, 0x1b, 0x21, 0xbc, 0x11, 0x52};
  uint8_t src_haddr[ETH_ALEN] = {0xa0, 0x36, 0x9f, 0x03, 0x13, 0x86};
  // hw addr for yoon
  //uint8_t dst_haddr[ETH_ALEN] = {0x3c, 0xa3, 0x15, 0x04, 0x88, 0xd3};
  //uint8_t dst_haddr[ETH_ALEN] = {0x3c, 0xa3, 0x15, 0x04, 0x86, 0x76};
  uint8_t dst_haddr[ETH_ALEN] = {0x00, 0x1b, 0x21, 0xbc, 0x11, 0x52};
  //uint8_t dst_haddr[ETH_ALEN] = {0xa0, 0x36, 0x9f, 0x9c, 0x93, 0x06};
	iph = (struct iphdr *)EthernetOutput(d_tx_pkt_buffer, ETH_P_IP, src_haddr, dst_haddr, payloadlen + IP_HEADER_LEN);
	if (!iph) {
		return NULL;
	}

	iph->ihl = IP_HEADER_LEN >> 2;
	iph->version = 4;
	iph->tos = 0;
	iph->tot_len = HTONS(IP_HEADER_LEN + payloadlen);

  // to avoid memory misalignment
  // maybe, __be16 is not recognized as 2bytes by cuda
  // maybe, we need to redevine ip header structure using __align__
	*(uint16_t*)(&(iph->id)) = HTONS(ip_id);

  // XXX ??? why undefined?
#define IP_DF   0x4000
	*(uint16_t*)(&(iph->frag_off)) = (uint16_t)HTONS(IP_DF);	// no fragmentation
	*(uint8_t*)&iph->ttl = 64;
	*(uint8_t*)&iph->protocol = protocol;
	//iph->saddr = saddr;
	memcpy((uint16_t*)&iph->saddr,&saddr,4);
	//*(uint32_t*)&iph->saddr = saddr;
	//*(uint32_t*)&iph->daddr = daddr;
	memcpy((uint16_t*)&iph->daddr,&daddr,4);

	// XXX CKJUNG 18.03.15. Shoud understand why problem occurs from seq 512
  iph->check = 0;
  //uint16_t tmp = ip_fast_csum(iph, iph->ihl);
	//printf("CKJUNG___tmp:0x%x\n", ip_fast_csum(iph, iph->ihl));
	//memcpy((uint16_t*)&iph->check, &tmp, 2);
	//printf("CKJUNG___iph->check:0x%x\n", iph->check);
	iph->check = ip_fast_csum(iph, iph->ihl);
	return (uint8_t *)(iph + 1);
}

__device__ static uint16_t ICMPChecksum(uint16_t *icmph, int len)
{
#if 1
	uint16_t ret = 0;
	uint32_t sum = 0;
	uint16_t odd_byte;
	
	while (len > 1) {
		sum += *icmph++;
		len -= 2;
	}
	
	if (len == 1) {
		*(uint8_t*)(&odd_byte) = * (uint8_t*)icmph;
		sum += odd_byte;
	}
	
	sum =  (sum >> 16) + (sum & 0xffff);
	sum += (sum >> 16);
	ret =  ~sum;
	return ret; 
#endif
#if 0
	uint16_t result = 0x12a5;
	return result;
#endif
}

__device__ static int ICMPOutput(unsigned char* d_tx_pkt_buffer, uint32_t saddr, uint32_t daddr,uint8_t icmp_type, uint8_t icmp_code, uint16_t icmp_id, uint16_t icmp_seq, uint8_t *icmpd, uint16_t len)
{
	struct icmphdr *icmph;

	icmph = (struct icmphdr *)IPOutputStandalone(
      d_tx_pkt_buffer, IPPROTO_ICMP, 0, saddr, daddr, sizeof(struct icmphdr) + len);
	if (!icmph)
		return -1;
	/* Fill in the icmp header */
	icmph->icmp_type = icmp_type;
	icmph->icmp_code = icmp_code;
	icmph->icmp_checksum = 0;
	ICMP_ECHO_SET_ID(icmph, HTONS(icmp_id));
	ICMP_ECHO_SET_SEQ(icmph, HTONS(icmp_seq));
	
	/* Fill in the icmp data */
	if (len > 0)
		memcpy((void *)(icmph + 1), icmpd, len);
	
#if 1
	//DumpICMPPacket("ICMPChecksum", icmph, saddr, daddr);
	/* Calculate ICMP Checksum with header and data */
//	icmph->icmp_checksum = 0x12a5;
#if 1
	icmph->icmp_checksum = 
		ICMPChecksum((uint16_t *)icmph, sizeof(struct icmphdr) + len);
#endif
#endif
//	printf("CKJUNG___%s__icmp_checksum:0x%x\n", __FUNCTION__, icmph->icmp_checksum);	
	//DumpICMPPacket("TX", icmph, saddr, daddr);

#if 0
	if (ICMPChecksum((uint16_t *) icmph, 64) ) {
    printf("ICMPChecksum returns ERROR\n");
  }
#endif
	return 0;
}

	__device__ static int ProcessICMPECHORequest(unsigned char* d_tx_pkt_buffer, struct iphdr *iph, int len)
{
	int ret = 0;
	struct icmphdr *icmph = (struct icmphdr *) IP_NEXT_PTR(iph);
	
  // TODO
#if 1 
	if (ICMPChecksum((uint16_t *) icmph, len - (iph->ihl << 2)) ) {
		ret = ERROR;
  }
	else 
#endif
  {
    // RESOLVING MISALINGED ERROR
		// 18.06.14, CKJUNG, Mechanism????
    uint16_t* _saddr = (uint16_t*)&(iph->saddr);
    uint16_t* _daddr = (uint16_t*)&(iph->daddr);
    uint32_t saddr = 0;
    uint32_t daddr = 0;
    memcpy(&saddr, _saddr, 4);
    memcpy(&daddr, _daddr, 4);

    ICMPOutput(d_tx_pkt_buffer, daddr, saddr, ICMP_ECHOREPLY, 0, 
        NTOHS(ICMP_ECHO_GET_ID(icmph)), NTOHS(ICMP_ECHO_GET_SEQ(icmph)), 
        (uint8_t *) (icmph + 1),
        (uint16_t) (len - (iph->ihl << 2) - sizeof(struct icmphdr)) );
  }

  return ret;
}


__device__ int ProcessUDPPacket(struct iphdr *iph, int len)
{
//	atomicAdd(&u_cnt, 1);
//	u_cnt++;
//	printf("udp_cnt: %d\n", u_cnt);
	return 0;
}
// ~ckjung

__device__ int ProcessICMPPacket(unsigned char* d_tx_pkt_buffer, struct iphdr *iph, int len)
{
  //uint8_t* _saddr = (uint8_t*) &(iph->saddr);
  //uint8_t* _daddr = (uint8_t*) &(iph->daddr);

	// CKJUNG, #define IP_NEXT_PTR(iph) ((uint8_t *)iph + (iph->ihl << 2))
	// iph->ihl value is 5 in most cases. So, 5 << 2 == 5 * 4 = 20 Bytes (IP header length)
	struct icmphdr *icmph = (struct icmphdr *) IP_NEXT_PTR(iph);
	//int i;
  // TODO : should we do the following?
#if 0
	int to_me = -1;
	
	/* process the icmp messages destined to me */
	for (i = 0; i < CONFIG.eths_num; i++) {
		if (iph->daddr == CONFIG.eths[i].ip_addr) {
			to_me = TRUE;
		}
	}
	
	if (!to_me)
		return TRUE;
#endif
	
  // need to re-align for cuda
#if 0
  uint16_t* _saddr = (uint16_t*)&(iph->saddr);
  uint16_t* _daddr = (uint16_t*)&(iph->daddr);
  uint32_t saddr = 0;
  uint32_t daddr = 0;
  memcpy(&saddr, _saddr, 4);
  memcpy(&daddr, _daddr, 4);
#endif

  switch (icmph->icmp_type) {
        case ICMP_ECHO:
          ProcessICMPECHORequest(d_tx_pkt_buffer, iph, len);
          break;
        case ICMP_DEST_UNREACH:
          printf("[INFO] ICMP Destination Unreachable message received\n");
          break;
        case ICMP_TIME_EXCEEDED:
          printf("[INFO] ICMP Time Exceeded message received\n");
          break;
        default:
          printf("[INFO] Unsupported ICMP message type %x received\n", icmph->icmp_type);
          break;
  }
  return TRUE;
}


__device__ inline int ProcessIPv4Packet(unsigned char* d_tx_pkt_buffer, unsigned char *pkt_data, int len, int* pkt_size)
{
  //printf("[%s][%d]\n",__FUNCTION__, __LINE__);
	/* check and process IPv4 packets */
	struct iphdr* iph = (struct iphdr *)(pkt_data + sizeof(struct ethhdr));
	int ip_len = NTOHS(iph->tot_len);
	*pkt_size = ip_len + 18; // CKJUNG, 18.10.20. + Eth, mac headers(18 bytes)

//	printf("[GPU]_________________ ip_len: %d,  pkt_size: %d\n", ip_len, *pkt_size);

	/* drop the packet shorter than ip header */
	if (ip_len < sizeof(struct iphdr))
    // TODO: define ERROR and FALSE
		//return ERROR;
    return -1;

  // TODO: should handle checksum and promiscuous mode
#if 0
#ifndef DISABLE_HWCSUM
	if (mtcp->iom->dev_ioctl != NULL)
		rc = mtcp->iom->dev_ioctl(mtcp->ctx, ifidx, PKT_RX_IP_CSUM, iph);
	if (rc == -1 && ip_fast_csum(iph, iph->ihl))
		return ERROR;
#else
	UNUSED(rc);
	if (ip_fast_csum(iph, iph->ihl))
		return ERROR;
#endif

#if !PROMISCUOUS_MODE
	/* if not promiscuous mode, drop if the destination is not myself */
	if (iph->daddr != CONFIG.eths[ifidx].ip_addr)
		//DumpIPPacketToFile(stderr, iph, ip_len);
		return TRUE;
#endif
#endif 

	// CKJUNG 18.09.15. For checking ip-pkt length
	//printf("CKJUNG________total-length: %d\n", NTOHS(iph->tot_len));

	
#if 0
	// CKJUNG, 18.08.31 NF#1. IPv4 lookup, DIR-24-8 Algorithm -----------------------------------
	uint16_t* _daddr = (uint16_t*)&(iph->daddr);
	uint32_t daddr = 0;
	memcpy(&daddr, _daddr, 4);
#if 0 // CKJUNG, Printout DST IPs, For check
	uint8_t* t = (uint8_t *)&daddr;
	printf("CKJUNG___________________dst_ip: %u.%u.%u.%u\n", t[0], t[1], t[2], t[3]);
#endif
	//ToDo.
	//IP lookup here!
	//d_interface_lookup(&daddr, d_mtable, d_stable);
#endif
	// ~ CKJUNG----------------------------------------------------------------------------------


	// see if the version is correct
	if (iph->version != 0x4 ) {
    // TODO: define ERROR and FALSE
		//return FALSE;
		return -1;
	}
	
  switch (iph->protocol) {
#if 0
		case IPPROTO_TCP:
			return ProcessTCPPacket(mtcp, cur_ts, ifidx, iph, ip_len);
#endif
// ckjung, 180617 Adding UDP 
//		case IPPROTO_UDP:
//			return ProcessUDPPacket(iph, ip_len);
// ~ ckjung
		case IPPROTO_ICMP:
			ProcessICMPPacket(d_tx_pkt_buffer, iph, ip_len);
			return 1;
		default:
			/* currently drop other protocols */
      // TODO: define FALSE
			return 0;
      //return FALSE
	}
  //return FALSE
}

//__device__ unsigned char* d_tx_buf;
__device__ struct pkt_buf* d_p_buf;
__device__ volatile uint8_t* d_io_addr;
__device__ volatile union ixgbe_adv_tx_desc* d_tx_desc;
__device__ uint64_t* d_gddr_dma_addr;
__device__ int* d_tx_cnt;
__device__ int d_tx_flag[512];
__device__  int prev_t_id;
__device__ int batch_num; //19.08.15. For batch order
__device__ int tx_warp[16];

//#define wrap_ring(index, ring_size) (uint16_t) ((index + 1) & (ring_size - 1))
#define wrap_ring(index, add, ring_size) (uint16_t) ((index + add) & (ring_size - 1))
#define CLEAN_BATCH 32
#define SEND_BATCH 32
//__device__ void send(int pkt_size, int num, int t_id, int batch)
__device__ void send(int pkt_size, volatile uint8_t *io_addr)
{
#if 1
	int num = atomicAdd(d_tx_cnt, 1);
	int t_id = num % 512;
#else
	num = atomicAdd(d_tx_cnt, 1);
	t_id = num % 512;
	//printf("tx_tail_shared: %p, tx_tail_global: %p\n", *tx_tail_shared, *tx_tail_for_queue_zero);
#endif
  //memcpy(&d_p_buf->tx_buf[0x1000 * t_id], tmp_pkt, pkt_size);
	//printf("t_id: %d\n", t_id); 
#if 1
#if 1
	unsigned int paylen = pkt_size; // [Need #2] tx_pkt_size
	int batch = 32;

	(d_tx_desc + t_id)->read.cmd_type_len = IXGBE_TXD_CMD_EOP | IXGBE_TXD_CMD_RS | IXGBE_TXD_CMD_IFCS | IXGBE_TXD_CMD_DEXT | IXGBE_ADVTXD_DTYP_DATA | paylen;
	(d_tx_desc + t_id)->read.olinfo_status = paylen << IXGBE_ADVTXD_PAYLEN_SHIFT;
#if 0
	//if((t_id % 64) == (64 - 1)) {
	if((t_id % batch) == (batch - 1)) { // doorbelling thread
		while(true){
			int32_t cleanable = tx_index - clean_index;
			if(cleanable < 0){
				cleanable = 512 + cleanable;
			}
			if(cleanable < CLEAN_BATCH){
				break;
			}
			int32_t cleanup_to = clean_index + CLEAN_BATCH - 1;
			if(cleanup_to >= 512){
				cleanup_to -= 512;
			}
			if((d_tx_desc + cleanup_to)->wb.status & IXGBE_TXD_STAT_DD){
				int32_t i = clean_index;
				while(true){
					if(i == cleanup_to)
						break;
					i = wrap_ring(i, 512);
				}
				clean_index = wrap_ring(cleanup_to, 512);
			}else{
				break;
			}
		}
	}
#endif
#if 1
	if((t_id % batch) == (batch - 1)) { // doorbelling thread
		while(true){
			// For "writel" every 32-threads(warp) batch.
			if((t_id+1)/batch == readNoCache(&batch_num)){
						//printf("threadIdx.x: %d___(t_id:%d)___batchnum: %d___________________tx: %d, clean: %d\n", threadIdx.x, t_id, (t_id+1)/batch, tx_index, clean_index);
				// If the Index we are trying to writel now is NOT "need-to-clean area" of the ring.

				//[TODO] Make Senderble as cleanable!!!
				
				if(clean_index != t_id){
				//if(sendable){
#if 1
					if(t_id == 511)
						*(volatile unsigned long*)tx_tail_for_queue_zero = (unsigned long)(0);
					//*(volatile unsigned long*)((volatile uint8_t*)io_addr + IXGBE_TDT(0)) = (unsigned long)(0);
					else
						*(volatile unsigned long*)tx_tail_for_queue_zero = (unsigned long)(t_id + 1);
					//*(volatile unsigned long*)((volatile uint8_t*)io_addr + IXGBE_TDT(0)) = (unsigned long)(t_id + 1);
#endif

					// Set "tx_index" for kernel "clean_topia".
					if(t_id == 511)
						tx_index = 0;
					else
						tx_index = t_id + 1; // +1 because this means "How many" not "Which order".

					batch_num = (batch_num + 1);
					if(batch_num == (512/batch)+1)
						batch_num = 1;
					break;
				}
			}
		}
	}
#else
	if((t_id % batch) == (batch - 1)) {
		printf("threadIdx.x: %d___(t_id:%d)___batchnum: %d___________________clean: %d, tx: %d\n", threadIdx.x, t_id, (t_id+1)/batch, clean_index, tx_index);
		if(clean_index != tx_index + 1){
			if(t_id == 511)
				*(volatile unsigned long*)tx_tail_for_queue_zero = (unsigned long)(0);
			else
				*(volatile unsigned long*)tx_tail_for_queue_zero = (unsigned long)(t_id + 1);

			if(t_id == 511)
				tx_index = 0;
			else
				tx_index = t_id + 1;
		}
	}

#endif
#else
	//[TODO] 19.08.15. We don't have to check all desc's STAT_DD flag!
	// We only need to concern about the LAST one!
	//d_tx_flag[t_id] = 1;
	unsigned int paylen = pkt_size; // [Need #2] tx_pkt_size
	//[TODO] IF values below are set, HW never set this desc to STAT_DD!, 19.08.15.

	int batch = 32;
	//if((t_id % batch) != (batch - 1)) {
	d_tx_flag[t_id] = 1;
	//atomicAdd(&d_tx_flag[ ((t_id / batch) + 1) * batch - 1 ], 1);
	//[TODO] 2-codelines below should be moved down.
	// Is is better to access adjacent PCIe address from 1-thread instead of multiple threads?, 19.08.15.
	//(desc + t_id)->read.cmd_type_len = IXGBE_TXD_CMD_EOP | IXGBE_TXD_CMD_RS | IXGBE_TXD_CMD_IFCS | IXGBE_TXD_CMD_DEXT | IXGBE_ADVTXD_DTYP_DATA | paylen;
	//(desc + t_id)->read.olinfo_status = paylen << IXGBE_ADVTXD_PAYLEN_SHIFT;
	//}

	if((t_id % batch) == (batch - 1)) { // doorbelling thread
		bool wait = true;
		while(wait){
			int sum = 0;
			for(int i = t_id - (batch - 1); i < t_id; i++) {
				sum += d_tx_flag[i];
			}
			if(sum == (batch-1)) {
				for(int i = t_id - (batch - 1); i < t_id; i++) {
					d_tx_flag[i] = 0;
					//[TODO] cmd_type_len is critical!!! 13.4 Mpps -> 8 Mpps !!
					//(d_tx_desc + i)->read.cmd_type_len |= paylen;
					(d_tx_desc + i)->read.cmd_type_len = IXGBE_TXD_CMD_EOP | IXGBE_TXD_CMD_RS | IXGBE_TXD_CMD_IFCS | IXGBE_TXD_CMD_DEXT | IXGBE_ADVTXD_DTYP_DATA | paylen;
					(d_tx_desc + i)->read.olinfo_status = paylen << IXGBE_ADVTXD_PAYLEN_SHIFT;
				}
				//printf("threadIdx.x: %d___(t_id:%d)___batchnum: %d\n", threadIdx.x, t_id, (t_id+1)/batch);
				while(true){
					if((t_id+1)/batch == readNoCache(&batch_num)){
						uint32_t status = (d_tx_desc + t_id)->wb.status;
						if(status & IXGBE_TXD_STAT_DD) {
							if(clean_index == tx_index + 1)
								break;
							//printf("_____________________________________________threadIdx.x: %d___(t_id:%d)___writel(%d)\n", threadIdx.x, t_id, (t_id+1)/batch);
							d_tx_flag[t_id] = 0;
							//(d_tx_desc + t_id)->read.cmd_type_len |= paylen;
							(d_tx_desc + t_id)->read.cmd_type_len = IXGBE_TXD_CMD_EOP | IXGBE_TXD_CMD_RS | IXGBE_TXD_CMD_IFCS | IXGBE_TXD_CMD_DEXT | IXGBE_ADVTXD_DTYP_DATA | paylen;
							(d_tx_desc + t_id)->read.olinfo_status = paylen << IXGBE_ADVTXD_PAYLEN_SHIFT;
							if(t_id == 511)
								//*(volatile unsigned long*)tx_tail_for_queue_zero = (unsigned long)(0);
								*(volatile unsigned long*)((volatile uint8_t*)io_addr + IXGBE_TDT(0)) = (unsigned long)(0);
							else
								//*(volatile unsigned long*)tx_tail_for_queue_zero = (unsigned long)(t_id + 1);
								*(volatile unsigned long*)((volatile uint8_t*)io_addr + IXGBE_TDT(0)) = (unsigned long)(t_id + 1);
							wait = false;

							tx_index = t_id + 1;

							batch_num = (batch_num + 1);
							if(batch_num == (512/batch)+1)
								batch_num = 1;
							break;
						}
						//printf("Can't triggering writel______________t_id: %d\n", t_id);
					}
				}
				//printf("return______________threadIdx.x: %d_____________batchnum: %d (t_id:%d)\n", threadIdx.x, (t_id+1)/batch, t_id);
			}else{
				//printf("[FAIL] sum : %d\n", sum);
			}
		}
	}
#endif
#endif
}

__device__ void swap_src_dst(uint8_t *buf, struct pkt_buf *p_buf, int idx)
{
	int i;
	struct ethhdr *ethh;
	struct iphdr *iph;
	ethh = (struct ethhdr *)buf;
	iph = (struct iphdr *)(buf + sizeof(struct ethhdr));

	uint8_t tmp[ETH_ALEN] = {0,};
	uint32_t tmp_ip = 0;
	uint16_t* _saddr = (uint16_t*)&(iph->saddr);
	uint16_t* _daddr = (uint16_t*)&(iph->daddr);
	uint32_t saddr = 0;
	uint32_t daddr = 0;
	memcpy(&saddr, _saddr, 4);
	memcpy(&daddr, _daddr, 4);
	tmp_ip = saddr;
	saddr = daddr;
	daddr = tmp_ip;
	
	
#if 1
	for(i = 0; i < ETH_ALEN; i++) {
		ethh->h_source[i] = p_buf->mac_dst[idx][i];
		ethh->h_dest[i] = p_buf->mac_src[idx][i];
	
//		tmp[i] = ethh->h_source[i];
//		ethh->h_source[i] = ethh->h_dest[i];
//		ethh->h_dest[i] = tmp[i];
	}

//	memcpy((uint16_t*)&iph->saddr, &saddr, 4);
//	memcpy((uint16_t*)&iph->daddr, &daddr, 4);
	
#endif
#if 0
	printf("Source MAC:\n");
	for(i = 0; i < ETH_ALEN; i++) {
		printf("%02x ", p_buf->mac_src[idx][i]);
	}
	printf("\n");
	
	printf("Dest MAC:\n");
	for(i = 0; i < ETH_ALEN; i++) {
		printf("%02x ", p_buf->mac_dst[idx][i]);
	}
	printf("\n");
#endif
}


__global__ void writeler(void)
{
	int i;
	int idx = 0;
	for(i = 0; i < 16; i++)
		tx_warp[i] = 0;
	while(true)
	{
		//for(i = 0; i < 16; i++)
		//	printf("%d ", tx_warp[i]);
		//printf("\n");
		if(tx_warp[idx] == 1){
			printf("idx: %d\n", idx);
			if(clean_index == tx_index + 1)
				continue;
			int t_id = (idx + 1)*32 - 1;

			if(t_id == 511)
				*(volatile unsigned long*)tx_tail_for_queue_zero = (unsigned long)(0);
			else
				*(volatile unsigned long*)tx_tail_for_queue_zero = (unsigned long)(t_id + 1);

			if(t_id == 511)
				tx_index = 0;
			else
				tx_index = t_id + 1;
			tx_warp[idx] = 0;
			idx++;
		}
	}
}

#define LOG 1
//__global__ void tx_handler(volatile union ixgbe_adv_tx_desc* tx_desc, unsigned char* gtx_desc, volatile uint8_t* io_addr, int* pkt_cnt)
__global__ void tx_handler(union ixgbe_adv_tx_desc* gtx_desc, volatile uint8_t* io_addr, int* pkt_cnt, uint64_t *gddr_dma_addr)
{
	__shared__ int clean[512];
	__shared__ int tx[512];
	__shared__ int desc[512];
	__shared__ int clean_index; // sum of clean[512] 
	__shared__ int tx_index; // sum of tx[512]
	__shared__ int cleanable;
	__shared__ int cleanup_to;
	__shared__ int do_clean;

	__shared__ clock_t t1, t2;
	__shared__ int yhoon_num;

	int tx_hang = 0; // For each threads. 19.08.31.

// Initialize variables
	if(threadIdx.x == 0){
		int i;
		for(i = 0; i < 512; i++){
			clean[i] = 1; // Every desc is "Clean".
			tx[i] = 0; // Every desc is usable.
			desc[i] = 0;
		}
		clean_index = 0;
		tx_index = 0;
		cleanable = 0;
		cleanup_to = 0;
		do_clean = 0;
		t1 = 0;
		t2 = 0;
		for(i = 0; i < 512; i++){
			(gtx_desc + i)->read.buffer_addr = *gddr_dma_addr + 0x1000*i;
			(gtx_desc + i)->read.cmd_type_len = IXGBE_TXD_CMD_EOP | IXGBE_TXD_CMD_RS | IXGBE_TXD_CMD_IFCS | IXGBE_TXD_CMD_DEXT | IXGBE_ADVTXD_DTYP_DATA;
		}
	}
	// Persistent Loop
	int count = 0;
	while(true){
#if 0
		if(threadIdx.x == 0)
			printf("__________________________________________________start of Persist.loop\n");
#endif
/////////////////////////////////// desc-clean-routine //////////////////////////////////////
			// tx_index, clean_index, cleanable, cleanup_to
#if 0
		if(threadIdx.x == 0){
		//	if(count++ % 10000 == 0) {
				int i;
		
				for(i = 0; i < 512; i++){
					if(i % 32 == 0)
						printf("\n");
					printf("%d ", desc[i]);
				}
				
				printf("\n\n");
		
				//printf("tx_index: %d, clean_index: %d\n", tx_index, clean_index);
				/*
				for(i = 0; i < 512; i++){
					if(i % 32 == 0)
						printf("\n");
					printf("%d ", (tx_desc + i)->wb.status & IXGBE_TXD_STAT_DD);
				}
				printf("\n\n");
			*/
		//	}
		}
			__syncthreads();
#endif
			__syncthreads(); //[TODO] If we have path divergence below, this line is necessary!
#if 0
			if(threadIdx.x % CLEAN_BATCH == (CLEAN_BATCH-1) && desc[threadIdx.x] == 1) {  // --> Need to clean (used for Tx).
				//printf("threadId: %d\n", (threadIdx.x + 1)/32);
				//if(desc[threadIdx.x] == 1) {  // --> Need to clean (used for Tx).
				//if(readNoCache(& ((tx_desc + threadIdx.x)->wb.status)) & IXGBE_TXD_STAT_DD) {
				if(((gtx_desc + threadIdx.x)->wb.status) & IXGBE_TXD_STAT_DD) {
					for(int i=0; i<CLEAN_BATCH; i++)
						desc[threadIdx.x-i] = 0;
				}
			}
#endif
#if 1
			//if(threadIdx.x == (clean_index + CLEAN_BATCH - 1)){
			if(threadIdx.x == wrap_ring(clean_index, CLEAN_BATCH - 1, 512)){      
				if(((gtx_desc + threadIdx.x)->wb.status) & IXGBE_TXD_STAT_DD) {
					for(int i=0; i<CLEAN_BATCH; i++)
						desc[threadIdx.x-i] = 0;
				clean_index = wrap_ring(threadIdx.x, 1, 512);
				//atomicAdd(&pkt_cnt[1], SEND_BATCH);
				}
			}
#else
			if(threadIdx.x == wrap_ring(clean_index, CLEAN_BATCH - 1, 512)){      
				int cnt = 0;                                                        
				while(true){                                                        
					if(cnt > 3){                                                      
						for(int i=0; i<CLEAN_BATCH; i++)                              
							desc[threadIdx.x-i] = 0;                                    
						clean_index = wrap_ring(threadIdx.x, 1, 512);                 
						break;                                                        
					}                                                                 
					int cleanable = tx_index - clean_index;                           
					if(cleanable < 0)                                                 
						cleanable = 512 + cleanable;                                    
					if(cleanable < CLEAN_BATCH) break;                                
					if(((gtx_desc + threadIdx.x)->wb.status) & IXGBE_TXD_STAT_DD) {   
						for(int i=0; i<CLEAN_BATCH; i++)                                
							desc[threadIdx.x-i] = 0;                                      
						clean_index = wrap_ring(threadIdx.x, 1, 512);                   
					}                                                                 
					cnt++;                                                            
				}                                                                   
			}                                                                     
#endif
			__syncthreads();
			//	if(desc[threadIdx.x] == 0) { // --> Able to tx (cleaned).
			if(threadIdx.x >= tx_index && threadIdx.x < tx_index + SEND_BATCH) {
				if(desc[threadIdx.x] == 0){
					unsigned int paylen = PKT_SIZE;
					(gtx_desc + threadIdx.x)->read.cmd_type_len = IXGBE_TXD_CMD_EOP | IXGBE_TXD_CMD_RS | IXGBE_TXD_CMD_IFCS | IXGBE_TXD_CMD_DEXT | IXGBE_ADVTXD_DTYP_DATA | paylen;
					(gtx_desc + threadIdx.x)->read.olinfo_status = paylen << IXGBE_ADVTXD_PAYLEN_SHIFT;
					desc[threadIdx.x] = 1;
					if(threadIdx.x == tx_index + SEND_BATCH - 1){
						//tx_index = wrap_ring(threadIdx.x, 512);
						tx_index = wrap_ring(threadIdx.x, 1, 512);
						*(volatile unsigned long*)((volatile uint8_t*)io_addr + IXGBE_TDT(0)) = (unsigned long)(tx_index);
						//printf("writel, tx_index: %d\n", tx_index);
						atomicAdd(&pkt_cnt[1], SEND_BATCH);
					}
				}
			}
			__syncthreads();
	} // while(true)
}

#define C_SIZE 64
__global__ void tx_test(int* pkt_cnt, volatile uint8_t* io_addr)
{
	__shared__ int num_turns;
	//__shared__ clock_t start;

	__shared__ int num;
	__shared__ int t_id;
	__shared__ int batch;

	if(threadIdx.x == 0){
		num = 0;
		t_id = 0;
		batch = 32;
	}


	clock_t start; // For each thread
	start = clock64();

	while(num_turns < NUM_TURN_rx_handler){
#if 0
		if(threadIdx.x == 0)
		{
			while(1){
				//if(3000.0 <= (float)(((clock64() - start)/1480000000.0)*1000.0)){
				if(0.02 <= (float)(((clock64() - start)/1480000000.0)*1000.0)){
					start = clock64();
					break;
				}
			}
		}
		__syncthreads();
#endif
#if 0
		while(1){
			if(0.03 <= (float)(((clock64() - start)/1480000000.0)*1000.0)){
				start = clock64();
				break;
			}
		}
#endif
		//send(64, num, t_id, batch);
		send(64, io_addr);


	}
}


__global__ void var_map(struct pkt_buf *p_buf, volatile uint8_t* io_addr, volatile union ixgbe_adv_tx_desc* tx_desc, uint64_t *gddr_dma_addr, int* pkt_cnt)
{
	//d_tx_buf = p_buf->tx_buf;
	d_p_buf = p_buf;
	d_io_addr = io_addr;
	d_tx_desc = tx_desc;
	d_gddr_dma_addr = gddr_dma_addr;
	d_tx_cnt = &pkt_cnt[1];
	for(int i=0; i<512; i++) {
		d_tx_flag[i] = 0;
		(d_tx_desc+i)->wb.status |= IXGBE_TXD_STAT_DD;
	}
	batch_num = 1;
	tx_tail_for_queue_zero = (volatile uint8_t*)io_addr + IXGBE_TDT(0);
	//rx_tail_for_queue_zero = (volatile uint8_t*)io_addr + IXGBE_RDT(0);
}


__global__ void old_tx_handler(struct pkt_buf *p_buf, int* pkt_cnt, volatile uint8_t* io_addr, volatile union ixgbe_adv_tx_desc* tx_desc, uint64_t *gddr_dma_addr)
{
	__shared__ int num_turns;
	__shared__ int begin;
	__shared__ int batch_map[16];
	__shared__ int warp_idx;

	int idx = 0;
	if(threadIdx.x == 0){
		int i;
		for(i = 0; i < 16; i++)
			batch_map[i] = 0;
		warp_idx = 0;
	}

	tx_tail_for_queue_zero = io_addr + IXGBE_TDT(0);
	while(num_turns < NUM_TURN_rx_handler) {
#if 0
		if(threadIdx.x == 0){
			if(batch_map[idx] == 1){
				int t_id = ((idx+1)*32) - 1;
									
				if(t_id == 511)
					*(volatile unsigned long*)tx_tail_for_queue_zero = (unsigned long)(0);
				else
					*(volatile unsigned long*)tx_tail_for_queue_zero = (unsigned long)(t_id + 1);
			
				batch_map[idx] = 0;
				idx += 1;
				if(idx == 17)
					idx = 1;
			}
		}
#endif
		if(readNoCache(&(p_buf->tx_buf_idx[threadIdx.x])) == 1){ // [Need #1] tx_buf_idx
			p_buf->tx_buf_idx[threadIdx.x] = 0;
			//printf("[tx_handler] got pkt. tid: %d\n", t_id);

			//	p_buf->rx_no_poll[t_id] = 1; // pause rx_handler for this buf.
#if 1
#if 1
	//		memcpy(&p_buf->tx_buf[0x1000 * threadIdx.x], tmp_pkt, p_buf->tx_pkt_size[threadIdx.x]);
#else
			memcpy(&p_buf->tx_buf[0x1000 * threadIdx.x], &p_buf->rx_buf[0x1000 * threadIdx.x], p_buf->tx_pkt_size[threadIdx.x]);


			swap_src_dst((uint8_t*)(&p_buf->tx_buf[0x1000 * threadIdx.x]), p_buf, threadIdx.x);
			struct iphdr *iph;
			iph = (struct iphdr *)(&(p_buf->rx_buf[0x1000 * threadIdx.x]) + sizeof(struct ethhdr));
			iph->check = ip_fast_csum(iph, iph->ihl);
#endif

#if 0
			START_GRN
0		printf("_________________________________________[TX_handler]\n");
			END
			DumpPacket_raw(&p_buf->tx_buf[0x1000 * t_id], p_buf->tx_pkt_size[t_id]);
#endif
			//volatile union ixgbe_adv_tx_desc *desc = tx_desc + t_id;

#if 1
			unsigned int paylen = p_buf->tx_pkt_size[threadIdx.x]; // [Need #2] tx_pkt_size
			//(tx_desc + threadIdx.x)->read.cmd_type_len = IXGBE_TXD_CMD_EOP | IXGBE_TXD_CMD_RS | IXGBE_TXD_CMD_IFCS | IXGBE_TXD_CMD_DEXT | IXGBE_ADVTXD_DTYP_DATA | paylen;
			(tx_desc + threadIdx.x)->read.cmd_type_len |= paylen;
			(tx_desc + threadIdx.x)->read.olinfo_status = paylen << IXGBE_ADVTXD_PAYLEN_SHIFT;
#endif
#if 0
			if(threadIdx.x % 32 == 31){
				batch_map[((threadIdx.x+1)/32)-1] = 1;
				//printf("tid: %d\n", ((threadIdx.x+1)/32)-1);
			}
#endif
			int num = atomicAdd(&pkt_cnt[1], 1);
			int t_id = num % 512;

			//printf("t_id: %d\n", t_id);
			
#if 1
			if(threadIdx.x % 32 == 31){

					//printf("t_id: %d\n", (threadIdx.x+1)/32);
					//[TODO] Order is trash itself! WTF.
					int n = atomicAdd(&warp_idx, 1);
					int tt = n % 16;
				
					printf("tt: %d_________warp_idx: %d\n", tt, ((tt+1)*32-1));
						if(((tt+1)*32-1) == 511)
							*(volatile unsigned long*)tx_tail_for_queue_zero = (unsigned long)(0);
						else
							*(volatile unsigned long*)tx_tail_for_queue_zero = (unsigned long)((tt+1)*32);
			}
#endif
			// [TODO] clean buffer (re-map)
				//for(i = 0; i < C_SIZE; i++){
				//	(desc + threadIdx.x)->read.buffer_addr = *gddr_dma_addr + threadIdx.x*0x1000; 
				//}
			//}
			//*(volatile unsigned long*)tx_tail_for_queue_zero = (unsigned long)(t_id);
			//*(uint16_t*)(&p_buf->rx_buf[0x1000*(t_id)]) = 0;

			// After Tx,
			//p_buf->tx_pkt_size[t_id] = 0;

#if 0
			//19.07.11, CKJUNG, If we do here, rx pps goes CRAZY!!!
			p_buf->rx_buf[0x1000 * t_id] = 0; // Prohibiting read.
			p_buf->rx_buf[(0x1000 * t_id)+1] = 0; // Prohibiting read. 
#endif
#if 0
			// Tx needs more time? 19.07.11 (writel?)
			if(t_id == 0){
				p_buf->tx_buf[0x1000 * 511] = 0; // Prohibiting read.
				p_buf->tx_buf[(0x1000 * 511)+1] = 0; // Prohibiting read. 
			}else{
				p_buf->tx_buf[0x1000 * (t_id-1)] = 0; // Prohibiting read.
				p_buf->tx_buf[(0x1000 * (t_id-1))+1] = 0; // Prohibiting read. 
			}
			__threadfence();
#endif
		//	p_buf->rx_no_poll[t_id] = 0; // resume rx_handler for this buf.

#endif
		}
	}
}

__global__ void rx_handler(struct pkt_buf *p_buf, int* pkt_cnt, int* pkt_size, volatile uint8_t* io_addr, volatile union ixgbe_adv_rx_desc* rx_desc, uint64_t *gddr_dma_addr)
{
	__shared__ int num_turns;
	__shared__ int max;
	__shared__ int flag[512];
	__shared__ volatile uint8_t *rx_tail_for_queue_zero_s;
	int i;
	// CKJUNG, 18.10.19,  Connect "d_pkt_buffer" with "p_buf" here in rx_handler. 
	// We'll just use p_buf from NFs.
	//p_buf->tx_buf = d_pkt_buffer;
	//p_buf->rx_buf = p_buf->tx_buf + offset_for_rx;

	BEGIN_SINGLE_THREAD_PART{
		for(i = 0; i < 512; i++)
			flag[i] = 0;
		num_turns = 0;
		max = 0;
	} END_SINGLE_THREAD_PART;
	//if(threadIdx.x == 0)
		//printf("[GPU]rx_handler, gddr_dma_addr: %p\n", *gddr_dma_addr);
	int mem_index = 0x1000 * threadIdx.x;
	uint64_t rx_dma_addr = *gddr_dma_addr + 0x1000*512 + threadIdx.x*0x1000;
	rx_tail_for_queue_zero_s = io_addr + IXGBE_RDT(0);
	while(num_turns < NUM_TURN_rx_handler) { // Persistent kernel
			//printf("[Rx_Hdlr] Infinite_loop num_turns: %d\n", num_turns);
			BEGIN_SINGLE_THREAD_PART{
#if 0
				if(*(&pkt_cnt[0]) != 0 && *(&pkt_cnt[0]) % 512 == 0){ // Reset index to "0", when exceeds 512. 
					for(i = 0; i < 512; i++)
						p_buf->rx_buf_idx[i] = 0;
				}
#endif		
#if 0
				if(*(&pkt_cnt[0]) != 0 && *(&pkt_cnt[0]) % BATCH == 0){ // Set index to "2", batch 32.
					for(i = 0; i < 512; i++){
						if(p_buf->rx_buf_idx[i] == 1)
							p_buf->rx_buf_idx[i] = 2;
					}
				}
#endif
			} END_SINGLE_THREAD_PART;

				//printf("[rx_handler] got pkt. tid: %d, %d\n", threadIdx.x, (uint8_t)p_buf->rx_buf[mem_index]);

#if 0
			BEGIN_SINGLE_THREAD_PART{
				if(pkt_cnt[0] > 0 && pkt_cnt[0] % 500 == 0)
					*(volatile unsigned long*)rx_tail_for_queue_zero = (unsigned long)(last_idx);
			} END_SINGLE_THREAD_PART;
#endif
#if 0
#define POLLING_THS 128
			if(threadIdx.x % (512/POLLING_THS) == (512/POLLING_THS)-1)
			{
				for(i = threadIdx.x - ((512/POLLING_THS)-1); i <= threadIdx.x; i++)
				{
					if((readNoCache((uint16_t*)&p_buf->rx_buf[0x1000*i]) != 0))
					{
						flag[i] = 1;
					}
				}

			}
			if((readNoCache(&flag[threadIdx.x]) != 0)){
#else
			if(readNoCache((uint16_t*)&p_buf->rx_buf[mem_index]) != 0){
#endif

				//p_buf->rx_no_poll[threadIdx.x] = 1; // pause rx_handler for this buf.
				//if(readNoCache((uint16_t*)&p_buf->rx_buf[mem_index]) != 0 && p_buf->tx_buf_idx[threadIdx.x] == 0 ){
				//printf("[rx_handler] got pkt. tid: %d\n", threadIdx.x);

#if 0
				START_BLU
				printf("_________________________________________[RX_handler]\n");
				END
				DumpPacket_raw(&p_buf->rx_buf[0x1000 * threadIdx.x], 64);
#endif
#if 0
				struct ethhdr *ethh;
				ethh = (struct ethhdr *)&p_buf->rx_buf[mem_index];
				int i;
				for(i = 0; i < ETH_ALEN; i++)
				{
					p_buf->mac_src[threadIdx.x][i] = ethh->h_source[i];
					p_buf->mac_dst[threadIdx.x][i] = ethh->h_dest[i];
				}
#endif

				atomicAdd(&pkt_cnt[0], 1);

				// 19.04.11, CKJUNG

				//atomicAdd(num_turns, 1);
#if 0
				atomicAdd(&cnt, 1);
				acum_cnt[threadIdx.x] = cnt;
				rx_ed = clock64();
				//printf("\033[1;32m[Rx_Hdlr] Buf_id[%d]: %lf\033[0m\n", threadIdx.x,(double)(((double)rx_ed - (double)rx_st)/1480000000.0)*1000.0);
				printf("%3d %lf %3d\n", threadIdx.x,(double)(((double)rx_ed - (double)rx_st)/1480000000.0)*1000.0, acum_cnt[threadIdx.x]);
#endif

				//[TODO] buf_idx to 1 at each threads (parallelism)??
#if 0
				if(pkt_cnt[0] % BATCH == 0 && pkt_cnt[0] != 0){
					for(i = threadIdx.x; i > threadIdx.x - BATCH; i--)
						p_buf->rx_buf_idx[i] = 1; // [Step 1] If we receive something.
				}
#else					
				__syncthreads();
				p_buf->rx_buf_idx[threadIdx.x] = 1; // [Step 1] If we receive something.
#endif	
				p_buf->rx_buf[mem_index] = 0; // Prohibiting read.
				p_buf->rx_buf[mem_index+1] = 0; // Prohibiting read. 
				//flag[threadIdx.x] = 0;

				__syncthreads();
				volatile union ixgbe_adv_rx_desc *desc = rx_desc + threadIdx.x;
				desc->read.pkt_addr = rx_dma_addr;
				desc->wb.upper.length = 0;

#if 1
				// "rx_desc" is stored in Global memory. 19.08.07. CKJUNG 
				//__threadfence();
				//int batch_size = 32*8;
				//if(threadIdx.x % batch_size  == (batch_size - 1)){
				
				__syncthreads();
				if(threadIdx.x % (32*8)  == ((32*8) - 1)){
					*(volatile unsigned long*)rx_tail_for_queue_zero_s = (unsigned long)(threadIdx.x);
				}
				//__syncthreads();
#else
				if(pkt_cnt[0] > 0 && pkt_cnt[0] % 32 == 0){
					printf("tid: %d, pkt_cnt: %d\n", threadIdx.x, pkt_cnt[0]);
					*(volatile unsigned long*)rx_tail_for_queue_zero = (unsigned long)(threadIdx.x);
				}

#endif

				//p_buf->rx_done[threadIdx.x] = 1;

				unsigned char* rx_packet = &p_buf->rx_buf[0x1000*threadIdx.x];
				unsigned char* tx_packet = &p_buf->tx_buf[0x1000*threadIdx.x];
				if(*(uint16_t*)(rx_packet+12) != 0) {
					struct ethhdr *ethh = (struct ethhdr *)rx_packet;
					u_short ip_proto = NTOHS(ethh->h_proto);
					
					struct iphdr *iph = (struct iphdr *)(rx_packet + sizeof(struct ethhdr));
					int ip_len = NTOHS(iph->tot_len);
					*pkt_size = ip_len + 18; // + mac header (18 Bytes)

					if (ip_proto == ETH_P_ARP) {
						ProcessARPPacket(tx_packet, rx_packet, 60); // [TODO] Need to off NFs..
						p_buf->tx_buf_idx[threadIdx.x] = 1; // Send!
						p_buf->tx_pkt_size[threadIdx.x] = 60;
						atomicAdd(&pkt_cnt[1], 1);
					}else if(ip_proto == ETH_P_IP) {
						// TODO: passing len from below
#if 0
						if(ProcessIPv4Packet(tx_packet, rx_packet, 1500, pkt_size)){
							//printf("ICMP] tid: %d\n", threadIdx.x);
							p_buf->tx_buf_idx[threadIdx.x] = 1; // Send!
							p_buf->tx_pkt_size[threadIdx.x] = *pkt_size;
							//printf("pkt_size: %d\n", *pkt_size);
							atomicAdd(&pkt_cnt[1], 1);
						}
#endif
						;
					}else {
						printf("[%s][%d] %d thread unknown protocol\n", __FUNCTION__, __LINE__, threadIdx.x);
					}
					//*(uint16_t*)(rx_packet+12) = 0;
				}
			}
	} // ~ while
	if(threadIdx.x == 0)
		printf("End of rx_handler!\n");
}

// YHOON~ for test
int tx_rx_ring_setup()
{
  const char *myinode = "/dev/ixgbe";
  int fd = open(myinode, O_RDWR);
  ioctl(fd, 1);
  return fd;
}

void yhoon_finalizer(void* ixgbe_bar0_host_addr, void* desc_addr)
{
  const size_t IXGBE_BAR0_SIZE = 4096*8; // A rough calculation
	printf("Finalizer called!\n");
  cudaHostUnregister(desc_addr);
  cudaHostUnregister(ixgbe_bar0_host_addr);
  munmap(ixgbe_bar0_host_addr, IXGBE_BAR0_SIZE*5);
}



void yhoon_initializer(int fd, void *ixgbe_bar0_host_addr, void *tx_desc_addr, void *rx_desc_addr, void **io_addr, void **tx_desc, void **rx_desc)
{
	const size_t IXGBE_BAR0_SIZE = 4096*8; // A rough calculation

	ixgbe_bar0_host_addr = mmap(0, 4096*12, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	//ixgbe_bar0_host_addr = mmap(0, IXGBE_BAR0_SIZE*5 , PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if(ixgbe_bar0_host_addr == MAP_FAILED) {
		  START_RED
				  printf("mmap Error!\n");
			  END
					  exit(1);
	}

	printf("[mmap] ixgbe_bar0_host_addr: %p\n", ixgbe_bar0_host_addr);
	cudaError_t desc_addr_error = cudaHostRegister(ixgbe_bar0_host_addr, IXGBE_BAR0_SIZE, cudaHostRegisterIoMemory);
	ASSERTRT(desc_addr_error);
	if(desc_addr_error != cudaSuccess) {
		  START_RED
				    fprintf(stdout, "%s\n", cudaGetErrorName(desc_addr_error));
			  END
					 // yhoon_finalizer(ixgbe_bar0_host_addr, desc_addr);
				  exit(1);
	}
	ASSERTRT(cudaHostGetDevicePointer((void**)io_addr, (void*)ixgbe_bar0_host_addr, 0));
	printf("[GetDevicePtr] io_addr: %p\n", *io_addr);

	tx_desc_addr = (void*)((unsigned char*)ixgbe_bar0_host_addr + IXGBE_BAR0_SIZE);
	printf("[offset] tx_desc_addr: %p\n", tx_desc_addr);
	desc_addr_error = cudaHostRegister(tx_desc_addr, 0x1000*2, cudaHostRegisterIoMemory);
	if(desc_addr_error != cudaSuccess) {
		  START_RED
				    printf("%s\n", cudaGetErrorName(desc_addr_error));
			  END
					//  yhoon_finalizer(ixgbe_bar0_host_addr, desc_addr);
				  exit(1);
	}
	ASSERTRT(cudaHostGetDevicePointer((void**)tx_desc, (void*)tx_desc_addr, 0));
	if(*tx_desc != NULL){
		  START_GRN
				  printf("tx_desc ready :)\n");
			END
	}

	rx_desc_addr = (void*)((unsigned char*)ixgbe_bar0_host_addr + IXGBE_BAR0_SIZE + 4096*2);
	printf("[offset] rx_desc_addr: %p\n", rx_desc_addr);                                    
	desc_addr_error = cudaHostRegister(rx_desc_addr, 0x1000*2, cudaHostRegisterIoMemory);   
	if(desc_addr_error != cudaSuccess) {                                                    
		START_RED                                                                             
			printf("%s\n", cudaGetErrorName(desc_addr_error));                                  
		END                                                                                   
			//  yhoon_finalizer(ixgbe_bar0_host_addr, desc_addr);                               
			exit(1);                                                                            
	}                                                                                       
	ASSERTRT(cudaHostGetDevicePointer((void**)rx_desc, (void*)rx_desc_addr, 0));            
	if(*rx_desc != NULL){                                                                   
		START_GRN                                                                             
			printf("rx_desc ready :)\n");                                                       
		END                                                                                   
	}                                                                                       

	printf("[GetDevicePtr] tx_desc: %p\n", *tx_desc);
	printf("[GetDevicePtr] rx_desc: %p\n", *rx_desc);
}

extern "C"
void initialize_gdnio(void)
{
	printf("____[Initialize]__GDNIO__\n");
	int dev_id = 0;
	size_t _pkt_buffer_size = 2*512*4096; // 4MB, for rx,tx ring
	size_t pkt_buffer_size = (_pkt_buffer_size + GPU_PAGE_SIZE - 1) & GPU_PAGE_MASK;
	int n_devices = 0;
	ASSERTRT(cudaGetDeviceCount(&n_devices));

	cudaDeviceProp prop;
	for (int n=0; n<n_devices; ++n) {
		cudaGetDeviceProperties(&prop,n);
		OUT << "GPU id:" << n << " name:" << prop.name 
			<< " PCI domain: " << prop.pciDomainID 
			<< " bus: " << prop.pciBusID 
			<< " device: " << prop.pciDeviceID << endl;
	}
	OUT << "selecting device " << dev_id << endl;
	OUT << "_pkt_buffer_size: " << _pkt_buffer_size << "  pkt_buffer_size: " << pkt_buffer_size << endl;


	int peak_clk = 1; // in kHz
	//CKJUNG 18.03.17
	ASSERTRT(cudaDeviceGetAttribute(&peak_clk, cudaDevAttrClockRate, dev_id));
	OUT << "GPU___Peak_clockrate:" << peak_clk << " kHz" << endl;
	// ~CKJUNG

	ASSERTRT(cudaSetDevice(dev_id));

	// 18.10.25, CKJUNG, We Reset the device to fresh each run.
	ASSERTRT(cudaDeviceReset());
  ASSERTRT(cudaSetDeviceFlags(cudaDeviceMapHost));


//	unsigned char* d_pkt_buffer;
  ASSERTRT(cudaMalloc((void**)&d_pkt_buffer, pkt_buffer_size));
  ASSERTRT(cudaMemset(d_pkt_buffer, 0, pkt_buffer_size));

// Allocate "Tx-desc" in GDDR, 19.09.02. CKJUNG
  ASSERTRT(cudaMalloc((void**)&gtx_desc, sizeof(union ixgbe_adv_tx_desc)*512));
  ASSERTRT(cudaMemset(gtx_desc, 0, sizeof(union ixgbe_adv_tx_desc)*512));


	unsigned int flag = 1;
	ASSERTDRV(cuPointerSetAttribute(&flag, CU_POINTER_ATTRIBUTE_SYNC_MEMOPS, (CUdeviceptr) d_pkt_buffer));
	ASSERTDRV(cuPointerSetAttribute(&flag, CU_POINTER_ATTRIBUTE_SYNC_MEMOPS, (CUdeviceptr) gtx_desc));

	my_t g = my_open();

	ASSERT_NEQ(g, (void*)0);

	uint64_t ret_dma_addr;
	my_mh_t mh;
	printf("[GDNIO]Pinning Pkt_Buffer in GDDR\n");
	if (my_pin_buffer(g, (CUdeviceptr)d_pkt_buffer, pkt_buffer_size, 0, 0, &mh, &ret_dma_addr)  != 0)
		OUT << "[my_pin_buffer] NOT_EQ" << endl;

	printf("[GDNIO]Pinning Tx_desc in GDDR\n");
	if (my_pin_desc(g, (CUdeviceptr)gtx_desc, sizeof(union ixgbe_adv_tx_desc), 0, 0, &mh)  != 0)
		OUT << "[my_pin_desc] NOT_EQ" << endl;

#if 0
	*ixgbe_bar0_host_addr = 0;
	*io_addr = 0;
	*tx_desc = 0;
	*rx_desc = 0;
	*tx_desc_addr = 0;
	*rx_desc_addr = 0;
#endif
	int fd = tx_rx_ring_setup();
	yhoon_initializer(fd, ixgbe_bar0_host_addr, tx_desc_addr, rx_desc_addr, &io_addr, &tx_desc, &rx_desc);
	
	cudaStream_t cuda_stream1;
	cudaStream_t cuda_stream5;
	cudaStream_t cuda_stream6;
	ASSERT_CUDA(cudaStreamCreateWithFlags(&cuda_stream1,cudaStreamNonBlocking));
	ASSERT_CUDA(cudaStreamCreateWithFlags(&cuda_stream5,cudaStreamNonBlocking));
	ASSERT_CUDA(cudaStreamCreateWithFlags(&cuda_stream6,cudaStreamNonBlocking));
	
	// CKJUNG, 18.10.17 p_buf struct added.
	//int *pkt_cnt; // pkt_cnt[0]:RX, pkt_cnt[1]:TX
	//int *pkt_size;
	//struct pkt_buf *p_buf;
	//unsigned int *ctr;

  ASSERTRT(cudaMalloc((void**)&pkt_cnt, sizeof(int)*2));
  ASSERTRT(cudaMalloc((void**)&pkt_size, sizeof(int)));
  ASSERTRT(cudaMalloc((void**)&p_buf, sizeof(struct pkt_buf)));
  ASSERTRT(cudaMalloc((void**)&ctr, sizeof(unsigned int)));

	ASSERTRT(cudaMalloc((void**)&gddr_dma_addr, sizeof(uint64_t)));
	ASSERTRT(cudaMemcpy(gddr_dma_addr, &ret_dma_addr, sizeof(uint64_t), cudaMemcpyHostToDevice));
	

	ASSERT_CUDA(cudaMemset(pkt_cnt, 0, sizeof(int)*2));
	ASSERT_CUDA(cudaMemset(pkt_size, 0, sizeof(int)));
	ASSERT_CUDA(cudaMemset(p_buf, 0, sizeof(struct pkt_buf)));
	ASSERT_CUDA(cudaMemset(ctr, 0, sizeof(unsigned int)));


  clean_buffer<<< 1, 1 >>> (d_pkt_buffer, pkt_buffer_size, p_buf);
	var_map<<<1, 1 >>> (p_buf, (volatile uint8_t*)io_addr, (volatile union ixgbe_adv_tx_desc*)tx_desc, gddr_dma_addr, pkt_cnt); 

	cudaDeviceSynchronize();
#if 1
	START_RED
	printf("[GDNIO]#0: Rx_handler\n");
	END
	rx_handler<<< 1, 512, 0, cuda_stream1 >>> (p_buf, pkt_cnt, pkt_size, (volatile uint8_t*)io_addr, (volatile union ixgbe_adv_rx_desc*)rx_desc, gddr_dma_addr);
#endif
#if 0
	START_BLU
	printf("[GDNIO]#0: Tx_handler\n");
	END
	//tx_handler<<< 1, 512, 0, cuda_stream5 >>> (p_buf, pkt_cnt, (volatile uint8_t*)io_addr, (volatile union ixgbe_adv_tx_desc*)tx_desc, gddr_dma_addr); 
	tx_handler<<< 1, 512, 0, cuda_stream5 >>> ((union ixgbe_adv_tx_desc*)gtx_desc, (volatile uint8_t*)io_addr, pkt_cnt, gddr_dma_addr); 
#endif
#if 0
	START_YLW
	printf("[GDNIO]#0: tx_test\n");
	END
	tx_test<<< 1, 512, 0, cuda_stream6 >>> (pkt_cnt, (volatile uint8_t*)io_addr);
#endif

#if 0
	START_RED
	printf("[GDNIO]#0: writeler\n");
	END
	writeler<<< 1, 1, 0, cuda_stream5 >>> ();
#endif




	START_GRN
	printf("[Done]____[Initialize]__GDNIO__\n");
	END
}

extern "C"
void wait_for_gpu(void)
{
	cudaDeviceSynchronize();
}

// returns a timestamp in nanoseconds
// based on rdtsc on reasonably configured systems and is hence fast
uint64_t monotonic_time() {
	struct timespec timespec;
	clock_gettime(CLOCK_MONOTONIC, &timespec);
	return timespec.tv_sec * 1000 * 1000 * 1000 + timespec.tv_nsec;
}

extern "C"
void monitoring_loop(void)
{
	START_GRN
		printf("Control is returned to CPU! :)\n");
	END
		// CKJUNG, 18.06.30
		struct timeval prev, cur;
	int prev_pkt[2] = {0,}, cur_pkt[2] = {0,};
	double pkts[2];
	char units[] = {' ', 'K', 'M', 'G', 'T'};
	char pps[2][40];
	char bps[2][40];
	int buf_idx[512] = {0,};
	int p_size=0;
	int i, j;
	int data[1024] = {0,};

	uint64_t last_stats_printed = monotonic_time();
	uint64_t time;
	// Replace "gettimeofday" to "clock_gettime", CKJUNG, 20.01.13
	//gettimeofday(&prev, NULL);
	while(1)                                           
	{
		time = monotonic_time();
		if(time - last_stats_printed > 1000 * 1000 * 1000){
			printf("elapsed time: %d\n", (time - last_stats_printed)/(1000*1000));
			last_stats_printed = time;
			//gettimeofday(&cur, NULL);
			//if(((cur.tv_sec - prev.tv_sec) * 1000000) + (cur.tv_usec - prev.tv_usec) > 1000000){
			//prev = cur;
			//printf("%p, %p\n", p_buf->tx_buf, d_pkt_buffer+(512*0x1000));
			cudaError_t err = cudaMemcpy(&cur_pkt[0], &pkt_cnt[0], sizeof(int), cudaMemcpyDeviceToHost);
			cudaError_t err2 = cudaMemcpy(&cur_pkt[1], &pkt_cnt[1], sizeof(int), cudaMemcpyDeviceToHost);
			cudaError_t err3 = cudaMemcpy(&p_size, pkt_size, sizeof(int), cudaMemcpyDeviceToHost);
			cudaError_t err4 = cudaMemcpy(buf_idx, (p_buf->rx_buf_idx), sizeof(int)*512, cudaMemcpyDeviceToHost);
			//cudaError_t err5 = cudaMemcpy(data, (p_buf->rx_buf), sizeof(int)*1024, cudaMemcpyDeviceToHost);
			//cudaError_t err5 = cudaMemcpy(data, d_pkt_buffer+(512*0x1000), sizeof(int)*1024, cudaMemcpyDeviceToHost);


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
				double batch;
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

__global__ void print_gpu(unsigned char* d_pkt_buf, int size)
{
	int i;
	printf("[GPU]:\n");
	for(i = 0; i < size; i++)
		printf("%02x ", d_pkt_buf[i]);
	printf("\n");
}


extern "C"
void copy_to_gpu(unsigned char* buf, int size)
{
	unsigned char *d_pkt_buf;
	cudaMalloc((void**)&d_pkt_buf, sizeof(unsigned char)*1500);
	printf("____1__________copy_to_gpu____\n");
	//cudaMemcpy(&p_buf->rx_buf+(0x1000*idx), buf, sizeof(unsigned char)*size, cudaMemcpyHostToDevice);
	cudaMemcpy(d_pkt_buffer+(512*0x1000)+(0x1000*idx), buf, sizeof(unsigned char)*size, cudaMemcpyHostToDevice);
	print_gpu<<<1,1>>>(d_pkt_buffer+(512*0x1000)+(0x1000*idx), sizeof(unsigned char)*size);
	//printf("p_buf->rx_buf: %p\n", p_buf->rx_buf);
	//cudaMemcpy(p_buf->rx_buf, buf, sizeof(unsigned char)*size, cudaMemcpyHostToDevice);
	idx++;
	if(idx == 512)
		idx = 0;
	printf("____2__________copy_to_gpu____\n");
}

extern "C"
void set_gpu_mem_for_dpdk(void)
{
	size_t _pkt_buffer_size = 2*512*4096; // 4MB, for rx,tx ring
	size_t pkt_buffer_size = (_pkt_buffer_size + GPU_PAGE_SIZE - 1) & GPU_PAGE_MASK;
	
  ASSERTRT(cudaMalloc((void**)&d_pkt_buffer, pkt_buffer_size));
  ASSERTRT(cudaMemset(d_pkt_buffer, 0, pkt_buffer_size));

	ASSERTRT(cudaMalloc((void**)&pkt_cnt, sizeof(int)*2));
  ASSERTRT(cudaMalloc((void**)&pkt_size, sizeof(int)));
  ASSERTRT(cudaMalloc((void**)&p_buf, sizeof(struct pkt_buf)));
  ASSERTRT(cudaMalloc((void**)&ctr, sizeof(unsigned int)));


	ASSERT_CUDA(cudaMemset(pkt_cnt, 0, sizeof(int)*2));
	ASSERT_CUDA(cudaMemset(pkt_size, 0, sizeof(int)));
	ASSERT_CUDA(cudaMemset(p_buf, 0, sizeof(struct pkt_buf)));
	ASSERT_CUDA(cudaMemset(ctr, 0, sizeof(unsigned int)));

  clean_buffer<<< 1, 1 >>> (d_pkt_buffer, pkt_buffer_size, p_buf);

	START_GRN
	printf("[Done]____GPU mem set for dpdk__\n");
	END
}
