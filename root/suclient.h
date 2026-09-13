/*
 * suclient -- shared wire protocol for talking to sud (the root daemon).
 *
 * Both suc (PoC client) and su (hybrid su) need to speak the exact same
 * protocol, and getting it wrong in one but not the other is the kind of bug
 * that only shows up on-device. Extracted here so there is one implementation.
 */
#ifndef SUCLIENT_H
#define SUCLIENT_H

#define SOCK_NAME "projector_su"    /* abstract namespace (leading NUL) */

/*
 * Ask sud to run cmd as target_uid, with our own stdin/stdout/stderr handed
 * over via SCM_RIGHTS. Returns the daemon's 4-byte exit status, or -1 if the
 * socket could not be reached (caller prints its own "is sud running?").
 */
int su_via_daemon(unsigned int target_uid, const char *cmd);

#endif
