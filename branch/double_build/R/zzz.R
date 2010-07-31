.First.lib <- function(libname, pkgname) {
    global <- function(name,value) assign(name,value,envir=.GlobalEnv)
    global("which_system", Sys.getenv('CRAN2DEB_SYS','debian'))
    if (!length(grep('^[a-z]+$',which_system))) {
        stop('Invalid system specification: must be of the form name')
    }
    global("maintainer", 'cran2deb autobuild <cran2deb@gmail.com>')
    global("root", system.file(package='cran2deb'))
    global("cache_root", '/var/cache/cran2deb')
    global("indep_arch", "all")
    global("archs", c("i386", "amd64"))
    # get the pbuilder results dir, and config
    global("get_pbuilder_config", function(arch) {
        sys_arch <- paste(which_system, arch, sep='-')
        return(c(file.path('/var/cache/cran2deb/results',sys_arch))
                ,file.path('/etc/cran2deb/sys',sys_arch,'pbuilderrc'))
    })
    global("reprepro_dir", file.path('/var/www/repo',which_system))
    global("get_reprepro_orig_tgz", function(srcname, version) {
        return file.path(reprepro_dir, 'pool', 'main', substr(srcname, 1, 1),
                            srcname, paste(srcname,'_',version,'.orig.tar.gz',
                                           sep=''))
    })
    global("r_depend_fields", c('Depends','Imports')) # Suggests, Enhances
    global("scm_revision", paste("svn:", svnversion()))
    global("patch_dir", '/etc/cran2deb/patches')
    global("lintian_dir", '/etc/cran2deb/lintian')
    global("changesfile", function(srcname,version='*',arch='*') {
        return(file.path(pbuilder_results
                        ,paste(srcname,'_',version,'_'
                              ,arch,'.changes',sep='')))
    })
    global("version_suffix","cran")
    # perhaps db_cur_version() should be used instead?
    global("version_suffix_step",1)

    cache <- file.path(cache_root,'cache.rda')
    if (file.exists(cache)) {
        load(cache,envir=.GlobalEnv)
    }
    message(paste('I: cran2deb',scm_revision,'building for',which_system,'at',Sys.time()))
}
