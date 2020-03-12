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

