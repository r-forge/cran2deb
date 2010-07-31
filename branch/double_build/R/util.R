iterate <- function(xs,z,fun) {
    y <- z
    for (x in xs)
        y <- fun(y,x)
    return(y)
}

chomp <- function(x) {
    # remove leading and trailing spaces
    return(sub('^[[:space:]]+','',sub('[[:space:]]+$','',x)))
}

err <- function(...) {
    error(...)
    exit()
}

exit <- function() {
    q(save='no')
}
