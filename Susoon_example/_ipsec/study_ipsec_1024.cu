#include "ipsec.h"
#include "packet_man.h"
#include "gdnio.h"

#define TOTAL_T_NUM 11 * 63 * 16
#define AES_T_NUM 63
#define PPB 16
#define HMAC_T_NUM 16
#define PKT_SIZE 1024
#define PAD_LEN 0

__device__ void sha1_kernel_global_1024(unsigned char *data, sha1_gpu_context *ctx, unsigned int *extended, int len, int pkt_idx)
{
	int thread_index = threadIdx.x%94;
	
	if(thread_index >= HMAC_T_NUM)
		return;

	int e_index = thread_index * 80;
	int block_index = thread_index * 64;
	unsigned int temp, t;

	if(thread_index == 0){
		/* Initialization vector for SHA-1 */
		ctx->state[0] = 0x67452301;           
		ctx->state[1] = 0xEFCDAB89;           
		ctx->state[2] = 0x98BADCFE;           
		ctx->state[3] = 0x10325476;           
		ctx->state[4] = 0xC3D2E1F0; 
	}
	__syncthreads();

	/*
	 * Extend 32 block byte block into 80 byte block.
	 */

//sh_kim 20.03.11 : when data length is 20byte, we need padding
	if(len == 20 && threadIdx.x = 0)
	{
		memset(data + len - 1, 0, 44);
	}

	GET_UINT32_BE( extended[pkt_idx*e_index + 0], data + block_index,  0 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 1], data + block_index,  4 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 2], data + block_index,  8 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 3], data + block_index, 12 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 4], data + block_index, 16 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 5], data + block_index, 20 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 6], data + block_index, 24 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 7], data + block_index, 28 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 8], data + block_index, 32 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 9], data + block_index, 36 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 10], data + block_index, 40 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 11], data + block_index, 44 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 12], data + block_index, 48 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 13], data + block_index, 52 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 14], data + block_index, 56 );
	GET_UINT32_BE( extended[pkt_idx*e_index + 15], data + block_index, 60 );

	// Same as "blk(i)" macro in openssl source.
	for (t = 16; t < 80; t++) {
		temp = extended[pkt_idx*e_index + t - 3] ^ extended[pkt_idx*e_index + t - 8] ^ extended[pkt_idx*e_index + t - 14] ^ extended[pkt_idx*e_index + t - 16];
		extended[pkt_idx*e_index + t] = S(temp,1);
	}

	__syncthreads();
	if(thread_index == 0){
		for(t = 0; t < HMAC_T_NUM; t++) 
			sha1_gpu_process(ctx, (unsigned int*)&extended[pkt_idx * t * 80]);
	}
}

