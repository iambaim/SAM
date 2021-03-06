##' reduce helper function to reduce data
##' @param data a data object as returned by the function setup.sam.data
##' @param year a vector of years to be excluded.  
##' @param fleet a vector of fleets to be excluded.
##' @param age a vector of ages fleets to be excluded.
##' @param conf an optional corresponding configuration to be modified along with the data change. Modified is returned as attribute "conf"  
##' @details When more than one vector is supplied they need to be of same length, as only the pairs are excluded
##' @export
reduce<-function(data, year=NULL, fleet=NULL, age=NULL, conf=NULL){
  nam<-c("year", "fleet", "age")[c(length(year)>0,length(fleet)>0,length(age)>0)]
  if((length(year)==0) & (length(fleet)==0) & (length(age)==0)){
    idx <- rep(TRUE,nrow(data$aux))
  }else{
    idx <- !do.call(paste, as.data.frame(data$aux[,nam,drop=FALSE])) %in% do.call(paste, as.data.frame(cbind(year=year, fleet=fleet, age=age)))
  }
  data$aux <- data$aux[idx,]
  data$logobs <- data$logobs[idx]
  suf <- sort(unique(data$aux[,"fleet"])) # sort-unique-fleet
  data$noFleets <- length(suf)
  data$fleetTypes <- data$fleetTypes[suf]
  data$sampleTimes <- data$sampleTimes[suf]
  data$years <- min(as.numeric(data$aux[,"year"])):max(as.numeric(data$aux[,"year"]))
  ages <- min(as.numeric(data$aux[,"age"])):max(as.numeric(data$aux[,"age"]))
  data$noYears <- length(data$years)
  mmfun<-function(f,y, ff){idx<-which(data$aux[,"year"]==y & data$aux[,"fleet"]==f); ifelse(length(idx)==0, NA, ff(idx)-1)}
  data$idx1 <- outer(suf, data$years, Vectorize(mmfun,c("f","y")), ff=min)
  data$idx2 <- outer(suf, data$years, Vectorize(mmfun,c("f","y")), ff=max)
  data$nobs <- length(data$logobs[idx])  
  data$propMat <- data$propMat[rownames(data$propMat)%in%data$years, colnames(data$propMat)%in%ages]
  data$stockMeanWeight <- data$stockMeanWeight[rownames(data$stockMeanWeight)%in%data$years, colnames(data$stockMeanWeight)%in%ages]
  data$natMor <- data$natMor[rownames(data$natMor)%in%data$years, colnames(data$natMor)%in%ages]
  data$propF <- data$propF[rownames(data$propF)%in%data$years, colnames(data$propF)%in%ages]
  data$propM <- data$propM[rownames(data$propM)%in%data$years, colnames(data$propM)%in%ages]
  data$landFrac <- data$landFrac[rownames(data$landFrac)%in%data$years, colnames(data$landFrac)%in%ages]  
  data$catchMeanWeight <- data$catchMeanWeight[rownames(data$catchMeanWeight)%in%data$years, colnames(data$catchMeanWeight)%in%ages]
  data$disMeanWeight <- data$disMeanWeight[rownames(data$disMeanWeight)%in%data$years, colnames(data$disMeanWeight)%in%ages]
  data$landMeanWeight <- data$landMeanWeight[rownames(data$landMeanWeight)%in%data$years, colnames(data$landMeanWeight)%in%ages]
  data$aux[,"fleet"] <- match(data$aux[,"fleet"],suf)
  data$minAgePerFleet <- tapply(as.integer(data$aux[,"age"]), INDEX=data$aux[,"fleet"], FUN=min)
  data$maxAgePerFleet <- tapply(as.integer(data$aux[,"age"]), INDEX=data$aux[,"fleet"], FUN=max)
  attr(data,"fleetNames") <- attr(data,"fleetNames")[suf]
  if(!missing(conf)){
    .reidx <- function(x){
      if(any(x >= (-0.5))){
        xx <- x[x >= (-.5)]
        x[x >= (-.5)] <- match(xx,sort(unique(xx)))-1
      };
      x
    }
    conf$keyLogFsta <- .reidx(conf$keyLogFsta[suf,,drop=FALSE])
    conf$keyLogFpar <- .reidx(conf$keyLogFpar[suf,,drop=FALSE])
    conf$keyQpow <- .reidx(conf$keyQpow[suf,,drop=FALSE])
    conf$keyVarF <- .reidx(conf$keyVarF[suf,,drop=FALSE])
    conf$keyVarObs <- .reidx(conf$keyVarObs[suf,,drop=FALSE])
    conf$obsCorStruct <- conf$obsCorStruct[suf]
    conf$keyCorObs <- conf$keyCorObs[suf,,drop=FALSE]
    yidx <- conf$keyScaledYears%in%data$aux[data$aux[,'fleet']==1,'year']
    if(length(conf$keyScaledYears)>0){
      conf$noScaledYears <- sum(yidx)
      conf$keyScaledYears <- as.vector(conf$keyScaledYears)[yidx]
      conf$keyParScaledYA <- .reidx(conf$keyParScaledYA[yidx,,drop=FALSE])
    }
    conf$obsLikelihoodFlag <- conf$obsLikelihoodFlag[suf]
    attr(data, "conf") <- conf
  }
  data
}


