/* config.h for the liblouis sources vendored in VoiceOver Audio Split.
 *
 * liblouis 3.39.0, from the official release tarball
 * https://github.com/liblouis/liblouis/releases/download/v3.39.0/liblouis-3.39.0.tar.gz
 * (sha256 629fa8cb0dfd9ad457c5bf47a42f0953b673e62c8ad6b1d03ddc4e2bd20008f1).
 * Licensed under the GNU Lesser General Public License 2.1 or later (COPYING.LESSER).
 *
 * Written by hand instead of by ./configure: the library itself only needs the
 * version and a table directory. liblouis.h is liblouis.h.in with
 * @WIDECHAR_TYPE@ set to the default (16-bit widechars, as without --enable-ucs4).
 * The tables are bundled in the app under Resources/BrailleTables, and the app
 * sets that path at runtime with lou_setDataPath, so TABLESDIR is only a fallback.
 * Only the library sources are vendored (no tools, tests or gnulib).
 */

#ifndef LOUISCFG_H
#define LOUISCFG_H

#define PACKAGE "liblouis"
#define PACKAGE_NAME "liblouis"
#define PACKAGE_VERSION "3.39.0"
#define VERSION "3.39.0"

#ifndef TABLESDIR
#define TABLESDIR ""
#endif

/* Xcode's Debug configuration defines DEBUG, which would switch on liblouis's
 * own debugging code; keep the library the same in every build. */
#undef DEBUG

#endif /* LOUISCFG_H */