//CKJUNG, ipsec_1024 ver.
__global__ void nf_ipsec_1024(struct pkt_buf *p_buf, int* pkt_cnt, unsigned int* ctr, unsigned char* d_nounce, unsigned int* d_key, unsigned char* d_sbox, unsigned char* d_GF2, int chain_seq, unsigned int* seq, unsigned int* extended)
{
	// <<< 11, 1008 >>> threads. 
	//	63 threads for 1 pkt. (102B pkt)
	// 1008 / 63 = 16, 1TB has 1008 threads each and manages 16 pkts.
	unsigned int tid = blockDim.x * blockIdx.x + threadIdx.x;
	unsigned int cur_tid = threadIdx.x / AES_T_NUM;
	// 11 x 1008 = 11,088
	// tid : 0 - 11,087 (10,087 threads)

	__shared__ unsigned char IV[PPB][16];
	__shared__ unsigned char aes_tmp[PPB][16*AES_T_NUM]; 
	__shared__ unsigned char rot_index; // This index is updated by "the last thread" of each TB to move forward to the NEXT 256 desc.
	// rot_index (0 - 2): {0 x 171(0) ~ 2 x 171(342)} + 170  == 0 ~ 511
	// IV : 16 * 16 =  256
	// aes_tmp : 16 * 16 * 63 = 16,128
	// ictx : 16 * 16 = 256
	// octx : 16 * 16 = 256
	// rot_index : 1
	//-------------------------- Total __shared__ mem Usage : 16,897 / 49,152 (48KB per TB)

	if(threadIdx.x == 0) // The first thread of EACH TB initialize rot_index(rotation_index) to "0". 
		rot_index = 0;

	if(tid == TOTAL_T_NUM - 1){
		START_RED
		printf("tid %d is alive!\n", tid);
		END
	}

	__syncthreads();

	while(true){ // Persistent Kernel (for every threads)
		// 63-threads to be grouped. 
		if(tid < 171*AES_T_NUM && (rot_index == 2 && tid < 171 * AES_T_NUM - 1)){ // Beyond this idx could exceed "rx_buf" boundary.
			//-------------------------- Multi threads Job --------------------------------------------
			if(readNoCache(&p_buf->rx_buf_idx[tid/AES_T_NUM + rot_index*171]) == chain_seq){

				//-------------------------- Single threads Job --------------------------------------------
				if(tid % AES_T_NUM == 0){ 
					///////////////////// ESP Tailer, padlen, next-hdr /////////////////////////
					int i;
					for(i = 1; i <= 6; i++)
						p_buf->rx_buf[0x1000 * (tid/AES_T_NUM + rot_index*171) + i] = 0; // padding
					
					p_buf->rx_buf[0x1000 * (tid/AES_T_NUM + rot_index*171) + 1510 + 6] = 6; // padlen 

					p_buf->rx_buf[0x1000 * (tid/AES_T_NUM + rot_index*171) + 1510 + 6 + 1] = IPPROTO_IPIP; // next-hdr (Meaning "IP within IP)

					/* For Reference...
						 IPPROTO_IP = 0
						 IPPROTO_ICMP = 1
						 IPPROTO_IPIP = 4
						 IPPROTO_TCP = 6
						 IPPROTO_UDP = 17
						 IPPROTO_ESP = 50
					 */
					atomicAdd(ctr, 1); // same "ctr" value for grouped 63-threads. (counter) AES-CTR Mode
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

					for(int i = 1; i < 10; i++)
					{
						SubBytes(IV[cur_tid], d_sbox);
						ShiftRows(IV[cur_tid]);
						MixColumns(IV[cur_tid], d_GF2, tmp);
						AddRoundKey(IV[cur_tid], &d_key[4 * i]);
					}
					SubBytes(IV[cur_tid], d_sbox);
					ShiftRows(IV[cur_tid]);
					AddRoundKey(IV[cur_tid], &d_key[4 * 10]);
				}
				__syncthreads();
				//-------------------------- Multi threads Job --------------------------------------------
				////////////////// Locating AES Encrypted parts into a pkt  ///////////////////////////////
				for(int i = 0; i < 16; i++){
					aes_tmp[cur_tid][((tid%AES_T_NUM)*16) + i] = p_buf->rx_buf[(0x1000 * (tid/AES_T_NUM + rot_index*171)) + sizeof(struct ethhdr) + ((tid%AES_T_NUM) * 16) + i] ^ IV[cur_tid][i];
				}
				for(int i = 0; i < 16; i++){
					p_buf->rx_buf[(0x1000 * (tid/AES_T_NUM + rot_index*171)) + sizeof(struct ethhdr) + sizeof(struct iphdr) + sizeof(struct esphdr) + ((tid%AES_T_NUM) * 16) + i] = aes_tmp[cur_tid][((tid%AES_T_NUM)*16) + i]; 
				}
				__syncthreads();
#if 1
				//-------------------------- Single threads Job --------------------------------------------
				if(tid % AES_T_NUM == 0){
					//////////// Proto_type = ESP set! ///////////
					p_buf->rx_buf[0x1000 * (tid/AES_T_NUM + rot_index*171) + sizeof(struct ethhdr) + 9] = IPPROTO_ESP; // IPPROTO_ESP = 50
					struct ethhdr* ethh;
					struct iphdr* iph;
					struct esphdr* esph;

					ethh = (struct ethhdr *)&p_buf->rx_buf[0x1000 * (tid/AES_T_NUM + rot_index*171)];
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
				}
				__syncthreads();
#endif
					// CKJUNG, HMAC-SHA1 From here! /////////////////////////////
					// RFC 2104, H(K XOR opad, H(K XOR ipad, text))
					/**** Inner Digest ****/
					// H(K XOR ipad, text) : 64 Bytes
					sha1_kernel_global_1024(&p_buf->rx_buf[(0x1000 * (tid/AES_T_NUM + rot_index*171)) + sizeof(struct ethhdr) + sizeof(struct iphdr)], &ictx[cur_tid], extended, 64, (tid/AES_T_NUM + rot_index*171));
					/**** Outer Digest ****/
					// H(K XOR opad, H(K XOR ipad, text)) : 20 Bytes
					sha1_kernel_global_1024(&(ictx[cur_tid].c_state[0]), &octx[cur_tid], extended, 20, (tid/AES_T_NUM + rot_index*171));
			
				//-------------------------- Single threads Job --------------------------------------------
				if(tid % AES_T_NUM == 0){
					atomicAdd(&pkt_cnt[1], 1);	
					p_buf->rx_buf_idx[tid/AES_T_NUM + rot_index*171] = chain_seq+1;
					if(tid/AES_T_NUM == 255)
						rot_index += 1;
					if(rot_index == 3)
						rot_index = 0;
				}
			}
		}
		__syncthreads();
	}
}
