#include <stdio.h>
#include <pthread.h>
#include <unistd.h>

double waste_time(long n)
{
	double res = 0;
	long i = 0;
	while(i < n * 200000)
	{
		i++;
		res += i;
	}
	
	return res;
}

void * thread_func(void * param)
{
	unsigned long mask;

	while(1)
	{
#if 0
		sleep(3);

		mask = 4;

		if(pthread_setaffinity_np(pthread_self(), sizeof(mask), &mask) < 0)
		{
			perror("pthread_setaffinity_np");
		}
	
		printf("result: %f\n", waste_time(2000));

		sleep(3);

		mask = 8;
	
			if(pthread_setaffinity_np(pthread_self(), sizeof(mask), &mask) < 0)
		{
			perror("pthread_setaffinity_np");
			}
#endif		
		printf("pthread result: %f\n", waste_time(2000));
	}
}

int main(void)
{
	pthread_t my_thread;

	if(pthread_create(&my_thread, NULL, thread_func, NULL) != 0)
		perror("pthread_create");
	
	int i = 0;

	while(1)
	{
		printf("main result : %f\n", waste_time(i));
		i += 20;
	}
	
	pthread_exit(NULL);
}
