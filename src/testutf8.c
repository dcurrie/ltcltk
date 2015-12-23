#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define BUFLEN 4096

static int probablyutf8seq(const char *seq, int len)
{
	int pos = 0;
	int ok = 1;
	char c;
	int uch = 0;
	if (len < 0) return 0;
	if (len == 0) return 1;
	while (ok && (pos < len)) {
		c = seq[pos++];
		if (c == 0) {	/* if this is used for sth other than Tcl, remove this first test. */
			ok = 0;
		} else if ((c & 0x80) != 0) { /* ASCII char and thus ok if == 0 */
			uch = c;
			if ((c & 0xE0) == 0xC0 && c != 0xC0 && c != 0xC1) { /* 2 byte sequence */
				if (pos < len) {
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
				} else
					ok = 0;
			} else if ((c & 0xF0) == 0xE0) { /* 3 byte sequence */
				if (pos+1 < len) {
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
				} else
					ok = 0;
			} else if ((c & 0xF8) == 0xF0 && c <= 0xF4) { /* 4 byte sequence */
				if (pos+2 < len) {
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
					ok = ok && ((seq[pos++] & 0xC0) == 0x80);
				} else
					ok = 0;
			} else
				ok = 0;
		} else
			uch = c;
	}
	return ok;
}

int main(int argc, char **argv)
{
	FILE *f = 0;
	char buf[BUFLEN];
	int len = 0;
	int lineno = 0;
	int ok = 1;

	if (argc != 2) {
		fprintf(stderr, "%s <filename>\n", argv[0]);
		exit(1);
	}
	
	f = fopen(argv[1], "r");
	if (!f) {
		fprintf(stderr, "can't open file %s for reading.\n", argv[1]);
		exit(1);
	}
	
	while (fgets(buf, BUFLEN, f)) {
		len = strlen(buf);
		lineno++;
		#if TIMEIT
		ok = ok && probablyutf8seq(buf, len);
		#else
		printf("Line %05d: ", lineno); 
		if (ok = ok && probablyutf8seq(buf, len))
			puts("ok");
		else
			puts("nok");
		#endif
	}
	
	fclose(f);
	exit(0);
}
