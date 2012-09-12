# Copyright 1999-2012 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header: $

EAPI="3"
VIRTUALX_REQUIRED="pgo"
WANT_AUTOCONF="2.1"
MOZ_ESR=""

MY_PN="firefox"
MOZ_P="${MY_PN}-${PV}"

if [[ ${MOZ_ESR} == 1 ]]; then
	# ESR releases have slightly version numbers
	MOZ_P="${MOZ_P}esr"
fi

# Patch version
PATCH="${MY_PN}-15.0-patches-0.2"
# Upstream ftp release URI that's used by mozlinguas.eclass
# We don't use the http mirror because it deletes old tarballs.
MOZ_FTP_URI="ftp://ftp.mozilla.org/pub/${MY_PN}/releases/"

inherit check-reqs flag-o-matic toolchain-funcs eutils gnome2-utils mozconfig-3 multilib pax-utils fdo-mime autotools python virtualx

DESCRIPTION="Torbrowser without vidalia or tor"
HOMEPAGE="https://www.torproject.org/projects/torbrowser.html.en"

# may work on other arches, but untested
KEYWORDS=""
SLOT="0"
# BSD license applies to torproject-related code like the patches
# icons are under CCPL-Attribution-3.0
LICENSE="|| ( MPL-1.1 GPL-2 LGPL-2.1 )
	BSD
	CCPL-Attribution-3.0"
IUSE="bindist gstreamer +ipc +jit pgo selinux system-sqlite +torprofile +webm"

SRC_URI="${SRC_URI}
	http://dev.gentoo.org/~nirbheek/mozilla/patchsets/${PATCH}.tar.xz
	${MOZ_FTP_URI}/${PV}/source/${MOZ_P}.source.tar.bz2
	http://gitweb.torproject.org/${PN}.git/blob_plain/HEAD:/build-scripts/branding/default256.png -> torbrowser256.png"

ASM_DEPEND=">=dev-lang/yasm-1.1"

# Mesa 7.10 needed for WebGL + bugfixes
RDEPEND="
	>=sys-devel/binutils-2.16.1
	>=dev-libs/nss-3.13.6
	>=dev-libs/nspr-4.9.2
	>=dev-libs/glib-2.26:2
	>=media-libs/mesa-7.10
	>=media-libs/libpng-1.5.9[apng]
	virtual/libffi
	gstreamer? (
		>=media-libs/gstreamer-0.10.33:0.10
		>=media-libs/gst-plugins-base-0.10.33:0.10 )
	system-sqlite? ( >=dev-db/sqlite-3.7.12.1[fts3,secure-delete,threadsafe,unlock-notify,debug=] )
	webm? ( >=media-libs/libvpx-1.0.0
		media-libs/alsa-lib )
	selinux? ( sec-policy/selinux-mozilla )"
# We don't use PYTHON_DEPEND/PYTHON_USE_WITH for some silly reason
DEPEND="${RDEPEND}
	virtual/pkgconfig
	pgo? (
		=dev-lang/python-2*[sqlite]
		>=sys-devel/gcc-4.5 )
	webm? ( x86? ( ${ASM_DEPEND} )
		amd64? ( ${ASM_DEPEND} )
		virtual/opengl )"
PDEPEND="torprofile? ( =www-misc/torbrowser-profile-2.3.22_alpha1 )"

if [[ ${MOZ_ESR} == 1 ]]; then
	S="${WORKDIR}/mozilla-esr${PV%%.*}"
else
	S="${WORKDIR}/mozilla-release"
fi

QA_PRESTRIPPED="usr/$(get_libdir)/${PN}/${MY_PN}/firefox"

pkg_setup() {
	moz_pkgsetup

	# Avoid PGO profiling problems due to enviroment leakage
	# These should *always* be cleaned up anyway
	unset DBUS_SESSION_BUS_ADDRESS \
		DISPLAY \
		ORBIT_SOCKETDIR \
		SESSION_MANAGER \
		XDG_SESSION_COOKIE \
		XAUTHORITY

	if ! use bindist; then
		einfo
		elog "You are enabling official branding. You may not redistribute this build"
		elog "to any users on your network or the internet. Doing so puts yourself into"
		elog "a legal problem with Mozilla Foundation"
		elog "You can disable it by emerging ${PN} _with_ the bindist USE-flag"
	fi

	if use pgo; then
		einfo
		ewarn "You will do a double build for profile guided optimization."
		ewarn "This will result in your build taking at least twice as long as before."
	fi

	# Ensure we have enough disk space to compile
	if use pgo || use debug || use test ; then
		CHECKREQS_DISK_BUILD="8G"
	else
		CHECKREQS_DISK_BUILD="4G"
	fi
	check-reqs_pkg_setup
}

