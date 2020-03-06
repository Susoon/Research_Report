#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(void)
{
	FILE * output = fopen("data.txt", "w");

	srand(time(NULL));
	for(int i = 0; i < (1024 * 32 + 32) * 64 * 3; i++)
	{
		fprintf(output, "%d", rand() % 10);
	}

	fclose(output);
}
