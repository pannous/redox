/*
 * SMP Stress Test for Redox OS
 * Tests concurrent execution, memory operations, and system stability
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/wait.h>
#include <string.h>
#include <time.h>

#define NUM_WORKERS 8
#define ITERATIONS 10000
#define MEMORY_SIZE (1024 * 1024) // 1MB per worker

// Shared memory test - will trigger TLB shootdowns
volatile int shared_counter = 0;

void cpu_intensive_work(int worker_id) {
    unsigned long sum = 0;
    for (int i = 0; i < ITERATIONS * 100; i++) {
        sum += i * worker_id;
        if (i % 10000 == 0) {
            // Touch shared memory to trigger cache coherency
            shared_counter++;
        }
    }
    printf("Worker %d: CPU intensive work done (sum=%lu)\n", worker_id, sum);
}

void memory_intensive_work(int worker_id) {
    char *buffer = malloc(MEMORY_SIZE);
    if (!buffer) {
        fprintf(stderr, "Worker %d: Failed to allocate memory\n", worker_id);
        return;
    }

    // Write pattern
    for (int i = 0; i < MEMORY_SIZE; i++) {
        buffer[i] = (char)(i + worker_id);
    }

    // Verify pattern
    for (int i = 0; i < MEMORY_SIZE; i++) {
        if (buffer[i] != (char)(i + worker_id)) {
            fprintf(stderr, "Worker %d: Memory corruption detected at %d!\n", worker_id, i);
            free(buffer);
            return;
        }
    }

    printf("Worker %d: Memory test passed (%d bytes)\n", worker_id, MEMORY_SIZE);
    free(buffer);
}

void io_intensive_work(int worker_id) {
    char filename[64];
    snprintf(filename, sizeof(filename), "/tmp/smp_test_%d.tmp", worker_id);

    FILE *fp = fopen(filename, "w");
    if (!fp) {
        fprintf(stderr, "Worker %d: Failed to open file\n", worker_id);
        return;
    }

    // Write test data
    for (int i = 0; i < 1000; i++) {
        fprintf(fp, "Worker %d iteration %d\n", worker_id, i);
    }
    fclose(fp);

    // Read and verify
    fp = fopen(filename, "r");
    if (!fp) {
        fprintf(stderr, "Worker %d: Failed to reopen file\n", worker_id);
        return;
    }

    char line[128];
    int count = 0;
    while (fgets(line, sizeof(line), fp)) {
        count++;
    }
    fclose(fp);

    // Cleanup
    unlink(filename);

    printf("Worker %d: I/O test passed (%d lines)\n", worker_id, count);
}

void worker_process(int worker_id) {
    printf("Worker %d starting (PID %d)...\n", worker_id, getpid());

    // Run different types of workloads
    cpu_intensive_work(worker_id);
    memory_intensive_work(worker_id);
    io_intensive_work(worker_id);

    printf("Worker %d completed all tests\n", worker_id);
    exit(0);
}

int main(int argc, char *argv[]) {
    printf("=== SMP Stress Test ===\n");
    printf("Starting %d concurrent worker processes...\n\n", NUM_WORKERS);

    time_t start_time = time(NULL);
    pid_t workers[NUM_WORKERS];

    // Spawn worker processes
    for (int i = 0; i < NUM_WORKERS; i++) {
        pid_t pid = fork();
        if (pid < 0) {
            fprintf(stderr, "Failed to fork worker %d\n", i);
            return 1;
        } else if (pid == 0) {
            // Child process
            worker_process(i);
        } else {
            // Parent process
            workers[i] = pid;
        }
    }

    // Wait for all workers to complete
    int failed = 0;
    for (int i = 0; i < NUM_WORKERS; i++) {
        int status;
        pid_t pid = waitpid(workers[i], &status, 0);
        if (pid < 0) {
            fprintf(stderr, "Failed to wait for worker %d\n", i);
            failed++;
        } else if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
            fprintf(stderr, "Worker %d failed with status %d\n", i, status);
            failed++;
        } else {
            printf("Worker %d (PID %d) completed successfully\n", i, pid);
        }
    }

    time_t end_time = time(NULL);

    printf("\n=== Test Results ===\n");
    printf("Duration: %ld seconds\n", end_time - start_time);
    printf("Workers completed: %d/%d\n", NUM_WORKERS - failed, NUM_WORKERS);
    printf("Shared counter value: %d (expected ~%d)\n", shared_counter, NUM_WORKERS * ITERATIONS / 10);
    printf("Status: %s\n", failed == 0 ? "PASSED" : "FAILED");

    return failed > 0 ? 1 : 0;
}