src_prepare() {
	# Apply our patches
	EPATCH_SUFFIX="patch" \
	EPATCH_FORCE="yes" \
	epatch "${WORKDIR}/firefox"

	# Torbrowser patches for firefox 10.0.5esr, check regularly/for every version-bump
	# https://gitweb.torproject.org/torbrowser.git/history/HEAD:/src/current-patches
	# exclude vidalia patch, cause we don't force the user to use it
	EPATCH_EXCLUDE="0012-Make-Tor-Browser-exit-when-not-launched-from-Vidalia.patch" \
	EPATCH_SUFFIX="patch" \
	EPATCH_FORCE="yes" \
	epatch "${FILESDIR}/${PN}-alpha-patches"

	# Allow AAC and H.264 files to be played using <audio> and <video>
	epatch "${FILESDIR}"/${MY_PN}*-gst*.patch

	# Allow user to apply any additional patches without modifing ebuild
	epatch_user

	# Enable gnomebreakpad
	if use debug ; then
		sed -i -e "s:GNOME_DISABLE_CRASH_DIALOG=1:GNOME_DISABLE_CRASH_DIALOG=0:g" \
			"${S}"/build/unix/run-mozilla.sh || die "sed failed!"
	fi

	# Disable gnomevfs extension
	sed -i -e "s:gnomevfs::" "${S}/"browser/confvars.sh \
		-e "s:gnomevfs::" "${S}/"xulrunner/confvars.sh \
		|| die "Failed to remove gnomevfs extension"

	# Ensure that plugins dir is enabled as default
	# and is different from firefox-location
	sed -i -e "s:/usr/lib/mozilla/plugins:/usr/$(get_libdir)/${PN}/${MY_PN}/plugins:" \
		"${S}"/xpcom/io/nsAppFileLocationProvider.cpp || die "sed failed to replace plugin path!"

	# Fix sandbox violations during make clean, bug 372817
	sed -e "s:\(/no-such-file\):${T}\1:g" \
		-i "${S}"/config/rules.mk \
		-i "${S}"/js/src/config/rules.mk \
		-i "${S}"/nsprpub/configure{.in,} \
		|| die

	#Fix compilation with curl-7.21.7 bug 376027
	sed -e '/#include <curl\/types.h>/d'  \
		-i "${S}"/toolkit/crashreporter/google-breakpad/src/common/linux/http_upload.cc \
		-i "${S}"/toolkit/crashreporter/google-breakpad/src/common/linux/libcurl_wrapper.cc \
		-i "${S}"/config/system-headers \
		-i "${S}"/js/src/config/system-headers || die "Sed failed"

	# Don't exit with error when some libs are missing which we have in
	# system.
	sed '/^MOZ_PKG_FATAL_WARNINGS/s@= 1@= 0@' \
		-i "${S}"/browser/installer/Makefile.in || die

	# Don't error out when there's no files to be removed:
	sed 's@\(xargs rm\)$@\1 -f@' \
		-i "${S}"/toolkit/mozapps/installer/packager.mk || die

	eautoreconf
}

src_configure() {
	MOZILLA_FIVE_HOME="/usr/$(get_libdir)/${PN}/${MY_PN}"
	MEXTENSIONS="default"

	####################################
	#
	# mozconfig, CFLAGS and CXXFLAGS setup
	#
	####################################

	mozconfig_init
	mozconfig_config

	mozconfig_annotate '' --prefix="${EPREFIX}"/usr
	mozconfig_annotate '' --libdir="${EPREFIX}"/usr/$(get_libdir)/${PN}
	mozconfig_annotate '' --enable-extensions="${MEXTENSIONS}"
	mozconfig_annotate '' --disable-gconf
	mozconfig_annotate '' --disable-mailnews
	mozconfig_annotate '' --enable-canvas
	mozconfig_annotate '' --enable-safe-browsing
	mozconfig_annotate '' --with-system-png
	mozconfig_annotate '' --enable-system-ffi

	# Other ff-specific settings
	mozconfig_annotate '' --with-default-mozilla-five-home=${MOZILLA_FIVE_HOME}
	mozconfig_annotate '' --target="${CTARGET:-${CHOST}}"

	mozconfig_use_enable gstreamer
	mozconfig_use_enable system-sqlite
	# Both methodjit and tracejit conflict with PaX
	mozconfig_use_enable jit methodjit
	mozconfig_use_enable jit tracejit

	# Allow for a proper pgo build
	if use pgo; then
		echo "mk_add_options PROFILE_GEN_SCRIPT='\$(PYTHON) \$(OBJDIR)/_profile/pgo/profileserver.py'" >> "${S}"/.mozconfig
	fi

	# Finalize and report settings
	mozconfig_final

	if [[ $(gcc-major-version) -lt 4 ]]; then
		append-cxxflags -fno-stack-protector
	elif [[ $(gcc-major-version) -gt 4 || $(gcc-minor-version) -gt 3 ]]; then
		if use amd64 || use x86; then
			append-flags -mno-avx
		fi
	fi
}

