#ifndef _RELIBC_SCHED_H
#define _RELIBC_SCHED_H

#include <time.h>
#include <bits/sched.h>

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/sched.h.html>.
 */
#define SCHED_FIFO 0

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/sched.h.html>.
 */
#define SCHED_RR 1

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/sched.h.html>.
 */
#define SCHED_OTHER 2

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/sched_yield.html>.
 */
int sched_yield(void);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* _RELIBC_SCHED_H */
