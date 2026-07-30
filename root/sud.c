/*
 * sud -- a minimal root daemon for the NL5H00X projector (proof of concept).
 *
 * Why this exists: zygote sets PR_SET_NO_NEW_PRIVS on every app process, which
 * neutralises setuid, so a setuid `su` can never elevate an app (measured:
 * "su: setgid failed"). The way every real root solution works instead -- and
 * the only way that works here -- is a daemon already running as root that apps
 * connect to over a socket. The app never elevates itself; it asks a process
 * that is already root to run something on its behalf.
 *
 * This is the PoC daemon. It is started by hand as root over adb and touches
 * nothing persistent. If it works, an init.rc service starts it at boot later.
 *
 * Protocol, one request per connection:
 *   client -> daemon : 4-byte target uid (LE) + command string,
 *                      with stdin/stdout/stderr passed as 3 fds (SCM_RIGHTS)
 *   daemon -> client : 4-byte exit status (LE)
 *
 * Access control: the caller's uid comes from SO_PEERCRED (kernel-supplied,
 * unspoofable), is resolved to a package via /data/system/packages.list, and
 * checked against /data/adb/su-allow. No list, or an unlisted caller, is
 * denied -- it fails closed, because failing open silently roots every app.
 */

#include <errno.h>
#include <grp.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#define SOCK_NAME  "projector_su"          /* abstract namespace (leading NUL) */
#define ALLOW_FILE "/data/adb/su-allow"
#define PKG_LIST   "/data/system/packages.list"
#define SHELL      "/system/bin/sh"
#define USER_RANGE 100000
#define MAXCMD     8192

static int package_for_uid(uid_t uid, char *out, size_t outlen) {
    FILE *f = fopen(PKG_LIST, "r");
    if (!f) return 0;
    char line[1024], name[512];
    unsigned long u;
    int found = 0;
    uid_t appid = uid % USER_RANGE;
    while (fgets(line, sizeof line, f)) {
        if (sscanf(line, "%511s %lu", name, &u) != 2) continue;
        if ((uid_t)(u % USER_RANGE) == appid) {
            snprintf(out, outlen, "%s", name);
            found = 1;
            break;
        }
    }
    fclose(f);
    return found;
}

static int package_allowed(const char *pkg) {
    FILE *f = fopen(ALLOW_FILE, "r");
    if (!f) return 0;
    char line[512];
    int ok = 0;
    while (fgets(line, sizeof line, f)) {
        char *s = line;
        while (*s == ' ' || *s == '\t') s++;
        char *e = s + strlen(s);
        while (e > s && (e[-1] == '\n' || e[-1] == '\r' ||
                         e[-1] == ' '  || e[-1] == '\t')) *--e = '\0';
        if (*s == '\0' || *s == '#') continue;
        if (strcmp(s, pkg) == 0) { ok = 1; break; }
    }
    fclose(f);
    return ok;
}

/* Receive target uid + command, and the three standard fds. */
static int recv_request(int conn, uid_t *target, char *cmd, size_t cmdlen,
                        int fds[3]) {
    struct msghdr msg = {0};
    char buf[4 + MAXCMD];
    struct iovec iov = { buf, sizeof buf };
    char ctrl[CMSG_SPACE(sizeof(int) * 3)];
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = ctrl;
    msg.msg_controllen = sizeof ctrl;

    ssize_t n = recvmsg(conn, &msg, 0);
    if (n < 4) return -1;

    unsigned int t;
    memcpy(&t, buf, 4);
    *target = (uid_t)t;
    size_t clen = (size_t)n - 4;
    if (clen >= cmdlen) clen = cmdlen - 1;
    memcpy(cmd, buf + 4, clen);
    cmd[clen] = '\0';

    fds[0] = fds[1] = fds[2] = -1;
    for (struct cmsghdr *c = CMSG_FIRSTHDR(&msg); c; c = CMSG_NXTHDR(&msg, c)) {
        if (c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS) {
            memcpy(fds, CMSG_DATA(c), sizeof(int) * 3);
        }
    }
    return 0;
}

static void handle(int conn) {
    struct ucred cr;
    socklen_t crlen = sizeof cr;
    if (getsockopt(conn, SOL_SOCKET, SO_PEERCRED, &cr, &crlen) != 0) return;

    uid_t target = 0;
    char cmd[MAXCMD];
    int fds[3];
    if (recv_request(conn, &target, cmd, sizeof cmd, fds) != 0) return;

    int status = 1;

    /* root and shell are always allowed; app uids must be on the list. */
    int permitted = (cr.uid == 0 || cr.uid == 2000);
    char pkg[512] = "";
    if (!permitted) {
        if (package_for_uid(cr.uid, pkg, sizeof pkg) && package_allowed(pkg))
            permitted = 1;
    }

    if (!permitted) {
        dprintf(fds[2] >= 0 ? fds[2] : conn,
                "sud: uid %u (%s) not allowed\n", cr.uid,
                pkg[0] ? pkg : "unknown");
    } else {
        pid_t pid = fork();
        if (pid == 0) {
            if (fds[0] >= 0) dup2(fds[0], 0);
            if (fds[1] >= 0) dup2(fds[1], 1);
            if (fds[2] >= 0) dup2(fds[2], 2);
            setgroups(0, NULL);
            setgid(target);
            setuid(target);
            execl(SHELL, "sh", "-c", cmd, (char *)NULL);
            _exit(127);
        } else if (pid > 0) {
            int st;
            waitpid(pid, &st, 0);
            status = WIFEXITED(st) ? WEXITSTATUS(st) : 1;
        }
    }

    for (int i = 0; i < 3; i++) if (fds[i] >= 0) close(fds[i]);
    unsigned int s = (unsigned int)status;
    (void)!write(conn, &s, sizeof s);
}

int main(void) {
    int srv = socket(AF_UNIX, SOCK_STREAM, 0);
    if (srv < 0) { perror("socket"); return 1; }

    struct sockaddr_un a = {0};
    a.sun_family = AF_UNIX;
    a.sun_path[0] = '\0';                       /* abstract namespace */
    memcpy(a.sun_path + 1, SOCK_NAME, strlen(SOCK_NAME));
    socklen_t alen = offsetof(struct sockaddr_un, sun_path) + 1 + strlen(SOCK_NAME);

    if (bind(srv, (struct sockaddr *)&a, alen) != 0) { perror("bind"); return 1; }
    if (listen(srv, 8) != 0) { perror("listen"); return 1; }

    fprintf(stderr, "sud: listening on @%s\n", SOCK_NAME);

    /* One connection at a time, each fork()+waitpid()'d synchronously below,
     * so there are no zombies to reap and no SIGCHLD handling to get wrong. */
    for (;;) {
        int conn = accept(srv, NULL, NULL);
        if (conn < 0) { if (errno == EINTR) continue; break; }
        handle(conn);
        close(conn);
    }
    return 0;
}
