/*
 * sudcheck -- check a deployed sud from the device side.
 *
 * One process does everything: it drops to a caller uid, sends one request
 * (target uid + command) with fds 0/1/2 over SCM_RIGHTS, and prints the
 * status sud answers with.
 *
 * This shape exists because relaying loses information. A probe that drops
 * uid in one process and runs a client in another (the way su_hybrid does)
 * reports the wrapper's exit code, not sud's, and adb's shell can rewrite
 * quoted arguments. Both produced false results during the first deploy.
 *
 * Usage, as root:
 *   sudcheck UID TARGET CMD...     drop to UID, ask sud to run CMD as TARGET
 *
 * Examples:
 *   sudcheck 10037 0 id -u                 allowed caller, root command
 *   sudcheck 10039 0 id -u                 caller not on the allow-list
 *   sudcheck 10037 4294967295 id -u        target uid that cannot be switched to
 *   sudcheck 10037 0 sh -c 'exit 7'        exit status pass-through
 *   sudcheck 10037 0 exit 7                same, without a shell
 *
 * Exit status is sud's status, so 0 means the command ran. Output of the
 * command arrives on stdout as sud returns it.
 *
 * Build for the projector: root/build.sh builds sudcheck with the rest.
 */
#define _GNU_SOURCE
#include <grp.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define SOCK_NAME "projector_su"
#define MAXCMD 4096

static int connect_sud(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) {
        perror("socket");
        exit(2);
    }
    struct sockaddr_un a = {0};
    a.sun_family = AF_UNIX;
    memcpy(a.sun_path + 1, SOCK_NAME, strlen(SOCK_NAME));
    socklen_t alen = offsetof(struct sockaddr_un, sun_path) + 1 + strlen(SOCK_NAME);
    if (connect(fd, (struct sockaddr *)&a, alen) != 0) {
        perror("connect");
        exit(2);
    }
    return fd;
}

int main(int argc, char **argv) {
    if (argc < 4 || strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0) {
        fprintf(stderr,
                "usage: sudcheck UID TARGET CMD...\n"
                "  drops to UID and asks sud to run CMD as TARGET uid;\n"
                "  exits with the status sud answers (0 = command ran)\n");
        return 2;
    }

    unsigned int uid = (unsigned int)strtoul(argv[1], NULL, 10);
    unsigned int target = (unsigned int)strtoul(argv[2], NULL, 10);

    char cmd[MAXCMD];
    size_t used = 0;
    for (int i = 3; i < argc; i++) {
        if (i > 3 && used + 1 < sizeof cmd) cmd[used++] = ' ';
        size_t n = strlen(argv[i]);
        if (n > sizeof cmd - 1 - used) n = sizeof cmd - 1 - used;
        memcpy(cmd + used, argv[i], n);
        used += n;
    }
    cmd[used] = 0;

    /* The caller identity comes from SO_PEERCRED on sud's side, so this has
     * to happen before connect. */
    if (setgroups(0, NULL) || setgid(uid) || setuid(uid)) {
        perror("drop privileges");
        return 2;
    }

    int fd = connect_sud();

    char body[4 + MAXCMD];
    memcpy(body, &target, 4);
    memcpy(body + 4, cmd, used + 1);
    struct iovec iov = { body, 4 + used + 1 };

    int fds[3] = { 0, 1, 2 };
    union { char b[CMSG_SPACE(sizeof fds)]; struct cmsghdr align; } ctrl;
    memset(&ctrl, 0, sizeof ctrl);
    struct msghdr msg = {0};
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = ctrl.b;
    msg.msg_controllen = sizeof ctrl.b;
    struct cmsghdr *c = CMSG_FIRSTHDR(&msg);
    c->cmsg_level = SOL_SOCKET;
    c->cmsg_type = SCM_RIGHTS;
    c->cmsg_len = CMSG_LEN(sizeof fds);
    memcpy(CMSG_DATA(c), fds, sizeof fds);
    if (sendmsg(fd, &msg, 0) < 0) {
        perror("sendmsg");
        return 2;
    }

    unsigned int status = 1;
    if (read(fd, &status, sizeof status) != (ssize_t)sizeof status) {
        fprintf(stderr, "sudcheck: no status from sud (is it running?)\n");
        return 3;
    }
    close(fd);
    fprintf(stderr, "sudcheck: caller uid=%u target=%u status=%u\n", uid, target, status);
    return (int)status;
}
