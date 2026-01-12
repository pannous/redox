#ifndef _RELIBC_CTYPE_H
#define _RELIBC_CTYPE_H

#include <bits/ctype.h>
#include <features.h>

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/isalnum.html>.
 */
int isalnum(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/isalpha.html>.
 */
int isalpha(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9699919799/functions/isascii.html>.
 *
 * The `isascii()` function was marked obsolescent in the Open Group Base
 * Specifications Issue 7, and removed in Issue 8.
 */
__deprecated int isascii(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/isblank.html>.
 */
int isblank(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/iscntrl.html>.
 */
int iscntrl(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/isdigit.html>.
 */
int isdigit(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/isgraph.html>.
 */
int isgraph(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/islower.html>.
 */
int islower(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/isprint.html>.
 */
int isprint(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/ispunct.html>.
 */
int ispunct(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/isspace.html>.
 */
int isspace(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/isupper.html>.
 */
int isupper(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/isxdigit.html>.
 */
int isxdigit(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9699919799/functions/toascii.html>.
 *
 * The `toascii()` function was marked obsolescent in the Open Group Base
 * Specifications Issue 7, and removed in Issue 8.
 */
__deprecated int toascii(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/tolower.html>.
 */
int tolower(int c);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/toupper.html>.
 */
int toupper(int c);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* _RELIBC_CTYPE_H */
