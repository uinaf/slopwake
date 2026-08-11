#include <unistd.h>

int main(void) {
    if (setsid() == -1) {
        return 1;
    }
    sleep(30);
    return 0;
}
