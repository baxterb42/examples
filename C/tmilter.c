#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>

#include "libmilter/mfapi.h"

#include <pwd.h>	/* setuid support */

#include <syslog.h>	/* logging support */
#include "apue.h"	/* daemonize support */

int             log_to_stderr = 0;

#ifndef bool
# define bool	int
# define TRUE	1
# define FALSE	0
#endif /* ! bool */


struct mlfiPriv
{
	char	*mlfi_fname;
	char	*mlfi_connectfrom;
	char	*mlfi_helofrom;
	FILE	*mlfi_fp;
};

#define MLFIPRIV	((struct mlfiPriv *) smfi_getpriv(ctx))

extern sfsistat		mlfi_cleanup(SMFICTX *, bool);

/* recipients to add and reject (set with -a and -r options) */
char *add = NULL;
char *reject = NULL;

sfsistat
mlfi_connect(ctx, hostname, hostaddr)
	 SMFICTX *ctx;
	 char *hostname;
	 _SOCK_ADDR *hostaddr;
{
	struct mlfiPriv *priv;
	char *ident;

	/* allocate some private memory */
	priv = malloc(sizeof *priv);
	if (priv == NULL)
	{
		/* can't accept this message right now */
		return SMFIS_TEMPFAIL;
	}
	memset(priv, '\0', sizeof *priv);

	/* save the private data */
	smfi_setpriv(ctx, priv);

	ident = smfi_getsymval(ctx, "_");
	if (ident == NULL)
		ident = "???";
	if ((priv->mlfi_connectfrom = strdup(ident)) == NULL)
	{
		(void) mlfi_cleanup(ctx, FALSE);
		return SMFIS_TEMPFAIL;
	}

	/* continue processing */
	return SMFIS_CONTINUE;
}

sfsistat
mlfi_helo(ctx, helohost)
	 SMFICTX *ctx;
	 char *helohost;
{
	size_t len;
	char *tls;
	char *buf;
	struct mlfiPriv *priv = MLFIPRIV;

	tls = smfi_getsymval(ctx, "{tls_version}");
	if (tls == NULL)
		tls = "No TLS";
	if (helohost == NULL)
		helohost = "???";
	len = strlen(tls) + strlen(helohost) + 3;
	if ((buf = (char*) malloc(len)) == NULL)
	{
		(void) mlfi_cleanup(ctx, FALSE);
		return SMFIS_TEMPFAIL;
	}
	snprintf(buf, len, "%s, %s", helohost, tls);
	if (priv->mlfi_helofrom != NULL)
		free(priv->mlfi_helofrom);
	priv->mlfi_helofrom = buf;

	/* continue processing */
	return SMFIS_CONTINUE;
}

sfsistat
mlfi_envfrom(ctx, argv)
	 SMFICTX *ctx;
	 char **argv;
{
	int fd = -1;
	int argc = 0;
	struct mlfiPriv *priv = MLFIPRIV;
	char *mailaddr = smfi_getsymval(ctx, "{mail_addr}");

	/* open a file to store this message */
	if ((priv->mlfi_fname = strdup("/var/tmp/tmilter/msg.XXXXXX")) == NULL)
	{
		(void) mlfi_cleanup(ctx, FALSE);
		return SMFIS_TEMPFAIL;
	}

	if ((fd = mkstemp(priv->mlfi_fname)) == -1)
	{
		(void) mlfi_cleanup(ctx, FALSE);
		return SMFIS_TEMPFAIL;
	}

	if ((priv->mlfi_fp = fdopen(fd, "w+")) == NULL)
	{
		(void) close(fd);
		(void) mlfi_cleanup(ctx, FALSE);
		return SMFIS_TEMPFAIL;
	}

	/* continue processing */
	return SMFIS_CONTINUE;
}

sfsistat
mlfi_envrcpt(ctx, argv)
	 SMFICTX *ctx;
	 char **argv;
{
	struct mlfiPriv *priv = MLFIPRIV;
	char *rcptaddr = smfi_getsymval(ctx, "{rcpt_addr}");
	int argc = 0;

	/* continue processing */
	return SMFIS_CONTINUE;
}

sfsistat
mlfi_header(ctx, headerf, headerv)
	 SMFICTX *ctx;
	 char *headerf;
	 unsigned char *headerv;
{
	/* write the header to the log file */
	if (fprintf(MLFIPRIV->mlfi_fp, "%s: %s\n", headerf, headerv) == EOF)
	{
		(void) mlfi_cleanup(ctx, FALSE);
		return SMFIS_TEMPFAIL;
	}

	/* continue processing */
	return SMFIS_CONTINUE;
}

