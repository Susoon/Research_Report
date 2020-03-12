#include "ipsec.h"
#include "packet_man.h"
#include "gdnio.h"

extern struct pkt_buf *p_buf;
extern int *pkt_cnt;
extern unsigned int *ctr;

__device__ void AddRoundKey(unsigned char *state, unsigned *w)
{
	int i;                                                              
	for(i = 0; i < BLOCK_SIZE; i++) { // column
		state[i * 4 + 0] = state[i * 4 + 0] ^ ((w[i] >> (8 * 3)) & 0xFF);
		state[i * 4 + 1] = state[i * 4 + 1] ^ ((w[i] >> (8 * 2)) & 0xFF);
		state[i * 4 + 2] = state[i * 4 + 2] ^ ((w[i] >> (8 * 1)) & 0xFF);
		state[i * 4 + 3] = state[i * 4 + 3] ^ ((w[i] >> (8 * 0)) & 0xFF);
	}                                                                   
}

__device__ void SubBytes(unsigned char *state, unsigned char* sbox) //state = 16 chars
{ 
	int i;
	for(i = 0; i < 4 * BLOCK_SIZE; i++) {
		state[i] = sbox[state[i]];
	}
} 

__device__ void ShiftRows(unsigned char *state)
{ 
	// NOTE: For whatever reason the standard uses column-major ordering ?
	// 0 1 2 3 --> 0 1 2 3  | 0  4  8  12 --> 0   4  8 12
	// 0 1 2 3 --> 1 2 3 0  | 1  5  9  13 --> 5   9 13  1
	// 0 1 2 3 --> 2 3 0 1  | 2  6  10 14 --> 10 14  2  6
	// 0 1 2 3 --> 3 0 1 2  | 3  7  11 15 --> 15  3  7 11
	unsigned char temp = state[1];

	state[1] = state[5];
	state[5] = state[9];
	state[9] = state[13];
	state[13] = temp;

	temp = state[2];
	state[2] = state[10];
	state[10] = temp;
	temp = state[6];
	state[6] = state[14];
	state[14] = temp;

	temp = state[3];
	state[3] = state[15];
	state[15] = state[11];
	state[11] = state[7];
	state[7] = temp;
}

// See "Efficient Software Implementation of AES on 32-bit platforms"
__device__ void MixColumns(unsigned char *state, unsigned char* GF_2, char* s) 
{
//[TODO] malloc!!!!!! is the criminal!!! CKJUNG, 18.10.26 
	memcpy(s, state, 4 * BLOCK_SIZE);
	int i;
#if 1
	for(i = 0; i < BLOCK_SIZE; i++) { // column
		unsigned char * x = (unsigned char*)&s[i*4];
		unsigned char * y = (unsigned char*)&state[i*4];
		y[0] = x[1] ^ x[2] ^ x[3];
		y[1] = x[0] ^ x[2] ^ x[3];
		y[2] = x[0] ^ x[1] ^ x[3];
		y[3] = x[0] ^ x[1] ^ x[2];
		x[0] = GF_2[x[0]];
		x[1] = GF_2[x[1]];
		x[2] = GF_2[x[2]];
		x[3] = GF_2[x[3]];
		y[0] ^= x[0] ^ x[1];
		y[1] ^= x[1] ^ x[2];
		y[2] ^= x[2] ^ x[3];
		y[3] ^= x[3] ^ x[0];
	}
#endif
} 

/**                                           
 * Initialize new context                      
 *                                             
 * @param context SHA1-Context                 
 */                                            
/*
 * Process extended block.
 */
