/*
 * su -- the hybrid su for the NL5H00X projector.
 *
 * Android su CLI: `su [UID] [-c COMMAND args...]`; bare `su` is an interactive
 * shell as uid 0; a bare command with no -c is also accepted, same as suc.
 *
 * Dispatch is on our own uid, because that is what decides whether we can
 * elevate ourselves at all:
 *
 *   - uid 0 or 2000 (AID_SHELL): these have no PR_SET_NO_NEW_PRIVS, so the
 *     stock setuid su still works and is the fast path. exec it unchanged,
 *     argv untouched, so behavior is byte-identical to stock su. Only if that
 *     exec fails and we are uid 0 do we fall back to doing the setuid/exec
 *     ourselves (root has nothing to gain by delegating to the daemon).
 *
 *   - any other uid: this is an app. Zygote sets PR_SET_NO_NEW_PRIVS on every
 *     app process, which neutralises setuid (see privtest.c), so a stock su
 *     cannot elevate it no matter what is exec'd. The only way root comes
 *     back is asking sud, which is already root, to do it on our behalf.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <grp.h>
#include <sys/types.h>
#include <unistd.h>

#include "suclient.h"

#define MAXCMD 8192

static int looks_like_uid(const char *s) {
    if (!*s) return 0;
    for (const char *p = s; *p; p++) if (*p < '0' || *p > '9') return 0;
    return 1;
}

/* uid 0 fallback if exec of the stock su fails: do the setuid/exec here. */
static int root_fallback(unsigned int target, const char *cmd) {
    setgroups(0, NULL);
    setgid(target);
    setuid(target);
    if (cmd && cmd[0]) {
        execl("/system/bin/sh", "sh", "-c", cmd, (char *)NULL);
    } else {
        execl("/system/bin/sh", "sh", (char *)NULL);
    }
    perror("su: exec /system/bin/sh");
    return 1;
}

int main(int argc, char **argv) {
    unsigned int target = 0;
    int i = 1;

    if (i < argc && looks_like_uid(argv[i])) {
        target = (unsigned int)strtoul(argv[i], NULL, 10);
        i++;
    }

    char cmd[MAXCMD];
    cmd[0] = '\0';
    if (i < argc && strcmp(argv[i], "-c") == 0) {
        i++;
        for (int k = i; k < argc; k++) {
            if (k > i) strncat(cmd, " ", sizeof cmd - strlen(cmd) - 1);
            strncat(cmd, argv[k], sizeof cmd - strlen(cmd) - 1);
        }
    } else if (i < argc) {
        for (int k = i; k < argc; k++) {
            if (k > i) strncat(cmd, " ", sizeof cmd - strlen(cmd) - 1);
            strncat(cmd, argv[k], sizeof cmd - strlen(cmd) - 1);
        }
    }

    uid_t me = getuid();
    if (me == 0 || me == 2000) {
        const char *orig = getenv("SUD_ORIG");
        if (!orig || !*orig) orig = "/system/xbin/su_orig";
        execv(orig, argv);
        /* stock su missing or unusable; only uid 0 can do anything about it */
        if (me == 0) return root_fallback(target, cmd);
        perror("su: exec su_orig");
        return 1;
    }

    /* app uid, has NO_NEW_PRIVS: cannot elevate itself, must delegate */
    const char *dcmd = cmd[0] ? cmd : "sh";     /* no -c: interactive-ish, PoC level */
    int status = su_via_daemon(target, dcmd);
    if (status < 0) {
        fprintf(stderr, "su: cannot reach the root daemon (@%s): is sud running?\n",
                SOCK_NAME);
        return 1;
    }
    return status;
}
