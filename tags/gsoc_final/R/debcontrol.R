get_dependencies <- function(pkg,extra_deps) {
    # determine dependencies
    dependencies <- r_dependencies_of(description=pkg$description)
    depends <- list()
    # these are used for generating the Depends fields
    as_deb <- function(r,build) {
        return(pkgname_as_debian(paste(dependencies[r,]$name)
                                ,version=dependencies[r,]$version
                                ,repopref=pkg$repo
                                ,build=build))
    }
    depends$bin <- lapply(rownames(dependencies), as_deb, build=F)
    depends$build <- lapply(rownames(dependencies), as_deb, build=T)
    # add the command line dependencies
    depends$bin = c(extra_deps$deb,depends$bin)
    depends$build = c(extra_deps$deb,depends$build)
    # add the system requirements
    if ('SystemRequirements' %in% colnames(pkg$description)) {
        sysreq <- sysreqs_as_debian(pkg$description[1,'SystemRequirements'])
        depends$bin = c(sysreq$bin,depends$bin)
        depends$build = c(sysreq$build,depends$build)
    }

    forced <- forced_deps_as_debian(pkg$name)
    if (length(forced)) {
        depends$bin = c(forced$bin,depends$bin)
        depends$build = c(forced$build,depends$build)
    }

    # make sure we depend upon R in some way...
    if (!length(grep('^r-base',depends$build))) {
        depends$build = c(depends$build,pkgname_as_debian('R',version='>= 2.7.0',build=T))
        depends$bin   = c(depends$bin,  pkgname_as_debian('R',version='>= 2.7.0',build=F))
    }
    # also include stuff to allow tcltk to build (suggested by Dirk)
    depends$build = c(depends$build,'xvfb','xauth','xfonts-base')

    # make all bin dependencies build dependencies.
    depends$build = c(depends$build, depends$bin)

    # remove duplicates
    depends <- lapply(depends,unique)

    # append the Debian dependencies
    depends$build=c(depends$build,'debhelper (>> 4.1.0)','cdbs')
    if (pkg$archdep) {
        depends$bin=c(depends$bin,'${shlibs:Depends}')
    }

    # the names of dependent source packages (to find the .changes file to
    # upload via dput). these can be found recursively.
    depends$r = r_dependency_closure(dependencies)
    # append command line dependencies
    depends$r = c(extra_deps$r, depends$r)
    return(depends)
}

sysreqs_as_debian <- function(sysreq_text) {
    # form of this field is unspecified (ugh) but most people seem to stick
    # with this
    aliases <- c()
    sysreq_text <- gsub('[[:space:]]and[[:space:]]',' , ',tolower(sysreq_text))
    for (sysreq in strsplit(sysreq_text,'[[:space:]]*,[[:space:]]*')[[1]]) {
        startreq = sysreq
        # constant case
        sysreq = tolower(sysreq)
        # drop version information/comments for now
        sysreq = gsub('[[][^])]*[]]','',sysreq)
        sysreq = gsub('\\([^)]*\\)','',sysreq)
        sysreq = gsub('[[][^])]*[]]','',sysreq)
        sysreq = gsub('version','',sysreq)
        sysreq = gsub('from','',sysreq)
        sysreq = gsub('[<>=]*[[:space:]]*[[:digit:]]+[[:digit:].+:~-]*','',sysreq)
        # byebye URLs
        sysreq = gsub('(ht|f)tps?://[[:alnum:]!?*"\'(),%$_@.&+/=-]*','',sysreq)
        # squish out space
        sysreq = chomp(gsub('[[:space:]]+',' ',sysreq))
        alias <- db_sysreq_override(sysreq)
        if (is.null(alias)) {
            error('do not know what to do with SystemRequirement:',sysreq)
            error('original SystemRequirement:',startreq)
            fail('unmet system requirement')
        }
        notice('mapped SystemRequirement',startreq,'onto',alias,'via',sysreq)
        aliases = c(aliases,alias)
    }
    return(map_aliases_to_debian(aliases))
}

forced_deps_as_debian <- function(r_name) {
    aliases <- db_get_forced_depends(r_name)
    return(map_aliases_to_debian(aliases))
}

map_aliases_to_debian <- function(aliases) {
    if (!length(aliases)) {
        return(aliases)
    }
    debs <- list()
    debs$bin = unlist(sapply(aliases, db_get_depends))
    debs$build = unlist(sapply(aliases, db_get_depends, build=T))
    debs$bin = debs$bin[debs$bin != 'build-essential']
    debs$build = debs$build[debs$build != 'build-essential']
    return(debs)
}

generate_control <- function(pkg) {
    # construct control file
    control = data.frame()
    control[1,'Source'] = pkg$srcname
    control[1,'Section'] = 'math'
    control[1,'Priority'] = 'optional'
    control[1,'Maintainer'] = maintainer
    control[1,'Build-Depends'] = paste(pkg$depends$build,collapse=', ')
    control[1,'Standards-Version'] = '3.8.0'

    control[2,'Package'] = pkg$debname
    control[2,'Architecture'] = 'all'
    if (pkg$archdep) {
        control[2,'Architecture'] = 'any'
    }
    control[2,'Depends'] = paste(pkg$depends$bin,collapse=', ')

#   # bundles provide virtual packages of their contents
#   # unnecessary for now; cran2deb converts R bundles itself
#    if (pkg$is_bundle) {
#        control[2,'Provides'] = paste(
#                    lapply(r_bundle_contains(pkg$name)
#                          ,function(name) return(pkgname_as_debian(paste(name)
#                                                                  ,repopref=pkg$repo)))
#                          ,collapse=', ')
#    }

    # generate the description
    descr = 'GNU R package "'
    if ('Title' %in% colnames(pkg$description)) {
        descr = paste(descr,pkg$description[1,'Title'],sep='')
    } else {
        descr = paste(descr,pkg$name,sep='')
    }
    if (pkg$is_bundle) {
        long_descr <- pkg$description[1,'BundleDescription']
    } else {
        long_descr <- pkg$description[1,'Description']
    }
    # using \n\n.\n\n is not very nice, but is necessary to make sure
    # the longer description does not begin on the synopsis line --- R's
    # write.dcf does not appear to have a nicer way of doing this.
    descr = paste(descr,'"\n\n', long_descr, sep='')
    if ('URL' %in% colnames(pkg$description)) {
        descr = paste(descr,'\n\nURL: ',pkg$description[1,'URL'],sep='')
    }
    control[2,'Description'] = descr

    # Debian policy says 72 char width; indent minimally
    write.dcf(control,file=pkg$debfile('control.in'),indent=1,width=72)
}

