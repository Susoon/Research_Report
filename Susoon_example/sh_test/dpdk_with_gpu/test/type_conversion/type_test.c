#include <stdint.h>
#include <stdio.h>

#define LARGE(x) { 	\
	x = 1; 			\
	x <<= 50; 		\
	x += 2 << 30; 	\
	x += 2 << 10;	\
	size = 0;		\
}
#define MID(x) {	\
	x += (2 << 30) + (2 << 10);\
	size = 1;		\
}
#define SMALL(x) {	\
	x += 2 << 10;	\
	size = 2;		\
}

#define TEST_NUM(x) SMALL(x)

int main(void)
{
	uint64_t num64 = 0;
	int num = 0;
	int size = 0;

	TEST_NUM(num64);
	TEST_NUM(num);

	num64 += 1;

	char * test[] = { "LARGE", "MIDDLE", "SMALL"};

	printf("%s test : num64 = %ld, num = %d\nnum64 > num = %d\n", test[size], num64, num, num64 > num);

	return 0;
}		