sfsistat
mlfi_eoh(ctx)
	 SMFICTX *ctx;
{
	/* output the blank line between the header and the body */
	if (fprintf(MLFIPRIV->mlfi_fp, "\n") == EOF)
	{
		(void) mlfi_cleanup(ctx, FALSE);
		return SMFIS_TEMPFAIL;
	}

	/* continue processing */
	return SMFIS_CONTINUE;
}

sfsistat
mlfi_body(ctx, bodyp, bodylen)
	 SMFICTX *ctx;
	 unsigned char *bodyp;
	 size_t bodylen;
{
        struct mlfiPriv *priv = MLFIPRIV;

	/* output body block to log file */
	if (fwrite(bodyp, bodylen, 1, priv->mlfi_fp) != 1)
	{
		/* write failed */
/*		fprintf(stderr, "Couldn't write file %s: %s\n",
			priv->mlfi_fname, strerror(errno));
*/
		syslog(LOG_ERR, "mlfi_body Couldn't write file %s: %m\n",
			priv->mlfi_fname);

		(void) mlfi_cleanup(ctx, FALSE);
		return SMFIS_TEMPFAIL;
	}

	/* continue processing */
	return SMFIS_CONTINUE;
}

sfsistat
mlfi_eom(ctx)
	 SMFICTX *ctx;
{
	bool ok = TRUE;

	/* change recipients, if requested */
	if (add != NULL)
		ok = (smfi_addrcpt(ctx, add) == MI_SUCCESS);
	return mlfi_cleanup(ctx, ok);
}

sfsistat
mlfi_abort(ctx)
	 SMFICTX *ctx;
{
	syslog(LOG_INFO, "mlfi_abort called. %m\n");
	return mlfi_cleanup(ctx, FALSE);
}

sfsistat
mlfi_cleanup(ctx, ok)
	 SMFICTX *ctx;
	 bool ok;
{
	sfsistat rstat = SMFIS_CONTINUE;
	struct mlfiPriv *priv = MLFIPRIV;
	char *p;
	char host[512];
	char hbuf[1024];

	syslog(LOG_INFO, "mlfi_cleanup called. %m\n");

	if (priv == NULL)
		return rstat;

	/* close the archive file */
	if (priv->mlfi_fp != NULL && fclose(priv->mlfi_fp) == EOF)
	{
		/* failed; we have to wait until later */
/*		fprintf(stderr, "Couldn't close archive file %s: %s\n",
			priv->mlfi_fname, strerror(errno));
*/
                syslog(LOG_ERR, "mlfi_cleanup Couldn't close file %s: %m\n",
                        priv->mlfi_fname);

		rstat = SMFIS_TEMPFAIL;
		(void) unlink(priv->mlfi_fname);
	}
	else if (ok)
	{
		/* add a header to the message announcing our presence */
		if (gethostname(host, sizeof host) < 0)
			snprintf(host, sizeof host, "localhost");
		p = strrchr(priv->mlfi_fname, '/');
		if (p == NULL)
			p = priv->mlfi_fname;
		else
			p++;
		snprintf(hbuf, sizeof hbuf, "%s@%s", p, host);
		if (smfi_addheader(ctx, "X-Archived", hbuf) != MI_SUCCESS)
		{
			/* failed; we have to wait until later */
/*			fprintf(stderr,
				"Couldn't add header: X-Archived: %s\n",
				hbuf);
*/
                	syslog(LOG_ERR, "mlfi_cleanup Couldn't add header X-Archived %s: %m\n",
                        	hbuf);

			ok = FALSE;
			rstat = SMFIS_TEMPFAIL;
			(void) unlink(priv->mlfi_fname);
		}
	}
	else
	{
		/* message was aborted -- delete the archive file */
/*		fprintf(stderr, "Message aborted.  Removing %s\n",
			priv->mlfi_fname);
*/
                syslog(LOG_INFO, "mlfi_cleanup Message aborted. Removing %s: %m\n",
                        priv->mlfi_fname);

		rstat = SMFIS_TEMPFAIL;
		(void) unlink(priv->mlfi_fname);
	}

	/* release private memory */
	if (priv->mlfi_fname != NULL)
		free(priv->mlfi_fname);

	/* return status */
	return rstat;
}

sfsistat
mlfi_close(ctx)
	 SMFICTX *ctx;
{
	struct mlfiPriv *priv = MLFIPRIV;

	syslog(LOG_INFO, "mlfi_close called. %m\n");

	if (priv == NULL)
		return SMFIS_CONTINUE;
	if (priv->mlfi_connectfrom != NULL)
		free(priv->mlfi_connectfrom);
	if (priv->mlfi_helofrom != NULL)
		free(priv->mlfi_helofrom);
	free(priv);
	smfi_setpriv(ctx, NULL);
	return SMFIS_CONTINUE;
}