__device__ void sha1_gpu_process (sha1_gpu_context *ctx, uint32_t W[80])
{
	uint32_t A, B, C, D, E;
	A = ctx->state[0];
	B = ctx->state[1];
	C = ctx->state[2];
	D = ctx->state[3];
	E = ctx->state[4];

#define P(a,b,c,d,e,x)\
{\
	e += S(a,5) + F(b,c,d) + K + x; b = S(b,30);\
}


#define F(x,y,z) (z ^ (x & (y ^ z)))
#define K 0x5A827999

	P( A, B, C, D, E, W[0]  );
	P( E, A, B, C, D, W[1]  );
	P( D, E, A, B, C, W[2]  );
	P( C, D, E, A, B, W[3]  );
	P( B, C, D, E, A, W[4]  );
	P( A, B, C, D, E, W[5]  );
	P( E, A, B, C, D, W[6]  );
	P( D, E, A, B, C, W[7]  );
	P( C, D, E, A, B, W[8]  );
	P( B, C, D, E, A, W[9]  );
	P( A, B, C, D, E, W[10] );
	P( E, A, B, C, D, W[11] );
	P( D, E, A, B, C, W[12] );
	P( C, D, E, A, B, W[13] );
	P( B, C, D, E, A, W[14] );
	P( A, B, C, D, E, W[15] );
	P( E, A, B, C, D, W[16] );
	P( D, E, A, B, C, W[17] );
	P( C, D, E, A, B, W[18] );
	P( B, C, D, E, A, W[19] );

#undef K
#undef F

#define F(x,y,z) (x ^ y ^ z)
#define K 0x6ED9EBA1

	P( A, B, C, D, E, W[20] );
	P( E, A, B, C, D, W[21] );
	P( D, E, A, B, C, W[22] );
	P( C, D, E, A, B, W[23] );
	P( B, C, D, E, A, W[24] );
	P( A, B, C, D, E, W[25] ); // w[25] is the problem.
	P( E, A, B, C, D, W[26] );
	P( D, E, A, B, C, W[27] );
	P( C, D, E, A, B, W[28] );
	P( B, C, D, E, A, W[29] );
	P( A, B, C, D, E, W[30] );
	P( E, A, B, C, D, W[31] );
	P( D, E, A, B, C, W[32] );
	P( C, D, E, A, B, W[33] );
	P( B, C, D, E, A, W[34] );
	P( A, B, C, D, E, W[35] );
	P( E, A, B, C, D, W[36] );
	P( D, E, A, B, C, W[37] );
	P( C, D, E, A, B, W[38] );
	P( B, C, D, E, A, W[39] );


#undef K
#undef F

#define F(x,y,z) ((x & y) | (z & (x | y)))
#define K 0x8F1BBCDC

	P( A, B, C, D, E, W[40] );
	P( E, A, B, C, D, W[41] );
	P( D, E, A, B, C, W[42] );
	P( C, D, E, A, B, W[43] );
	P( B, C, D, E, A, W[44] );
	P( A, B, C, D, E, W[45] );
	P( E, A, B, C, D, W[46] );
	P( D, E, A, B, C, W[47] );
	P( C, D, E, A, B, W[48] );
	P( B, C, D, E, A, W[49] );
	P( A, B, C, D, E, W[50] );
	P( E, A, B, C, D, W[51] );
	P( D, E, A, B, C, W[52] );
	P( C, D, E, A, B, W[53] );
	P( B, C, D, E, A, W[54] );
	P( A, B, C, D, E, W[55] );
	P( E, A, B, C, D, W[56] );
	P( D, E, A, B, C, W[57] );
	P( C, D, E, A, B, W[58] );
	P( B, C, D, E, A, W[59] );

#undef K
#undef F

#define F(x,y,z) (x ^ y ^ z)
#define K 0xCA62C1D6

	P( A, B, C, D, E, W[60] );
	P( E, A, B, C, D, W[61] );
	P( D, E, A, B, C, W[62] );
	P( C, D, E, A, B, W[63] );
	P( B, C, D, E, A, W[64] );
	P( A, B, C, D, E, W[65] );
	P( E, A, B, C, D, W[66] );
	P( D, E, A, B, C, W[67] );
	P( C, D, E, A, B, W[68] );
	P( B, C, D, E, A, W[69] );
	P( A, B, C, D, E, W[70] );
	P( E, A, B, C, D, W[71] );
	P( D, E, A, B, C, W[72] );
	P( C, D, E, A, B, W[73] );
	P( B, C, D, E, A, W[74] );
	P( A, B, C, D, E, W[75] );
	P( E, A, B, C, D, W[76] );
	P( D, E, A, B, C, W[77] );
	P( C, D, E, A, B, W[78] );
	P( B, C, D, E, A, W[79] );
#undef K
#undef F

	ctx->state[0] += A;
	ctx->state[1] += B;
	ctx->state[2] += C;
	ctx->state[3] += D;
	ctx->state[4] += E;
}