src_compile() {
	if use pgo; then
		addpredict /root
		addpredict /etc/gconf
		# Reset and cleanup environment variables used by GNOME/XDG
		gnome2_environment_reset

		# Firefox tries to use dri stuff when it's run, see bug 380283
		shopt -s nullglob
		cards=$(echo -n /dev/dri/card* | sed 's/ /:/g')
		if test -n "${cards}"; then
			# FOSS drivers are fine
			addpredict "${cards}"
		else
			cards=$(echo -n /dev/ati/card* /dev/nvidiactl* | sed 's/ /:/g')
			if test -n "${cards}"; then
				# Binary drivers seem to cause access violations anyway, so
				# let's use indirect rendering so that the device files aren't
				# touched at all. See bug 394715.
				export LIBGL_ALWAYS_INDIRECT=1
			fi
		fi
		shopt -u nullglob

		CC="$(tc-getCC)" CXX="$(tc-getCXX)" LD="$(tc-getLD)" \
		MOZ_MAKE_FLAGS="${MAKEOPTS}" \
		Xemake -f client.mk profiledbuild || die "Xemake failed"
	else
		CC="$(tc-getCC)" CXX="$(tc-getCXX)" LD="$(tc-getLD)" \
		MOZ_MAKE_FLAGS="${MAKEOPTS}" \
		emake -f client.mk || die "emake failed"
	fi
}

src_install() {
	MOZILLA_FIVE_HOME="/usr/$(get_libdir)/${PN}/${MY_PN}"

	# MOZ_BUILD_ROOT, and hence OBJ_DIR change depending on arch, compiler, pgo, etc.
	local obj_dir="$(echo */config.log)"
	obj_dir="${obj_dir%/*}"
	cd "${S}/${obj_dir}"

	# Without methodjit and tracejit there's no conflict with PaX
	if use jit; then
		# Pax mark xpcshell for hardened support, only used for startupcache creation.
		pax-mark m "${S}/${obj_dir}"/dist/bin/xpcshell
	fi

	MOZ_MAKE_FLAGS="${MAKEOPTS}" \
	emake DESTDIR="${D}" install || die "emake install failed"

	# remove default symlink in /usr/bin, because we add a proper wrapper-script later
	rm "${ED}"/usr/bin/${MY_PN} || die "Failed to remove binary-symlink"
	# we dont want development stuff for this kind of build, might as well
	# conflict with other firefox-builds
	rm -rf "${ED}"/usr/include "${ED}${MOZILLA_FIVE_HOME}"/{idl,include,lib,sdk} || \
		die "Failed to remove sdk and headers"

	# Without methodjit and tracejit there's no conflict with PaX
	if use jit; then
		# Required in order to use plugins and even run firefox on hardened.
		pax-mark m "${ED}"${MOZILLA_FIVE_HOME}/{firefox,firefox-bin}
	fi

	# Plugin-container needs to be pax-marked for hardened to ensure plugins such as flash
	# continue to work as expected.
	pax-mark m "${ED}"/usr/$(get_libdir)/${PN}/${MY_PN}/plugins

	# Plugins dir
	keepdir /usr/$(get_libdir)/${PN}/${MY_PN}/plugins

	# create wrapper to start torbrowser
	# the class value should match the name of the desktop entry
	make_wrapper ${PN} "/usr/$(get_libdir)/${PN}/${MY_PN}/${MY_PN} --class torbrowser-torbrowser -no-remote -profile ~/.${PN}/profile"

	newicon -s 256 "${DISTDIR}"/${PN}256.png ${PN}.png
	make_desktop_entry ${PN} "Torbrowser" ${PN} "Network;WebBrowser"
}

pkg_preinst() {
	gnome2_icon_savelist
}

pkg_postinst() {
	ewarn "This patched firefox build is _NOT_ recommended by TOR upstream but uses"
	ewarn "the exact same patches (excluding Vidalia-patch). Use this only if you know"
	ewarn "what you are doing!"
	einfo ""
	if use torprofile ; then
		elog "Copy the folder contents from /usr/share/${PN}/profile (installed by"
		elog "www-misc/torbrowser-profile) into ~/.${PN}/profile and run '${PN}'."
		einfo
		elog "This profile folder includes pre-configuration recommended by upstream,"
		elog "as well as the extensions Torbutton, NoScript and HTTPS-Everywhere."
		elog "If you want to start from scratch just create the directories '~/.${PN}/profile'."
	fi
	einfo
	elog "The update check when you first start ${PN} does not recognize this version."
	einfo

	# Update mimedb for the new .desktop file
	fdo-mime_desktop_database_update
	gnome2_icon_cache_update
}

pkg_postrm() {
	gnome2_icon_cache_update
}
