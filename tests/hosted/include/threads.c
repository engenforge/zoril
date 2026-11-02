/* Starts a thread that keeps the process alive for a few seconds. */
#include <pthread.h>
#include <unistd.h>
static void *napper(void *arg) { (void)arg; sleep(5); return 0; }
void start_thread(void) {
    pthread_t t;
    pthread_create(&t, 0, napper, 0);
}
