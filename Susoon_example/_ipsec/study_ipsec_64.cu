#include "ipsec.h"
#include "packet_man.h"
#include "gdnio.h"

#define TOTAL_T_NUM 4 * 3 * 128
#define AES_T_NUM 3
#define PPB 128
#define HMAC_T_NUM 1
#define PKT_SIZE 64
#define PAD_LEN 0

__device__ void sha1_kernel_global_64(unsigned char *data, sha1_gpu_context *ctx, uint32_t *extended, int len)
{
#if 1
	/* Initialization vector for SHA-1 */
	ctx->state[0] = 0x67452301;           
	ctx->state[1] = 0xEFCDAB89;           
	ctx->state[2] = 0x98BADCFE;           
	ctx->state[3] = 0x10325476;           
	ctx->state[4] = 0xC3D2E1F0;           
#endif

	uint32_t temp, t;

	/*
	 * Extend 32 block byte block into 80 byte block.
	 */

//sh_kim 20.03.11 : when data length is 20byte, we need padding
	if(len == 20)
	{
		memset(data + len - 1, 0, 44);
	}

	GET_UINT32_BE( extended[0], data,  0 );
	GET_UINT32_BE( extended[1], data,  4 );
	GET_UINT32_BE( extended[2], data,  8 );
	GET_UINT32_BE( extended[3], data, 12 );
	GET_UINT32_BE( extended[4], data, 16 );
	GET_UINT32_BE( extended[5], data, 20 );
	GET_UINT32_BE( extended[6], data, 24 );
	GET_UINT32_BE( extended[7], data, 28 );
	GET_UINT32_BE( extended[8], data, 32 );
	GET_UINT32_BE( extended[9], data, 36 );
	GET_UINT32_BE( extended[10], data, 40 );
	GET_UINT32_BE( extended[11], data, 44 );
	GET_UINT32_BE( extended[12], data, 48 );
	GET_UINT32_BE( extended[13], data, 52 );
	GET_UINT32_BE( extended[14], data, 56 );
	GET_UINT32_BE( extended[15], data, 60 );

	// Same as "blk(i)" macro in openssl source.
	for (t = 16; t < 80; t++) {
		temp = extended[t - 3] ^ extended[t - 8] ^ extended[t - 14] ^ extended[t - 16];
		extended[t] = S(temp,1);
	}

	sha1_gpu_process(ctx, extended);
}

