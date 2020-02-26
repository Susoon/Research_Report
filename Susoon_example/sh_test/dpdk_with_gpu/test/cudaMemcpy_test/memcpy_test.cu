#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include <cuda_runtime_api.h>
#include <cuda.h>

#define START_RED printf("\033[1;31m");
#define START_GRN printf("\033[1;32m");
#define START_YLW printf("\033[1;33m");
#define END printf("\033[0m");

#define ONE_SEC (1000 * 1000 * 1000)
#define HALF (1024 * 32 * 64)

#define RAND 0

#define LOOP 0

#define SEL 1

#define CASE 17

char * device_buf;
char * host_buf;

int test_cnt;

FILE * data = fopen("data.txt", "r");

uint64_t latency[17] = { 0 };
const char* size_str[17] = { "64", "128", "256", "512", "1024", "1514",\
		 "64 * 32", "64 * 64", "64 * 128", "64 * 256",	\
		"64 * 512", "64 * 1024", "64 * 1024 * 2", "64 * 1024 * 4",		 	\
		"64 * 1024 * 8", "64 * 1024 * 16", "64 * 1024 * 32"};
int size[17] = { 64, 128, 256, 512, 1024, 1514, 64 * 32, 64 * 64,\
			 64 * 128, 64 * 256, 64 * 512, 64 * 1024,\
			 64 * 1024 * 2, 64 * 1024 * 4, 64 * 1024 * 8,\
			 64 * 1024 * 16, 64 * 1024 * 32};

int start[17] = { 0 };
int end[17] = { 0 };

int monotonic_time() 
{
	struct timespec timespec;
	clock_gettime(CLOCK_MONOTONIC, &timespec);
	return timespec.tv_sec * ONE_SEC + timespec.tv_nsec;
}

void call_data(int size)
{
	fseek(data, 0, SEEK_SET);
	for(int i = 0; i < size; i++)
	{
		fscanf(data, "%c", host_buf + i);
	}
}

void once(void)
{
	int i = 0;
	
	int skip = 0;

	while(i < test_cnt)
	{
#if RAND
#else
		call_data(HALF * 2);
		skip = 0;
#endif
		for(int j = 0; j < CASE; j++)
		{
#if RAND
			call_data(size[j] * 2);
			start[j] = monotonic_time();
			cudaMemcpy(device_buf, host_buf + rand() % size[j], size[j], cudaMemcpyHostToDevice);
#else
			start[j] = monotonic_time();
			cudaMemcpy(device_buf, host_buf + skip, size[j], cudaMemcpyHostToDevice);
			skip += size[j];
#endif
			end[j] = monotonic_time();
			latency[j] += end[j] - start[j];
			cudaMemset(device_buf, 0, size[j]);
		}
		i++;
	}

	for(i = 0; i < CASE; i++)
	{
		latency[i] /= (uint64_t)test_cnt;
	}
}

void loop(int loop_cnt)
{
	int i = 0;

	while(i < test_cnt)
	{
		for(int j = 0; j < CASE; j++) 
		{
#if RAND
			call_data(size[j] * 2);
			start[j] = monotonic_time();
			for(int k = 0; k < loop_cnt; k++)
			{
			cudaMemcpy(device_buf, host_buf + rand() % size[j], size[j], cudaMemcpyHostToDevice);
			}
#else
			call_data(size[j]);
			start[j] = monotonic_time();
			for(int k = 0; k < loop_cnt; k++)
			{
			cudaMemcpy(device_buf, host_buf, size[j], cudaMemcpyHostToDevice);
			}
#endif
			end[j] = monotonic_time();
			latency[j] += (end[j] - start[j]) / (uint64_t)loop_cnt;
		}
		i++;
	}

	for(i = 0; i < CASE; i++)
	{
		latency[i] /= (uint64_t)test_cnt;
	}
}

void same_cnt_loop(void)
{
	int i = 0;

	int loop_cnt = size[16];
	int cur_loop_cnt;

	while(i < test_cnt)
	{
		for(int j = 0; j < CASE; j++) 
		{
			cur_loop_cnt = loop_cnt / size[j];
#if RAND
			call_data(size[j] * 2);
			start[j] = monotonic_time();
			for(int k = 0; k < cur_loop_cnt; k++)
			{
			cudaMemcpy(device_buf, host_buf + rand() % size[j], size[j], cudaMemcpyHostToDevice);
			}
#else
			call_data(size[j]);
			start[j] = monotonic_time();
			for(int k = 0; k < cur_loop_cnt; k++)
			{
			cudaMemcpy(device_buf, host_buf, size[j], cudaMemcpyHostToDevice);
			}
#endif
			end[j] = monotonic_time();
			latency[j] += end[j] - start[j];
		}
		i++;
	}

	for(i = 0; i < CASE; i++)
	{
		latency[i] /= (uint64_t)test_cnt;
	}
}

void print_result(void)
{
	START_RED
	printf("\n\n___________________TEST START____________________\n\n");
	END

	START_YLW
#if RAND
	printf("RANDOM DATA TEST!\n");
#else
	printf("NORMAL DATA TEST!\n");
#endif
	END

	START_GRN
#if LOOP
	printf("TEST WAS RUNNED %d TIMES!\n", test_cnt);
#elif SEL
	printf("TEST WAS RUNNED SAME TIMES!\n");
#else
	printf("TEST WAS RUNNED ONCE!\n");
#endif
	END

	for(int i = 0; i < CASE; i++)
	{
		printf("data size : %s, latency : %ld\n", size_str[i], latency[i]);
	}

	START_RED
	printf("\n___________________TEST END____________________\n\n\n");
	END
}


int main(void)
{

	srand(time(NULL));

	host_buf = (char *)calloc(HALF * 2, sizeof(char));
	cudaHostAlloc((void**)&device_buf, HALF * sizeof(char), cudaHostAllocDefault);
	cudaMemset(device_buf, 0 ,HALF * sizeof(char)); 

	printf("Enter the test_cnt\n");
	scanf("%d", &test_cnt);

#if LOOP
	int loop_cnt;

	printf("Enter the loop_cnt\n");
	scanf("%d", &loop_cnt);
	loop(loop_cnt);
#elif SEL
	same_cnt_loop();
#else
	once();
#endif

	print_result();

	cudaFree(device_buf);

	fclose(data);

	return 0;
}