__device__ void sha1_kernel_global_1514(unsigned char *data, sha1_gpu_context *ctx, unsigned int *extended, int len, int pkt_idx)
{
	int thread_index = threadIdx.x%94;
	
	if(thread_index >= 24)
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
		for(t = 0; t < 24; t++) 
			sha1_gpu_process(ctx, (unsigned int*)&extended[pkt_idx * t * 80]);
	}
}


__device__ void sha1_kernel_global(unsigned char *data, sha1_gpu_context *ctx, uint32_t *extended, int len)
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
	// tid : 0 - 1,535 (1,536 threads) = 512 * 3

	__shared__ unsigned char IV[128][16];
	__shared__ unsigned char aes_tmp[128][16*3]; 
	__shared__ sha1_gpu_context octx[128];
	// IV : 128 * 16 =  2,048 
	// aes_tmp : 128 * 16 * 3 = 6,144
	// ictx : 24 * 128 = 3,072
	// octx : 24 * 128 = 3,072
	// pkt_len : 4 * 128 = 512
	//-------------------------- Total __shared__ mem Usage : 14,336 + 512

	if(tid == 1535){
		START_RED
		printf("[%s] tid %d is alive!\n", __FUNCTION__, tid);
		END
	}

	__syncthreads();
	while(true){ // Persistent Kernel (for every threads)
		// 3-threads to be grouped. ex) 0,1,2 --> idx 0; 3,4,5 --> idx 1; ...
		//-------------------------- Multi threads Job --------------------------------------------
		__syncthreads();
		if(readNoCache(&p_buf->rx_buf_idx[tid/3]) == chain_seq){
			//-------------------------- Single threads Job --------------------------------------------
			//__syncthreads();
#if 1
			if(tid % 3 == 0){
				p_buf->rx_buf[0x1000 * (tid/3) + 60] = 0; // padlen 
				p_buf->rx_buf[0x1000 * (tid/3) + 60 + 1] = IPPROTO_IPIP; // next-hdr (Meaning "IP within IP)
				/* For Reference...
					 IPPROTO_IP = 0
					 IPPROTO_ICMP = 1
					 IPPROTO_IPIP = 4
					 IPPROTO_TCP = 6
					 IPPROTO_UDP = 17
					 IPPROTO_ESP = 50
				 */
				atomicAdd(ctr, 1); // same "ctr" value for grouped 3-threads. (counter) AES-CTR Mode
				IV[threadIdx.x/3][15] = *ctr & 0xFF;
				IV[threadIdx.x/3][14] = (*ctr >> 8) & 0xFF; // CKJUNG, 1 Byte = 8bits means, Octal notation
				IV[threadIdx.x/3][13] = (*ctr >> 16) & 0xFF;
				IV[threadIdx.x/3][12] = (*ctr >> 24) & 0xFF;
				for(int i = 0; i < 12; i++)
					IV[threadIdx.x/3][i] = 0;

				// Copy our state into private memory
				unsigned char temp, temp2;
				unsigned char overflow = 0;
				char tmp[16];
				for(int i = 15; i != -1; i--) {
					temp = d_nounce[i];
					temp2 = IV[threadIdx.x/3][i];
					IV[threadIdx.x/3][i] += temp + overflow;
					overflow = ((int)temp2 + (int)temp + (int)overflow > 255);
				}

				AddRoundKey(IV[threadIdx.x/3], &d_key[0]);

#if 1
				for(int i = 1; i < 10; i++)
				{
					SubBytes(IV[threadIdx.x/3], d_sbox);
					ShiftRows(IV[threadIdx.x/3]);
					MixColumns(IV[threadIdx.x/3], d_GF2, tmp);
					AddRoundKey(IV[threadIdx.x/3], &d_key[4 * i]);
				}
#endif
				SubBytes(IV[threadIdx.x/3], d_sbox);
				ShiftRows(IV[threadIdx.x/3]);
				AddRoundKey(IV[threadIdx.x/3], &d_key[4 * 10]);
			}
#endif
			__syncthreads();
			//-------------------------- Multi threads Job --------------------------------------------
			////////////////// Locating AES Encrypted parts into a pkt  ///////////////////////////////
			for(int i = 0; i < 16; i++){
				aes_tmp[threadIdx.x/3][((tid%3)*16) + i] = p_buf->rx_buf[(0x1000 * (tid/3)) + sizeof(struct ethhdr) + ((tid%3) * 16) + i] ^ IV[threadIdx.x/3][i];
			}
			for(int i = 0; i < 16; i++){
				p_buf->rx_buf[(0x1000 * (tid/3)) + sizeof(struct ethhdr) + sizeof(struct iphdr) + sizeof(struct esphdr) + ((tid%3) * 16) + i] = aes_tmp[threadIdx.x/3][((tid%3)*16) + i]; 
			}
			__syncthreads();
#if 1
			//-------------------------- Single threads Job --------------------------------------------
			if(tid % 3 == 0){
				//////////// Proto_type = ESP set! ///////////
				p_buf->rx_buf[0x1000 * (tid/3) + sizeof(struct ethhdr) + 9] = IPPROTO_ESP; // IPPROTO_ESP = 50
				struct ethhdr* ethh;
				struct iphdr* iph;
				struct esphdr* esph;

				ethh = (struct ethhdr *)&p_buf->rx_buf[0x1000 * (tid/3)];
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

				sha1_kernel_global(&p_buf->rx_buf[(0x1000 * (tid/3)) + sizeof(struct ethhdr) + sizeof(struct iphdr)], &ictx, extended, 64);
				/**** Outer Digest ****/
				// H(K XOR opad, H(K XOR ipad, text)) : 20 Bytes
				sha1_kernel_global(&(ictx.c_state[0]), &octx[threadIdx.x/3], extended, 20);
			}
#endif
			__syncthreads();
			//-------------------------- Multi threads Job --------------------------------------------
			// Attach 20-bytes HMAC-SHA authentication digest to packet.
			memcpy(&p_buf->rx_buf[0x1000 * (tid/3) + 90 + ((tid%3) * 8)], &(octx[threadIdx.x/3].c_state[((tid%3)*8)]), 8);
			__syncthreads();
			//-------------------------- Single threads Job --------------------------------------------
			if(tid % 3 == 0){
				atomicAdd(&pkt_cnt[1], 1);	
				p_buf->rx_buf_idx[tid/3] = chain_seq+1;
			}
		}
	}
}

