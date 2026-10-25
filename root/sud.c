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
 * Started at boot by init (sud.rc), or by hand as root over adb.
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
 *
 * Concurrency: every connection gets its own session process, which runs the
 * command and waits for it. The listening process only accepts, forks and
 * reaps, so one long-lived root shell (a launcher keeps one open) cannot block
 * anyone else. Sessions are capped at MAX_SESSIONS; past that a caller gets
 * exit status 1 at once instead of hanging.
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE                        /* accept4, struct ucred outside bionic */
#endif

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <poll.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
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

#define MAX_SESSIONS      16   /* concurrent requests, long-lived shells included */
#define REQUEST_TIMEOUT_S 5    /* a connection must send its request this fast */
#define REAP_INTERVAL_MS  1000 /* how long a finished session can stay a zombie */
#define NOTE_TIMEOUT_MS   500  /* longest a denial waits on the caller's stderr */

static int package_for_uid(uid_t uid, char *out, size_t outlen) {
    FILE *f = fopen(PKG_LIST, "re");
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
    FILE *f = fopen(ALLOW_FILE, "re");
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

/* Close every fd the kernel installed from SCM_RIGHTS except those we keep. */
static void close_unused_rights(struct msghdr *msg, struct cmsghdr *keep) {
    for (struct cmsghdr *c = CMSG_FIRSTHDR(msg); c; c = CMSG_NXTHDR(msg, c)) {
        if (c == keep || c->cmsg_level != SOL_SOCKET || c->cmsg_type != SCM_RIGHTS)
            continue;
        size_t n = (c->cmsg_len - CMSG_LEN(0)) / sizeof(int);
        for (size_t i = 0; i < n; i++) {
            int fd;
            memcpy(&fd, CMSG_DATA(c) + i * sizeof(int), sizeof fd);
            close(fd);
        }
    }
}

/* Receive target uid + command, and the three standard fds. */
static int recv_request(int conn, int flags, uid_t *target, char *cmd,
                        size_t cmdlen, int fds[3]) {
    struct msghdr msg = {0};
    char buf[4 + MAXCMD];
    struct iovec iov = { buf, sizeof buf };
    /* room for more than one header, so extra fds a client sends still get
     * reported to us and closed, not silently kept */
    union { char b[CMSG_SPACE(sizeof(int) * 3) * 4]; struct cmsghdr align; } ctrl;
    msg.msg_iov = &iov;
    msg.msg_iovlen = 1;
    msg.msg_control = ctrl.b;
    msg.msg_controllen = sizeof ctrl.b;

    fds[0] = fds[1] = fds[2] = -1;
    /* CLOEXEC: the fds only reach the command through the explicit dup2 below */
    ssize_t n = recvmsg(conn, &msg, flags | MSG_CMSG_CLOEXEC);
    if (n < 0) return -1;

    struct cmsghdr *keep = NULL;
    for (struct cmsghdr *c = CMSG_FIRSTHDR(&msg); c; c = CMSG_NXTHDR(&msg, c)) {
        /* any app can connect here, so a short/forged control message must
         * not make us read past it and dup2/close whatever garbage follows */
        if (!keep && c->cmsg_level == SOL_SOCKET && c->cmsg_type == SCM_RIGHTS &&
            c->cmsg_len == CMSG_LEN(sizeof(int) * 3)) {
            keep = c;
            memcpy(fds, CMSG_DATA(c), sizeof(int) * 3);
        }
    }
    close_unused_rights(&msg, keep);

    if (n < 4 || (msg.msg_flags & MSG_CTRUNC)) {
        for (int i = 0; i < 3; i++) if (fds[i] >= 0) close(fds[i]);
        fds[0] = fds[1] = fds[2] = -1;
        return -1;
    }

    unsigned int t;
    memcpy(&t, buf, 4);
    *target = (uid_t)t;
    size_t clen = (size_t)n - 4;
    if (clen >= cmdlen) clen = cmdlen - 1;
    memcpy(cmd, buf + 4, clen);
    cmd[clen] = '\0';
    return 0;
}

/* MSG_NOSIGNAL: a caller that died must not take the daemon down with SIGPIPE. */
static void send_status(int conn, int status) {
    unsigned int s = (unsigned int)status;
    (void)!send(conn, &s, sizeof s, MSG_NOSIGNAL);
}

/* Write a note to a caller-owned fd without letting the caller stall the
 * session: a full pipe nobody reads would block the write forever. A throwaway
 * child does the write as the caller and is SIGKILLed past the deadline, so the
 * note is best effort and the session always moves on. */
static void bounded_note(int fd, uid_t uid, gid_t gid, const char *text) {
    pid_t w = fork();
    if (w == 0) {
        if (setgroups(0, NULL) != 0 || setgid(gid) != 0 || setuid(uid) != 0) _exit(1);
        (void)!write(fd, text, strlen(text));
        _exit(0);
    }
    if (w < 0) return;
    for (int waited = 0; waited < NOTE_TIMEOUT_MS; waited += 10) {
        pid_t r = waitpid(w, NULL, WNOHANG);
        if (r == w || (r < 0 && errno != EINTR)) return;
        usleep(10 * 1000);
    }
    /* still unreaped, so the pid cannot have been reused; SIGKILL ends a
     * blocked pipe write unconditionally */
    kill(w, SIGKILL);
    while (waitpid(w, NULL, 0) < 0 && errno == EINTR) {}
}

/* One request, in its own session process. Blocking here blocks nobody else. */
static void handle(int conn) {
    struct ucred cr;
    socklen_t crlen = sizeof cr;
    if (getsockopt(conn, SOL_SOCKET, SO_PEERCRED, &cr, &crlen) != 0) return;

    /* a client that connects and never sends would otherwise hold a session
     * slot forever; the command itself has no time limit */
    struct timeval tv = { REQUEST_TIMEOUT_S, 0 };
    setsockopt(conn, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);

    uid_t target = 0;
    char cmd[MAXCMD + 1];          /* +1 so a full MAXCMD-byte command from
                                     * suclient.c is not truncated */
    int fds[3];
    if (recv_request(conn, 0, &target, cmd, sizeof cmd, fds) != 0) return;

    int status = 1;

    /* root and shell are always allowed; app uids must be on the list. */
    int permitted = (cr.uid == 0 || cr.uid == 2000);
    char pkg[512] = "";
    if (!permitted) {
        if (package_for_uid(cr.uid, pkg, sizeof pkg) && package_allowed(pkg))
            permitted = 1;
    }

    if (!permitted) {
        /* only to the caller's stderr: text on conn would be read as status */
        if (fds[2] >= 0) {
            char note[640];
            snprintf(note, sizeof note, "sud: uid %u (%s) not allowed\n", cr.uid,
                     pkg[0] ? pkg : "unknown");
            bounded_note(fds[2], cr.uid, cr.gid, note);
        }
    } else {
        pid_t pid = fork();
        if (pid == 0) {
            signal(SIGPIPE, SIG_DFL);     /* the daemon ignores it; the command must not */
            /* fail closed: never run as root because dropping to target failed.
             * Done before taking the caller's fds, so the error goes to sud's own
             * stderr; a full caller pipe would otherwise hold this session forever. */
            if (setgroups(0, NULL) != 0 || setgid(target) != 0 || setuid(target) != 0) {
                dprintf(2, "sud: cannot switch to uid %u: %s\n", target, strerror(errno));
                _exit(1);
            }
            if (fds[0] >= 0) dup2(fds[0], 0);
            if (fds[1] >= 0) dup2(fds[1], 1);
            if (fds[2] >= 0) dup2(fds[2], 2);
            execl(SHELL, "sh", "-c", cmd, (char *)NULL);
            _exit(127);
        }
        /* drop our copies now so the session never keeps the caller's pipes open */
        for (int i = 0; i < 3; i++) if (fds[i] >= 0) close(fds[i]);
        fds[0] = fds[1] = fds[2] = -1;
        if (pid > 0) {
            int st;
            pid_t w;
            while ((w = waitpid(pid, &st, 0)) < 0 && errno == EINTR) {}
            if (w == pid) status = WIFEXITED(st) ? WEXITSTATUS(st) : 1;
        }
    }

    for (int i = 0; i < 3; i++) if (fds[i] >= 0) close(fds[i]);
    send_status(conn, status);
}

/* Over the session cap or out of processes: fail this caller, quickly. */
static void reject(int conn) {
    uid_t target;
    char cmd[MAXCMD + 1];
    int fds[3];
    /* drain what is already queued, so its fds get closed and the reply is not
     * lost to a reset; never block the listening process on it */
    if (recv_request(conn, MSG_DONTWAIT, &target, cmd, sizeof cmd, fds) == 0)
        for (int i = 0; i < 3; i++) close(fds[i]);
    send_status(conn, 1);
}

static void reap(int *active) {
    pid_t p;
    while ((p = waitpid(-1, NULL, WNOHANG)) > 0) (*active)--;
}

/* fds 0-2 must be taken before any client fd arrives, or dup2 onto them could
 * clobber a received fd or leave it close-on-exec. */
static void ensure_std_fds(void) {
    for (int fd = 0; fd < 3; fd++) {
        if (fcntl(fd, F_GETFD) >= 0) continue;
        int n = open("/dev/null", O_RDWR);
        if (n >= 0 && n != fd) { dup2(n, fd); close(n); }
    }
}

int main(void) {
    ensure_std_fds();
    /* writes to a caller that hung up must fail with EPIPE, not kill the daemon */
    signal(SIGPIPE, SIG_IGN);

    /* CLOEXEC: commands must not inherit the listener. A root shell holding it
     * would keep @projector_su bound and stop a restarted sud from binding. */
    int srv = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (srv < 0) { perror("socket"); return 1; }

    struct sockaddr_un a = {0};
    a.sun_family = AF_UNIX;
    a.sun_path[0] = '\0';                       /* abstract namespace */
    memcpy(a.sun_path + 1, SOCK_NAME, strlen(SOCK_NAME));
    socklen_t alen = offsetof(struct sockaddr_un, sun_path) + 1 + strlen(SOCK_NAME);

    if (bind(srv, (struct sockaddr *)&a, alen) != 0) { perror("bind"); return 1; }
    if (listen(srv, 8) != 0) { perror("listen"); return 1; }

    fprintf(stderr, "sud: listening on @%s\n", SOCK_NAME);

    /* This process only accepts, forks and reaps. There is no SIGCHLD handler:
     * a handler reaping with waitpid(-1) would also be inherited by sessions
     * and steal their command's exit status. Reaping is polled instead. */
    int active = 0;
    for (;;) {
        reap(&active);
        struct pollfd p = { srv, POLLIN, 0 };
        int r = poll(&p, 1, REAP_INTERVAL_MS);
        if (r < 0 && errno != EINTR) { perror("poll"); return 1; }
        if (r <= 0) continue;

        int conn = accept4(srv, NULL, NULL, SOCK_CLOEXEC);
        if (conn < 0) {
            if (errno == EBADF || errno == EINVAL || errno == ENOTSOCK) {
                perror("accept");
                return 1;                       /* init restarts us */
            }
            /* EMFILE and friends: back off instead of spinning on poll */
            if (errno != EINTR && errno != EAGAIN && errno != ECONNABORTED)
                usleep(100 * 1000);
            continue;
        }

        reap(&active);
        if (active >= MAX_SESSIONS) {
            reject(conn);
            close(conn);
            continue;
        }

        pid_t pid = fork();
        if (pid == 0) {
            close(srv);
            handle(conn);
            _exit(0);
        }
        if (pid > 0) active++;
        else reject(conn);
        close(conn);
    }
}
