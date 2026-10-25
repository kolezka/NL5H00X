/*
 * sudprobe -- test helper for tests/sud/sud-concurrency.sh. Linux only.
 *
 *   sudprobe runas UID PROG [ARGS...]  drop to UID (uid+gid) and exec PROG
 *   sudprobe hold                      connect to sud, never send, sleep
 *   sudprobe badfds                    send a valid request whose SCM_RIGHTS
 *                                      carries 5 fds instead of 3; print status
 *   sudprobe fds                       print this process's open fds, sorted,
 *                                      excluding the directory fd used to list
 *   sudprobe fullstderr N [TARGET]     send N requests (target uid TARGET,
 *                                      default 0) whose stderr is a full
 *                                      pipe nobody reads; wait up to 3 s for
 *                                      their statuses, print a summary, then
 *                                      keep the pipe full for 30 s
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <poll.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#define SOCK_NAME "projector_su"

static int connect_sud(void) {
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) { perror("socket"); exit(2); }
    struct sockaddr_un a = {0};
    a.sun_family = AF_UNIX;
    memcpy(a.sun_path + 1, SOCK_NAME, strlen(SOCK_NAME));
    socklen_t alen = offsetof(struct sockaddr_un, sun_path) + 1 + strlen(SOCK_NAME);
    if (connect(fd, (struct sockaddr *)&a, alen) != 0) { perror("connect"); exit(2); }
    return fd;
}

int main(int argc, char **argv) {
    if (argc >= 4 && strcmp(argv[1], "runas") == 0) {
        unsigned int uid = (unsigned int)strtoul(argv[2], NULL, 10);
        if (setgroups(0, NULL) || setgid(uid) || setuid(uid)) { perror("runas"); return 2; }
        execvp(argv[3], argv + 3);
        perror("exec");
        return 127;
    }
    if (argc == 2 && strcmp(argv[1], "hold") == 0) {
        connect_sud();
        sleep(60);
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "badfds") == 0) {
        int fd = connect_sud();
        char buf[4 + 4];
        unsigned int target = 0;
        memcpy(buf, &target, 4);
        memcpy(buf + 4, "true", 4);
        struct iovec iov = { buf, sizeof buf };
        int fds[5] = { 0, 1, 2, 0, 1 };
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
        if (sendmsg(fd, &msg, 0) < 0) { perror("sendmsg"); return 2; }
        unsigned int status = 0;
        if (read(fd, &status, sizeof status) != sizeof status) return 3;
        printf("%u\n", status);
        return 0;
    }
    if (argc == 2 && strcmp(argv[1], "fds") == 0) {
        DIR *d = opendir("/proc/self/fd");
        if (!d) { perror("opendir"); return 2; }
        int self = dirfd(d), seen[1024], n = 0;
        struct dirent *e;
        while ((e = readdir(d)) && n < 1024) {
            if (e->d_name[0] == '.') continue;
            int fd = atoi(e->d_name);
            if (fd != self) seen[n++] = fd;
        }
        closedir(d);
        for (int i = 0; i < n; i++)            /* tiny n: insertion sort */
            for (int j = i; j > 0 && seen[j - 1] > seen[j]; j--) {
                int t = seen[j]; seen[j] = seen[j - 1]; seen[j - 1] = t;
            }
        for (int i = 0; i < n; i++) printf("%d ", seen[i]);
        printf("\n");
        return 0;
    }
    if ((argc == 3 || argc == 4) && strcmp(argv[1], "fullstderr") == 0) {
        int count = atoi(argv[2]);
        unsigned int target = argc == 4 ? (unsigned int)strtoul(argv[3], NULL, 0) : 0;
        if (count < 1 || count > 64) return 2;
        int p[2];
        if (pipe(p)) { perror("pipe"); return 2; }
        int flags = fcntl(p[1], F_GETFL);
        fcntl(p[1], F_SETFL, flags | O_NONBLOCK);
        char fill[4096] = {0};
        while (write(p[1], fill, sizeof fill) > 0) {}
        if (errno != EAGAIN) { perror("fill"); return 2; }
        fcntl(p[1], F_SETFL, flags);           /* sud sees a blocking, full pipe */

        struct pollfd pf[64];
        for (int i = 0; i < count; i++) {
            int fd = connect_sud();
            char body[4 + 5] = { 0, 0, 0, 0, 'i', 'd', ' ', '-', 'u' };
            memcpy(body, &target, 4);
            struct iovec iov = { body, sizeof body };
            int fds[3] = { 0, 1, p[1] };
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
            if (sendmsg(fd, &msg, 0) != (ssize_t)sizeof body) { perror("sendmsg"); return 2; }
            pf[i].fd = fd;
            pf[i].events = POLLIN;
        }

        int got = 0, denied = 0;
        for (int left = 3000; left > 0 && got < count; left -= 50) {
            if (poll(pf, count, 50) <= 0) continue;
            for (int i = 0; i < count; i++) {
                if (pf[i].fd < 0 || !(pf[i].revents & (POLLIN | POLLHUP))) continue;
                unsigned int st = 0;
                if (read(pf[i].fd, &st, sizeof st) == sizeof st) {
                    got++;
                    if (st == 1) denied++;
                }
                pf[i].fd = -1;                 /* poll skips negative fds */
            }
        }
        printf("statuses=%d denied=%d of %d\n", got, denied, count);
        fflush(stdout);
        sleep(30);                             /* keep the pipe full meanwhile */
        return 0;
    }
    fprintf(stderr, "usage: sudprobe runas UID PROG... | hold | badfds | fds | fullstderr N [TARGET]\n");
    return 2;
}
