#ifndef _NET_IF_H
#define _NET_IF_H

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/net_if.h.html>.
 */
#define IF_NAMESIZE 16

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/net_if.h.html>.
 */
struct if_nameindex {
  unsigned int if_index;
  const char *if_name;
};

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/if_freenameindex.html>.
 *
 * # Safety
 * this is a no-op: the list returned by if_nameindex() is a ref to a constant
 */
void if_freenameindex(struct if_nameindex *s);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/if_indextoname.html>.
 *
 * # Safety
 * Returns only static lifetime references to const names, does not reuse the buf pointer.
 * Returns NULL in case of not found + ERRNO being set to ENXIO.
 * Currently only checks against inteface index 1.
 */
const char *if_indextoname(unsigned int idx, char *buf);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/if_nameindex.html>.
 *
 * # Safety
 * Returns a constant pointer to a pre defined const stub list
 * The end of the list is determined by an if_nameindex struct having if_index 0 and if_name NULL
 */
const struct if_nameindex *if_nameindex(void);

/**
 * See <https://pubs.opengroup.org/onlinepubs/9799919799/functions/if_nametoindex.html>.
 *
 * # Safety
 * Compares the name to a constant string and only returns an int as a result.
 * An invalid name string will return an index of 0
 */
unsigned int if_nametoindex(const char *name);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* _NET_IF_H */
