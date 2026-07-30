/*
 * Diagnostic: does PR_SET_NO_NEW_PRIVS neutralise setuid elevation here?
 *
 *   privtest plain  <cmd...>   exec cmd directly
 *   privtest nnp    <cmd...>   set PR_SET_NO_NEW_PRIVS, then exec cmd
 *
 * Run both as an app uid against a setuid binary. If "plain" elevates and
 * "nnp" does not, NO_NEW_PRIVS is why apps cannot use a setuid su, and a
 * daemon is required instead.
 */
#include <stdio.h>
#include <sys/prctl.h>
#include <unistd.h>
#include <string.h>

#ifndef PR_SET_NO_NEW_PRIVS
#define PR_SET_NO_NEW_PRIVS 38
#endif

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: privtest plain|nnp <cmd> [args...]\n");
        return 2;
    }
    if (strcmp(argv[1], "nnp") == 0) {
        if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) != 0) {
            perror("prctl PR_SET_NO_NEW_PRIVS");
            return 3;
        }
        fprintf(stderr, "[NO_NEW_PRIVS set]\n");
    }
    execvp(argv[2], &argv[2]);
    perror("execvp");
    return 4;
}
