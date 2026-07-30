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

#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define SOCK_NAME "projector_su"
#define MAXCMD    8192

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

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); return 1; }

    struct sockaddr_un a = {0};
    a.sun_family = AF_UNIX;
    a.sun_path[0] = '\0';
    memcpy(a.sun_path + 1, SOCK_NAME, strlen(SOCK_NAME));
    socklen_t alen = offsetof(struct sockaddr_un, sun_path) + 1 + strlen(SOCK_NAME);

    if (connect(fd, (struct sockaddr *)&a, alen) != 0) {
        fprintf(stderr, "suc: cannot reach the root daemon (@%s): is sud running?\n",
                SOCK_NAME);
        return 1;
    }

    /* payload: 4-byte target uid + command; ancillary: our 0/1/2 fds */
    char buf[4 + MAXCMD];
    memcpy(buf, &target, 4);
    size_t clen = strlen(cmd);
    memcpy(buf + 4, cmd, clen);

    struct msghdr msg = {0};
    struct iovec iov = { buf, 4 + clen };
    char ctrl[CMSG_SPACE(sizeof(int) * 3)];
    memset(ctrl, 0, sizeof ctrl);
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = ctrl;
    msg.msg_controllen = sizeof ctrl;

    struct cmsghdr *c = CMSG_FIRSTHDR(&msg);
    c->cmsg_level = SOL_SOCKET;
    c->cmsg_type = SCM_RIGHTS;
    c->cmsg_len = CMSG_LEN(sizeof(int) * 3);
    int stdfds[3] = { 0, 1, 2 };
    memcpy(CMSG_DATA(c), stdfds, sizeof stdfds);

    if (sendmsg(fd, &msg, 0) < 0) { perror("sendmsg"); return 1; }

    unsigned int status = 1;
    ssize_t n = read(fd, &status, sizeof status);
    if (n != sizeof status) return 1;
    return (int)status;
}
