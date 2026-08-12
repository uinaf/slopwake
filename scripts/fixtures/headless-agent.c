#include <signal.h>
#include <unistd.h>

int main(void) {
    if (setsid() == -1) {
        return 1;
    }
    for (;;) {
        pause();
    }
}
