/*
 * suclient -- shared wire protocol for talking to sud (the root daemon).
 * See suclient.h. Kept minimal: this is the one piece of protocol code that
 * must be byte-identical between suc and su, so it lives once.
 */

#include "suclient.h"

#include <stddef.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define MAXCMD 8192

int su_via_daemon(unsigned int target_uid, const char *cmd) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    struct sockaddr_un a = {0};
    a.sun_family = AF_UNIX;
    a.sun_path[0] = '\0';
    memcpy(a.sun_path + 1, SOCK_NAME, strlen(SOCK_NAME));
    socklen_t alen = offsetof(struct sockaddr_un, sun_path) + 1 + strlen(SOCK_NAME);

    if (connect(fd, (struct sockaddr *)&a, alen) != 0) {
        close(fd);
        return -1;
    }

    /* payload: 4-byte target uid + command; ancillary: our 0/1/2 fds */
    char buf[4 + MAXCMD];
    memcpy(buf, &target_uid, 4);
    size_t clen = strlen(cmd);
    if (clen > MAXCMD) clen = MAXCMD;
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

    if (sendmsg(fd, &msg, 0) < 0) {
        close(fd);
        return -1;
    }

    unsigned int status = 1;
    ssize_t n = read(fd, &status, sizeof status);
    close(fd);
    if (n != sizeof status) return -1;
    return (int)status;
}
