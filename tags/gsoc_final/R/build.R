
build <- function(name,extra_deps,force=F) {
    # can't, and hence don't need to, build base packages
    if (name %in% base_pkgs) {
        return(T)
    }
    log_clear()
    dir <- setup()

    # obtain the Debian version-to-be
    version <- try(new_build_version(name))
    if (inherits(version,'try-error')) {
        error('failed to build',name)
        return(NULL)
    }

    result <- try((function() {
        if (!force && !needs_build(name,version)) {
            notice('skipping build of',name)
            return(NULL)
        }

        pkg <- prepare_new_debian(prepare_pkg(dir,name),extra_deps)
        if (pkg$debversion != version) {
            fail('expected Debian version',version,'not equal to actual version',pkg$debversion)
        }
        # delete the current archive (XXX: assumes mini-dinstall)
        for (subdir in c('mini-dinstall','unstable')) {
            path = file.path(dinstall_archive,subdir)
            if (file.exists(path)) {
                unlink(path,recursive=T)
            }
        }

        # delete notes of upload
        file.remove(Sys.glob(file.path(pbuilder_results,'*.upload')))

        # make mini-dinstall generate the skeleton of the archive
        ret = log_system('umask 022;mini-dinstall --batch -c',dinstall_config)
        if (ret != 0) {
            fail('failed to create archive')
        }

        # pull in all the R dependencies
        notice('dependencies:',paste(pkg$depends$r,collapse=', '))
        for (dep in pkg$depends$r) {
            if (pkgname_as_debian(dep) %in% debian_pkgs) {
                notice('using Debian package of',dep)
                next
            }
            # otherwise, convert to source package name
            srcdep = pkgname_as_debian(dep,binary=F)

            notice('uploading',srcdep)
            ret = log_system('umask 022;dput','-c',shQuote(dput_config),'local'
                        ,changesfile(srcdep))
            if (ret != 0) {
                fail('upload of dependency failed! maybe you did not build it first?')
            }
        }
        build_debian(pkg)

        # upload the package
        ret = log_system('umask 022;dput','-c',shQuote(dput_config),'local'
                    ,changesfile(pkg$srcname,pkg$debversion))
        if (ret != 0) {
            fail('upload failed!')
        }

        return(pkg$debversion)
    })())
    cleanup(dir)
    if (is.null(result)) {
        # nothing was done so escape asap.
        return(result)
    }

    # otherwise record progress
    failed = inherits(result,'try-error')
    if (failed) {
        error('failure of',name,'means these packages will fail:'
                     ,paste(r_dependency_closure(name,forward_arcs=F),collapse=', '))
    }
    db_record_build(name, version, log_retrieve(), !failed)
    return(!failed)
}

needs_build <- function(name,version) {
    # see if the last build was successful
    build <- db_latest_build(name)
    if (!is.null(build) && build$success) {
        # then something must have changed for us to attempt this
        # build
        if (build$r_version == version_upstream(version) &&
            build$deb_epoch == version_epoch(version) &&
            build$db_version == db_get_version()) {
            return(F)
        }
    } else {
        # always rebuild on failure or no record
        return(T)
    }
    # see if it has already been built
    srcname <- pkgname_as_debian(name,binary=F)
    debname <- pkgname_as_debian(name,binary=T)
    if (file.exists(changesfile(srcname, version))) {
        notice('already built',srcname,'version',version)
        return(F)
    }

    # XXX: what about building newer versions of Debian packages?
    if (debname %in% debian_pkgs) {
        notice(srcname,' exists in Debian (perhaps a different version)')
        return(F)
    }

    rm(debname,srcname)
    return(T)
}

build_debian <- function(pkg) {
    wd <- getwd()
    setwd(pkg$path)
    notice('building Debian package'
                 ,pkg$debname
                 ,paste('(',pkg$debversion,')',sep='')
                 ,'...')

    cmd = paste('pdebuild --configfile',shQuote(pbuilder_config))
    if (version_revision(pkg$debversion) > 2) {
        cmd = paste(cmd,'--debbuildopts','-sd')
        notice('build should exclude original source')
    }
    ret = log_system(cmd)
    setwd(wd)
    if (ret != 0) {
        fail('Failed to build package.')
    }
}