struct smfiDesc smfilter =
{
	"TMilter",	/* filter name */
	SMFI_VERSION,	/* version code -- do not change */
	SMFIF_ADDHDRS|SMFIF_ADDRCPT,
			/* flags */
	mlfi_connect,	/* connection info filter */
	mlfi_helo,	/* SMTP HELO command filter */
	mlfi_envfrom,	/* envelope sender filter */
	mlfi_envrcpt,	/* envelope recipient filter */
	mlfi_header,	/* header filter */
	mlfi_eoh,	/* end of header */
	mlfi_body,	/* body block filter */
	mlfi_eom,	/* end of message */
	mlfi_abort,	/* message aborted */
	mlfi_close,	/* connection cleanup */
};

static void
usage(prog)
	char *prog;
{
	fprintf(stderr,
		"Usage: %s [-d] -p socket-addr -u daemon-user [-t timeout]\n",
		prog);
}

int
main(argc, argv)
	int argc;
	char **argv;
{
	bool setconn = FALSE;
	bool dodaemon = FALSE;
	int c;
	const char *args = "dp:t:u:h";
	extern char *optarg;
	char *become = NULL;

	/* report to console, syslog LOG_DAEMON until we load */
	openlog("tmilter_daemon", LOG_CONS, LOG_DAEMON);

	/* Process command line options */
	while ((c = getopt(argc, argv, args)) != -1)
	{
		switch (c)
		{
		case 'p':
			if (optarg == NULL || *optarg == '\0')
			{
				(void) fprintf(stderr, "Illegal conn: %s\n",
					       optarg);
				exit(EX_USAGE);
			}
			if (smfi_setconn(optarg) == MI_FAILURE)
			{
				(void) fprintf(stderr,
					       "smfi_setconn failed\n");
				exit(EX_SOFTWARE);
			}

			/*
			**  If we're using a local socket, make sure it
			**  doesn't already exist.  Don't ever run this
			**  code as root!!
			*/

			if (strncasecmp(optarg, "unix:", 5) == 0)
				unlink(optarg + 5);
			else if (strncasecmp(optarg, "local:", 6) == 0)
				unlink(optarg + 6);
			setconn = TRUE;
			break;

		case 't':
			if (optarg == NULL || *optarg == '\0')
			{
				(void) fprintf(stderr, "Illegal timeout: %s\n",
					       optarg);
				exit(EX_USAGE);
			}
			if (smfi_settimeout(atoi(optarg)) == MI_FAILURE)
			{
				(void) fprintf(stderr,
					       "smfi_settimeout failed\n");
				exit(EX_SOFTWARE);
			}
			break;

		case 'u':
			if (optarg == NULL || *optarg == '\0')
                        {
                                (void) fprintf(stderr, "Illegal user name: %s\n",
                                               optarg);
                                exit(EX_USAGE);
                        }
			become = optarg;
			break;

		case 'd':
                        dodaemon = TRUE;
                        break;

		case 'h':
		default:
			usage(argv[0]);
			exit(EX_USAGE);
		}
	}
	if (!setconn)
	{
		fprintf(stderr, "%s: Missing required -p argument\n", argv[0]);
		usage(argv[0]);
		exit(EX_USAGE);
	}
	/* daemon mode if specified */
	if (dodaemon)
		daemonize("tmilter_daemon");
	/* change user if appropriate */
	if (become != NULL)
	{
		struct passwd *pw;

		pw = getpwnam(become);
		if (pw == NULL)
		{
			uid_t uid;
			gid_t gid;

			uid = atoi(become);
			if (uid != 0 && uid != LONG_MIN && uid != LONG_MAX)
				pw = getpwuid(uid);
			if (pw == NULL)
			{
				fprintf(stderr, "No such user `%s'\n",
				        become);

				exit(EX_USAGE);
			}
		}

		(void) endpwent();

		/* specified user's group, BEFORE losing priv's with user change */
		/* we apply user's primary group, without asking */
                if (setgid(pw->pw_gid) != 0)
                {
                        fprintf(stderr, "setgid(): %s\n",
                                strerror(errno));

                        exit(EX_USAGE);
                }

		/* set uid */ 
                if (setuid(pw->pw_uid) != 0)
                {
                        fprintf(stderr, "setuid(): %s\n",
                                strerror(errno));

                        exit(EX_USAGE);
                }
	}

	if (smfi_register(smfilter) == MI_FAILURE)
	{
		fprintf(stderr, "smfi_register failed\n");
		exit(EX_UNAVAILABLE);
	}

	/* close LOG_DAEMON syslog conn, change to LOG_EMAIL facility file */
	closelog();
	openlog("tmilter_daemon", LOG_CONS, LOG_MAIL);

	return smfi_main();
}

/* eof */