##' runwithout helper function
##' @param fit a fitted model object as returned from sam.fit
##' @param year a vector of years to be excluded.  When both fleet and year are supplied they need to be of same length, as only the pairs are excluded
##' @param fleet a vector of fleets to be excluded.  When both fleet and year are supplied they need to be of same length, as only the pairs are excluded
##' @param ... extra arguments to sam.fit
##' @details ...
##' @export
runwithout <- function(fit, year=NULL, fleet=NULL, ...){
  data <- reduce(fit$data, year=year, fleet=fleet, conf=fit$conf)      
  conf <- attr(data, "conf")
  par <- defpar(data,conf)
  ret <- sam.fit(data, conf, par, rm.unidentified=TRUE, ...)
  return(ret)
}

##' retro run 
##' @param fit a fitted model object as returned from sam.fit
##' @param year either 1) a single integer n in which case runs where all fleets are reduced by 1, 2, ..., n are returned, 2) a vector of years in which case runs where years from and later are excluded for all fleets, and 3 a matrix of years were each column is a fleet and each column corresponds to a run where the years and later are excluded.    
##' @param ncores the number of cores to attemp to use
##' @param ... extra arguments to \code{\link{sam.fit}}
##' @details ...
##' @importFrom parallel detectCores makeCluster clusterEvalQ parLapply stopCluster
##' @export
retro <- function(fit, year=NULL, ncores=detectCores(), ...){
  data <- fit$data
  y <- fit$data$aux[,"year"]
  f <- fit$data$aux[,"fleet"]
  suf <- sort(unique(f))
  maxy <- sapply(suf, function(ff)max(y[f==ff]))
  if(length(year)==1){
    mat <- sapply(suf,function(ff){my<-maxy[ff];my:(my-year+1)})
  }
  if(is.vector(year) & length(year)>1){
    mat <- sapply(suf,function(ff)year)
  }
  if(is.matrix(year)){
    mat <- year
  }

  if(nrow(mat)>length(unique(y)))stop("The number of retro runs exceeds number of years")
  if(ncol(mat)!=length(suf))stop("Number of retro fleets does not match")

  setup <- lapply(1:nrow(mat),function(i)do.call(rbind,lapply(suf,function(ff)cbind(mat[i,ff]:maxy[ff], ff))))
  cl <- makeCluster(ncores) #set up nodes
  clusterEvalQ(cl, {library(stockassessment)}) #load the package to each node
  runs <- parLapply(cl, setup, function(s)runwithout(fit, year=s[,1], fleet=s[,2], ...))
  stopCluster(cl) #shut it down
  attr(runs, "fit") <- fit
  class(runs)<-"samset"
  runs
}

##' leaveout run 
##' @param fit a fitted model object as returned from sam.fit
##' @param fleet a list of vectors. Each element in the list specifies a run where the fleets mentioned are omitted 
##' @param ncores the number of cores to attemp to use
##' @param ... extra arguments to \code{\link{sam.fit}}
##' @details ...
##' @importFrom parallel detectCores makeCluster clusterEvalQ parLapply stopCluster
##' @export
leaveout <- function(fit, fleet=as.list(2:fit$data$noFleets), ncores=detectCores(), ...){
#  runs <- mclapply(fleet, function(f)runwithout(fit, fleet=f, ...), mc.cores=ncores, mc.silent=mc.silent)
  cl <- makeCluster(ncores) #set up nodes
  clusterEvalQ(cl, {library(stockassessment)}) #load the package to each node
  runs <- parLapply(cl, fleet, function(f)runwithout(fit, fleet=f, ...))
  stopCluster(cl) #shut it down
  names(runs) <- paste0("w.o. ", lapply(fleet, function(x)paste(attr(fit$data,"fleetNames")[x], collapse=" and ")))
  attr(runs, "fit") <- fit
  class(runs)<-"samset"
  runs
}
