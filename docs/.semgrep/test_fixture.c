#include <stdio.h>
#include <string.h>

int main(int argc, char *argv[]) {
    char buf[64];
    strcpy(buf, argv[0]);  /* potential buffer overflow */
    printf("Hello: %s\n", buf);
    return 0;
}