//CKJUNG, ipsec_1514 ver.
__global__ void nf_ipsec_1514(struct pkt_buf *p_buf, int* pkt_cnt, unsigned int* ctr, unsigned char* d_nounce, unsigned int* d_key, unsigned char* d_sbox, unsigned char* d_GF2, int chain_seq, unsigned int* seq, unsigned int* extended)
{
	// <<< 13, 940 >>> threads. 
	//	94 threads for 1 pkt. (1510B pkt)
	// 940 / 94 = 10, 1TB has 940 threads each and manages 10 pkts.
	unsigned int tid = blockDim.x * blockIdx.x + threadIdx.x;
	// 13 x 940 = 12,220
	// tid : 0 - 12,219 (12,220 threads)

	__shared__ unsigned char IV[10][16];
	__shared__ unsigned char aes_tmp[10][16*94]; 
	__shared__ unsigned char rot_index; // This index is updated by "the last thread" of each TB to move forward to the NEXT 128 desc.
	// rot_index (0 - 3): {0 x 128(0) ~ 3 x 128(384)} + 127  == 0 ~ 511
	// IV : 10 * 16 =  160
	// aes_tmp : 10 * 16 * 94 = 15,040
	// ictx : 24 * 10 = 240
	// octx : 24 * 10 = 240
	// rot_index : 1
	//-------------------------- Total __shared__ mem Usage : 15,681 / 49,152 (48KB per TB)

	if(threadIdx.x == 0) // The first thread of EACH TB initialize rot_index(rotation_index) to "0". 
		rot_index = 0;

	if(tid == 12219){
		START_RED
		printf("tid %d is alive!\n", tid);
		END
	}

	__syncthreads();

	while(true){ // Persistent Kernel (for every threads)
		// 94-threads to be grouped. 
		if(tid < 128*94){ // Beyond this idx could exceed "rx_buf" boundary.
			//-------------------------- Multi threads Job --------------------------------------------
			if(readNoCache(&p_buf->rx_buf_idx[tid/94 + rot_index*128]) == chain_seq){

				//-------------------------- Single threads Job --------------------------------------------
				if(tid % 94 == 0){ 
					///////////////////// ESP Tailer, padlen, next-hdr /////////////////////////
					int i;
					for(i = 1; i <= 6; i++)
						p_buf->rx_buf[0x1000 * (tid/94 + rot_index*128) + i] = 0; // padding
					
					p_buf->rx_buf[0x1000 * (tid/94 + rot_index*128) + 1510 + 6] = 6; // padlen 

					p_buf->rx_buf[0x1000 * (tid/94 + rot_index*128) + 1510 + 6 + 1] = IPPROTO_IPIP; // next-hdr (Meaning "IP within IP)

					/* For Reference...
						 IPPROTO_IP = 0
						 IPPROTO_ICMP = 1
						 IPPROTO_IPIP = 4
						 IPPROTO_TCP = 6
						 IPPROTO_UDP = 17
						 IPPROTO_ESP = 50
					 */
					atomicAdd(ctr, 1); // same "ctr" value for grouped 4-threads. (counter) AES-CTR Mode
					IV[threadIdx.x/94][15] = *ctr & 0xFF;
					IV[threadIdx.x/94][14] = (*ctr >> 8) & 0xFF; // CKJUNG, 1 Byte = 8bits means, Octal notation
					IV[threadIdx.x/94][13] = (*ctr >> 16) & 0xFF;
					IV[threadIdx.x/94][12] = (*ctr >> 24) & 0xFF;
					for(int i = 0; i < 12; i++)
						IV[threadIdx.x/94][i] = 0;

					// Copy our state into private memory
					unsigned char temp, temp2;
					unsigned char overflow = 0;
					char tmp[16];
					for(int i = 15; i != -1; i--) {
						temp = d_nounce[i];
						temp2 = IV[threadIdx.x/94][i];
						IV[threadIdx.x/94][i] += temp + overflow;
						overflow = ((int)temp2 + (int)temp + (int)overflow > 255);
					}

					AddRoundKey(IV[threadIdx.x/94], &d_key[0]);

					for(int i = 1; i < 10; i++)
					{
						SubBytes(IV[threadIdx.x/94], d_sbox);
						ShiftRows(IV[threadIdx.x/94]);
						MixColumns(IV[threadIdx.x/94], d_GF2, tmp);
						AddRoundKey(IV[threadIdx.x/94], &d_key[4 * i]);
					}
					SubBytes(IV[threadIdx.x/94], d_sbox);
					ShiftRows(IV[threadIdx.x/94]);
					AddRoundKey(IV[threadIdx.x/94], &d_key[4 * 10]);
				}
				__syncthreads();
				//-------------------------- Multi threads Job --------------------------------------------
				////////////////// Locating AES Encrypted parts into a pkt  ///////////////////////////////
				for(int i = 0; i < 16; i++){
					aes_tmp[threadIdx.x/94][((tid%94)*16) + i] = p_buf->rx_buf[(0x1000 * (tid/94 + rot_index*128)) + sizeof(struct ethhdr) + ((tid%94) * 16) + i] ^ IV[threadIdx.x/94][i];
				}
				for(int i = 0; i < 16; i++){
					p_buf->rx_buf[(0x1000 * (tid/94 + rot_index*128)) + sizeof(struct ethhdr) + sizeof(struct iphdr) + sizeof(struct esphdr) + ((tid%94) * 16) + i] = aes_tmp[threadIdx.x/94][((tid%94)*16) + i]; 
				}
				__syncthreads();
#if 1
				//-------------------------- Single threads Job --------------------------------------------
				if(tid % 94 == 0){
					//////////// Proto_type = ESP set! ///////////
					p_buf->rx_buf[0x1000 * (tid/94 + rot_index*128) + sizeof(struct ethhdr) + 9] = IPPROTO_ESP; // IPPROTO_ESP = 50
					struct ethhdr* ethh;
					struct iphdr* iph;
					struct esphdr* esph;

					ethh = (struct ethhdr *)&p_buf->rx_buf[0x1000 * (tid/94 + rot_index*128)];
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
					sha1_kernel_global_1514(&p_buf->rx_buf[(0x1000 * (tid/94 + rot_index*128)) + sizeof(struct ethhdr) + sizeof(struct iphdr)], &ictx[threadIdx.x/94], extended, 64, (tid/94 + rot_index*128));
					/**** Outer Digest ****/
					// H(K XOR opad, H(K XOR ipad, text)) : 20 Bytes
					sha1_kernel_global_1514(&(ictx[threadIdx.x/94].c_state[0]), &octx[threadIdx.x/94], extended, 20, (tid/94 + rot_index*128));
			
				//-------------------------- Single threads Job --------------------------------------------
				if(tid % 94 == 0){
					atomicAdd(&pkt_cnt[1], 1);	
					p_buf->rx_buf_idx[tid/94 + rot_index*128] = chain_seq+1;
					if(tid/94 == 127)
						rot_index += 1;
					if(rot_index == 4)
						rot_index = 0;
				}
			}
		}
		__syncthreads();
	}
}

unsigned int SubWord(unsigned int w) {                                              
	unsigned int i = (sbox[(w >> 24) & 0xFF] << 24) | (sbox[(w >> 16) & 0xFF] << 16); 
	i |= (sbox[(w >> 8) & 0xFF] << 8) | sbox[w & 0xFF];                               
	return i;                                                                         
}                                                                                   

unsigned int RotWord(unsigned int w) {                                              
	unsigned char temp = (w >> 24) & 0xFF;                                            
	return ((w << 8) | temp);                                                         
}                                                                                   

void KeyExpansion(unsigned char* key, unsigned int* w) {
	unsigned int temp;
	int i = 0;
	
	for(i = 0; i < KEY_SIZE; i++) {
		w[i] = (key[4*i] << 24) | (key[4*i + 1] << 16) | (key[4*i + 2] << 8) | key[4*i + 3];
	}
	
	for(; i < BLOCK_SIZE * (NUM_ROUNDS + 1); i++) {
		temp = w[i - 1];
		if(i % KEY_SIZE == 0) {
			temp = SubWord(RotWord(temp)) ^ Rcon[i / KEY_SIZE];
		}
		w[i] = w[i - KEY_SIZE] ^ temp;
	}
}                                                                                                            

extern "C"
void initialize_ipsec(int chain_seq)
{
	// CKJUNG, 18.10.25 [NF #2: IPSec] Setting initial_counter, key /////////////////////////

	unsigned char nounce[16];
	FILE* fnounce = fopen("test.ctr", "rb");
	fread(&nounce, 1, 16, fnounce);
	fclose(fnounce);

	int num_keys = BLOCK_SIZE * (NUM_ROUNDS + 1);
	unsigned char key[16];
	unsigned int* expanded_key = (unsigned int*)malloc(num_keys * sizeof(int));
	FILE* fkey = fopen("test.key", "rb");
	fread(&key, 1, 16, fkey);
	fclose(fkey);
	KeyExpansion(key, expanded_key);

	unsigned char *d_nounce;
	unsigned int *d_key;
	unsigned char *d_sbox;
	unsigned char *d_GF2;
	unsigned int *d_seq; // 20.02.02. CKJUNG

	unsigned int *d_extended;
	
	printf("____[Initialize]__NF #2__IPSec__\n");
	
	ASSERTRT(cudaMalloc((void**)&d_nounce, 16*sizeof(unsigned char)));
	ASSERTRT(cudaMemset(d_nounce, 0, 16*sizeof(unsigned char)));
	ASSERTRT(cudaMalloc((void**)&d_key, num_keys*sizeof(unsigned int)));
	ASSERTRT(cudaMemset(d_key, 0, num_keys*sizeof(unsigned int)));
	ASSERTRT(cudaMalloc((void**)&d_sbox, 256*sizeof(unsigned char)));
	ASSERTRT(cudaMemset(d_sbox, 0, 256*sizeof(unsigned char)));
	ASSERTRT(cudaMalloc((void**)&d_GF2, 256*sizeof(unsigned char)));
	ASSERTRT(cudaMemset(d_GF2, 0, 256*sizeof(unsigned char)));
	
	ASSERTRT(cudaMalloc((void**)&d_seq, sizeof(unsigned int)));
	ASSERTRT(cudaMemset(d_GF2, 0, sizeof(unsigned int)));
	
	ASSERTRT(cudaMalloc((void**)&d_extended, 512*80*24*sizeof(unsigned int)));
	ASSERTRT(cudaMemset(d_GF2, 0, sizeof(unsigned int)));
	
	cudaError_t nounce_err = cudaMemcpy(d_nounce, nounce, 16*sizeof(unsigned char), cudaMemcpyHostToDevice);
	cudaError_t key_err = cudaMemcpy(d_key, expanded_key, num_keys*sizeof(unsigned int), cudaMemcpyHostToDevice);
	cudaError_t sbox_err = cudaMemcpy(d_sbox, sbox, 256*sizeof(unsigned char), cudaMemcpyHostToDevice);
	cudaError_t GF2_err = cudaMemcpy(d_GF2, GF_2, 256*sizeof(unsigned char), cudaMemcpyHostToDevice);
	if(nounce_err != cudaSuccess || key_err != cudaSuccess || sbox_err != cudaSuccess || GF2_err != cudaSuccess)
	{
		START_RED
			printf("[Error] cudaMemcpy for \"nounce\" or \"key\" or \"sbox\" or \"GF2\" has failed.\n");
		END
	}else{
		START_GRN
			printf("[IPSec] Nounce, Expanded keys, SBOX, and GF2 are ready.\n");
		END
	}

	cudaStream_t cuda_stream3;
	ASSERT_CUDA(cudaStreamCreateWithFlags(&cuda_stream3,cudaStreamNonBlocking));
	
	printf("NF#2: IPsec\n");

	/* 
	 * ipsec for 64B pkt
	 * 1 pkt needs 3 GPU threads.
	 * 512 x 3 = 1,536 threads. (OK)
	 * 384 threads per TB; 384 = 3 * 128; each TB manages 128 pkts; 128 * 4 = 512 Descs 
	 */
	nf_ipsec_64<<< 4, 384, 0, cuda_stream3 >>> (p_buf, pkt_cnt, ctr, d_nounce, d_key, d_sbox, d_GF2, chain_seq, d_seq); 
	ipsec<<< 4, 384, 0, cuda_stream3 >>> (p_buf, pkt_cnt, ctr, d_nounce, d_key, d_sbox, d_GF2, chain_seq, d_seq); 

	/*
	 * ipsec for 1514B pkt
	 * 1 pkt needs 94 GPU threads.
	 * 512 x 94 = 48,128 threads. (Impossible)
	 * (Persistent kernel arch max; 1,024 threads per 1 SM) 14 x 1,024 = 14,336 threads is MAXIMUM 
	 * We can only afford 128 desc. 128 x 94 = 12,032 threads (OK)
	 * So, 12.8 x 940 is our choice here. ==> 13 x 940 (13 SM x 940 threads/SM)
	 */
	nf_ipsec_1514<<< 13, 940, 0, cuda_stream3 >>> (p_buf, pkt_cnt, ctr, d_nounce, d_key, d_sbox, d_GF2, chain_seq, d_seq, d_extended); 

	START_GRN
	printf("[Done]____[Initialize]__NF #2__IPSec__\n");
	END	

	free(expanded_key);
	// ~ CKJUNG /////////////////////////////////////////////////////////////////////////////
}