// CKJUNG, 18.10.26 [NF#2:IPSec]-------------------------------------
__global__ void nf_ipsec_64(struct pkt_buf *p_buf, int* pkt_cnt, unsigned int* ctr, unsigned char* d_nounce, unsigned int* d_key, unsigned char* d_sbox, unsigned char* d_GF2, int chain_seq, unsigned int* seq)
{
	// <<< 4, 384 >>> threads. 
	//	3 threads for 1 pkt. (60B pkt)
	// 384 / 3 = 128, 1TB has 384 threads each and manages 128 pkts.
	unsigned int tid = blockDim.x * blockIdx.x + threadIdx.x;
	unsigned int cur_tid = threadIdx.x / AES_T_NUM;
	// tid : 0 - 1,535 (1,536 threads) = 512 * 3

	__shared__ unsigned char IV[PPB][16];
	__shared__ unsigned char aes_tmp[PPB][16*AES_T_NUM]; 
	__shared__ sha1_gpu_context ictx[PPB];
	__shared__ sha1_gpu_context octx[PPB];
	// IV : 128 * 16 =  2,048 
	// aes_tmp : 128 * 16 * 3 = 6,144
	// ictx : 24 * 128 = 3,072
	// octx : 24 * 128 = 3,072
	// pkt_len : 4 * 128 = 512
	//-------------------------- Total __shared__ mem Usage : 14,336 + 512

	if(tid == TOTAL_T_NUM - 1){
		START_RED
		printf("[%s] tid %d is alive!\n", __FUNCTION__, tid);
		END
	}

	__syncthreads();
	while(true){ // Persistent Kernel (for every threads)
		// 3-threads to be grouped. ex) 0,1,2 --> idx 0; 3,4,5 --> idx 1; ...
		//-------------------------- Multi threads Job --------------------------------------------
		__syncthreads();
		if(readNoCache(&p_buf->rx_buf_idx[tid/AES_T_NUM]) == chain_seq){
			//-------------------------- Single threads Job --------------------------------------------
			//__syncthreads();
#if 1
			if(tid % AES_T_NUM == 0){
				p_buf->rx_buf[0x1000 * (tid/AES_T_NUM) + (PKT_SIZE - 4)] = 0; // padlen 
				p_buf->rx_buf[0x1000 * (tid/AES_T_NUM) + (PKT_SIZE - 4) + 1] = IPPROTO_IPIP; // next-hdr (Meaning "IP within IP)
				/* For Reference...
					 IPPROTO_IP = 0
					 IPPROTO_ICMP = 1
					 IPPROTO_IPIP = 4
					 IPPROTO_TCP = 6
					 IPPROTO_UDP = 17
					 IPPROTO_ESP = 50
				 */
				atomicAdd(ctr, 1); // same "ctr" value for grouped 3-threads. (counter) AES-CTR Mode
				IV[cur_tid][15] = *ctr & 0xFF;
				IV[cur_tid][14] = (*ctr >> 8) & 0xFF; // CKJUNG, 1 Byte = 8bits means, Octal notation
				IV[cur_tid][13] = (*ctr >> 16) & 0xFF;
				IV[cur_tid][12] = (*ctr >> 24) & 0xFF;
				for(int i = 0; i < 12; i++)
					IV[cur_tid][i] = 0;

				// Copy our state into private memory
				unsigned char temp, temp2;
				unsigned char overflow = 0;
				char tmp[16];
				for(int i = 15; i != -1; i--) {
					temp = d_nounce[i];
					temp2 = IV[cur_tid][i];
					IV[cur_tid][i] += temp + overflow;
					overflow = ((int)temp2 + (int)temp + (int)overflow > 255);
				}

				AddRoundKey(IV[cur_tid], &d_key[0]);

#if 1
				for(int i = 1; i < 10; i++)
				{
					SubBytes(IV[cur_tid], d_sbox);
					ShiftRows(IV[cur_tid]);
					MixColumns(IV[cur_tid], d_GF2, tmp);
					AddRoundKey(IV[cur_tid], &d_key[4 * i]);
				}
#endif
				SubBytes(IV[cur_tid], d_sbox);
				ShiftRows(IV[cur_tid]);
				AddRoundKey(IV[cur_tid], &d_key[4 * 10]);
			}
#endif
			__syncthreads();
			//-------------------------- Multi threads Job --------------------------------------------
			////////////////// Locating AES Encrypted parts into a pkt  ///////////////////////////////
			for(int i = 0; i < 16; i++){
				aes_tmp[cur_tid][((tid%AES_T_NUM)*16) + i] = p_buf->rx_buf[(0x1000 * (tid/AES_T_NUM)) + sizeof(struct ethhdr) + ((tid%AES_T_NUM) * 16) + i] ^ IV[cur_tid][i];
			}
			for(int i = 0; i < 16; i++){
				p_buf->rx_buf[(0x1000 * (tid/AES_T_NUM)) + sizeof(struct ethhdr) + sizeof(struct iphdr) + sizeof(struct esphdr) + ((tid%AES_T_NUM) * 16) + i] = aes_tmp[cur_tid][((tid%AES_T_NUM)*16) + i]; 
			}
			__syncthreads();
#if 1
			//-------------------------- Single threads Job --------------------------------------------
			if(tid % AES_T_NUM == 0){
				//////////// Proto_type = ESP set! ///////////
				p_buf->rx_buf[0x1000 * (tid/AES_T_NUM) + sizeof(struct ethhdr) + 9] = IPPROTO_ESP; // IPPROTO_ESP = 50
				struct ethhdr* ethh;
				struct iphdr* iph;
				struct esphdr* esph;

				ethh = (struct ethhdr *)&p_buf->rx_buf[0x1000 * (tid/AES_T_NUM)];
				iph = (struct iphdr *)(ethh + 1);
				esph = (struct esphdr *)((uint32_t *)iph + iph->ihl);

				// SPI (Security Parameter Index)
				uint32_t spi = 1085899777;
				HTONS32(spi);

				////////// Set ESP header SPI value ///////////////////
				memcpy(&esph->spi, &spi, 4);
				atomicAdd(seq, 1);

				//////////// Set ESP header SEQ value //////////
				memcpy(&esph->seq, seq, 4);

				// CKJUNG, HMAC-SHA1 From here! /////////////////////////////
				// RFC 2104, H(K XOR opad, H(K XOR ipad, text))
				/**** Inner Digest ****/
				// H(K XOR ipad, text) : 64 Bytes
				uint32_t extended[80];
				sha1_gpu_context ictx;

				sha1_kernel_global_64(&p_buf->rx_buf[(0x1000 * (tid/AES_T_NUM)) + sizeof(struct ethhdr) + sizeof(struct iphdr)], &ictx, extended, 64);
				/**** Outer Digest ****/
				// H(K XOR opad, H(K XOR ipad, text)) : 20 Bytes
				sha1_kernel_global_64(&(ictx.c_state[0]), &octx[cur_tid], extended, 20);
			}
#endif
			__syncthreads();
			//-------------------------- Multi threads Job --------------------------------------------
			// Attach 20-bytes HMAC-SHA authentication digest to packet.
			memcpy(&p_buf->rx_buf[0x1000 * (tid/AES_T_NUM) + 90 + ((tid%AES_T_NUM) * 8)], &(octx[cur_tid].c_state[((tid%AES_T_NUM)*8)]), 8);
			__syncthreads();
			//-------------------------- Single threads Job --------------------------------------------
			if(tid % AES_T_NUM == 0){
				atomicAdd(&pkt_cnt[1], 1);	
				p_buf->rx_buf_idx[tid/AES_T_NUM] = chain_seq+1;
			}
		}
	}
}
