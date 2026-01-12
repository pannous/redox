#ifndef _SYS_SELECT_H
#define _SYS_SELECT_H

#include <bits/sys/select.h>
#include <sys/time.h>
#include <signal.h>

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/pselect.html>.
 */
int select(int nfds, fd_set *readfds, fd_set *writefds, fd_set *exceptfds, struct timeval *timeout);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* _SYS_SELECT_H */
