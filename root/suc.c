/*
 * suc -- the su client that talks to sud (proof of concept).
 *
 * Run by an app, this does NOT try to elevate itself -- it cannot, because the
 * app process has PR_SET_NO_NEW_PRIVS set. It connects to the sud daemon, which
 * is already root, hands over its stdin/stdout/stderr, and asks it to run the
 * command. That is the whole trick, and it is why this works where a setuid su
 * does not.
 *
 *   suc [UID] -c "command"     run "command" as UID (default 0) via the daemon
 *   suc [UID]                  no command: for the PoC, defaults to `id`
 *
 * The real su would forward an interactive shell here; the PoC only needs to
 * prove root comes back.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "suclient.h"

#define MAXCMD 8192

static int looks_like_uid(const char *s) {
    if (!*s) return 0;
    for (const char *p = s; *p; p++) if (*p < '0' || *p > '9') return 0;
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
    } else {
        strcpy(cmd, "id");            /* PoC default */
    }

    int status = su_via_daemon(target, cmd);
    if (status < 0) {
        fprintf(stderr, "suc: cannot reach the root daemon (@%s): is sud running?\n",
                SOCK_NAME);
        return 1;
    }
    return status;
}
