referencePrepare <-
function( outFileTranscriptsAnnotation="",
	annotateGeneIds=TRUE, 
	u12IntronsChr=c(), u12IntronsBeg=c(), u12IntronsEnd=c(),
	u12IntronsRef,
	collapseExons=TRUE, sourceBuild="UCSC", ucscGenome="hg19",
	ucscTableName="knownGene",
	ucscUrl="http://genome-euro.ucsc.edu/cgi-bin/",
	biomart="ENSEMBL_MART_ENSEMBL",
	biomartDataset="hsapiens_gene_ensembl",
	biomartTranscriptIds=NULL, biomartExtraFilters=NULL,
	biomartIdPrefix="ensembl_", biomartHost="www.ensembl.org",
	biomartPort=80, circSeqs="", miRBaseBuild=NA, taxonomyId=NA,
	filePath="", fileFormat=c("auto", "gff3", "gtf"), fileDatSrc=NA,
	fileOrganism=NA, fileChrInf=NULL, 
	fileDbXrefTag=c(), addCollapsedTranscripts=TRUE, 
	ignore.strand=FALSE)
{

	if(circSeqs[1]=="")
		circSeqs<- NULL
#		circSeqs=GenomicFeatures::DEFAULT_CIRC_SEQS

	if(sourceBuild=="UCSC"){
		human.txdb <- txdbmaker::makeTxDbFromUCSC(genome=ucscGenome,
			tablename=ucscTableName, circ_seqs=circSeqs, url=ucscUrl,
			taxonomyId=taxonomyId)
	} else if (sourceBuild=="biomaRt"){
		human.txdb <- txdbmaker::makeTxDbFromBiomart(biomart=biomart,
			dataset=biomartDataset,
			transcript_ids=biomartTranscriptIds,
			circ_seqs=circSeqs,
			filter=biomartExtraFilters,
			id_prefix=biomartIdPrefix,
			host=biomartHost,
			port=biomartPort,
			miRBaseBuild=miRBaseBuild,
			taxonomyId=taxonomyId)
	}else if (sourceBuild=="file"){
		if(length(fileDbXrefTag)==0){
			human.txdb <- txdbmaker::makeTxDbFromGFF(file=filePath,
				format=fileFormat,
				dataSource=fileDatSrc, organism=fileOrganism,
				taxonomyId=taxonomyId,
				circ_seqs=circSeqs, chrominfo=fileChrInf,
				miRBaseBuild=miRBaseBuild)
		} else {
			human.txdb <- txdbmaker::makeTxDbFromGFF(file=filePath,
				format=fileFormat, 
				dataSource=fileDatSrc, organism=fileOrganism, 
				taxonomyId=taxonomyId, 
				circ_seqs=circSeqs, chrominfo=fileChrInf, 
				miRBaseBuild=miRBaseBuild, dbxrefTag=fileDbXrefTag)
		}
	}

	exons<- GenomicFeatures::exonsBy(human.txdb, by="tx", use.names=TRUE)
	namesExons=names(exons)


	time1=Sys.time()

	if(!ignore.strand){
	  strandsEx=as.character(GenomicRanges::strand(unlist(exons)))
	  exonsGR=GenomicRanges::GRanges( 
	    seqnames=as.character(GenomicRanges::seqnames(unlist(exons))), 
	    IRanges::IRanges(
	      start=as.numeric(GenomicRanges::start(unlist(exons))) , 
	      end=as.numeric(GenomicRanges::end(unlist(exons))) ),
	    strand=strandsEx)
	} else {
	  exonsGR=GenomicRanges::GRanges( 
	    seqnames=as.character(GenomicRanges::seqnames(unlist(exons))), 
	    IRanges::IRanges(
	      start=as.numeric(GenomicRanges::start(unlist(exons))) , 
	      end=as.numeric(GenomicRanges::end(unlist(exons))) ))
	}
	
	if (collapseExons){
		genMat=matrix(as.vector(unlist(sapply(exons,function(tmp)
			return(  c((as.character(GenomicRanges::seqnames(tmp)))[1], 
				as.numeric(GenomicRanges::start(tmp))[1], 
				as.numeric(GenomicRanges::width(tmp))[1], 
				utils::tail(as.numeric(GenomicRanges::start(tmp)),n=1), 
				utils::tail(as.numeric(GenomicRanges::width(tmp)),n=1), 
				as.character(GenomicRanges::strand(tmp))[1]  ))))), 
			byrow=TRUE, ncol=6)
	
		genBegs= as.numeric(as.numeric(genMat[,2]))
		genBegs[genMat[,6]=="-"]= 
			as.numeric(as.numeric(genMat[genMat[,6]=="-",4]))
		genEnds= (as.numeric(genMat[,4])+as.numeric(genMat[,5])-1)
		genEnds[genMat[,6]=="-"]= as.numeric(genMat[genMat[,6]=="-",2])+
			as.numeric(genMat[genMat[,6]=="-",3])-1
	
		genGr=GenomicRanges::GRanges( seqnames=genMat[,1], 
			IRanges::IRanges(start=genBegs , end=genEnds ), strand=genMat[,6])
	
		reduceExGr=GenomicRanges::reduce(exonsGR, ignore.strand=ignore.strand)
		intronsGr=GenomicRanges::gaps(reduceExGr)

		reduceGenGr=GenomicRanges::reduce(genGr, ignore.strand=ignore.strand)
	
		hitsEx= GenomicRanges::findOverlaps(reduceExGr, reduceGenGr, 
			type="any", ignore.strand=ignore.strand)
		hitsInt= GenomicRanges::findOverlaps(intronsGr, reduceGenGr, 
			type="any", ignore.strand=ignore.strand)

		genesExMap=tapply(S4Vectors::queryHits(hitsEx), 
			S4Vectors::subjectHits(hitsEx), unique)
		genesIntMap=tapply(S4Vectors::queryHits(hitsInt), 
			S4Vectors::subjectHits(hitsInt), unique)

		lenGenesExMap=sapply(genesExMap,length)
		multiEx=names(genesExMap[lenGenesExMap>1])
		singleEx=names(genesExMap[lenGenesExMap==1])

		allEx=names(genesExMap)
		matOutVecTmp=lapply(allEx, function(tmp){ 
			genExUnl=unlist(genesExMap[tmp])
			genIntUnl=unlist(genesIntMap[tmp])

			if(length(genIntUnl)>0){
				res=as.vector(c( 
					as.character(GenomicRanges::seqnames(reduceExGr)[
						genExUnl]),
					as.character(GenomicRanges::seqnames(intronsGr)[
						genIntUnl]),
					as.numeric(GenomicRanges::start(reduceExGr))[genExUnl],
					as.numeric(GenomicRanges::start(intronsGr))[genIntUnl],
					as.numeric(GenomicRanges::end(reduceExGr))[genExUnl],
					as.numeric(GenomicRanges::end(intronsGr))[genIntUnl],
					as.character(GenomicRanges::strand(reduceExGr))[genExUnl],
					as.character(GenomicRanges::strand(intronsGr))[genIntUnl],
					rep("exon",length(genExUnl)),
					rep("intron",length(genIntUnl)),
					seq(from=1, by=2, length.out=length(genExUnl)),
					seq(from=2, by=2, length.out=length(genIntUnl)),
					rep(tmp,length(genIntUnl)+ length(genExUnl))))
			} else {
				res= as.vector(c( 
					as.character(GenomicRanges::seqnames(reduceExGr)[
						genExUnl]),
					as.numeric(GenomicRanges::start(reduceExGr))[genExUnl],
					as.numeric(GenomicRanges::end(reduceExGr))[genExUnl],
					as.character(GenomicRanges::strand(reduceExGr))[genExUnl],
					rep("exon",length(genExUnl)),
					seq(from=1, by=2, length.out=length(genExUnl)), 
					rep(tmp,length(genExUnl))))
			}
			return( res )
		} )
	
		matOut=  data.frame(
			chr=as.character(unlist(sapply(matOutVecTmp, function(tmp) 
				return( (tmp[1:(length(tmp)/7)]) ) ) )) ,
			begin=as.numeric(unlist(sapply(matOutVecTmp, function(tmp) 
				return( (tmp[1*(length(tmp)/7)+(1:(length(tmp)/7))])[
					order(as.numeric(tmp[5*(length(tmp)/7)+
						(1:(length(tmp)/7))]),decreasing=FALSE)] ) ) )),
			end=as.numeric(unlist(sapply(matOutVecTmp, function(tmp) 
				return( (tmp[2*(length(tmp)/7)+(1:(length(tmp)/7))])[
					order(as.numeric(tmp[5*(length(tmp)/7)+
						(1:(length(tmp)/7))]),decreasing=FALSE)] ) ) )),
			strand=as.character(unlist(sapply(matOutVecTmp, function(tmp) 
				return( (tmp[3*(length(tmp)/7)+(1:(length(tmp)/7))]) ) ) )),
			int_ex=as.character(unlist(sapply(matOutVecTmp, function(tmp) 
				return( (tmp[4*(length(tmp)/7)+(1:(length(tmp)/7))])[
					order(as.numeric(tmp[5*(length(tmp)/7)+
						(1:(length(tmp)/7))]),decreasing=FALSE)] ) ))),
			int_ex_num=as.numeric(unlist(sapply(matOutVecTmp, function(tmp) 
				return( (tmp[5*(length(tmp)/7)+(1:(length(tmp)/7))])[
					order(as.numeric(tmp[5*(length(tmp)/7)+
						(1:(length(tmp)/7))]),decreasing=FALSE)] ) ))),
			collapsed_transcripts_id=as.numeric(unlist(sapply(matOutVecTmp, 
				function(tmp) 
					return( (tmp[6*(length(tmp)/7)+(1:(length(tmp)/7))]) ) ) 
						)),
			stringsAsFactors=FALSE)

		hitsGenToColl= GenomicRanges::findOverlaps(genGr,reduceGenGr, 
			type="any", ignore.strand=FALSE)
#Annotate collapsed transcripts
		trAnnoCollList=lapply(
			as.numeric(unique(matOut[,"collapsed_transcripts_id"])), 
			function(tmp) 
				namesExons[S4Vectors::queryHits(hitsGenToColl)[
					S4Vectors::subjectHits(hitsGenToColl)==tmp]])
		trAnnoColl=sapply(trAnnoCollList, function(tmp) paste(tmp, 
			collapse=','))
		names(trAnnoColl)= 
			as.character(unique(matOut[,"collapsed_transcripts_id"]))
	
		if(addCollapsedTranscripts)
			matOut$collapsed_transcripts=
				trAnnoColl[as.character(matOut[,"collapsed_transcripts_id"])]

		if(annotateGeneIds){
			trGenesTx<- GenomicFeatures::transcriptsBy(human.txdb, by="gene")
			if(length(trGenesTx)>0){
				trGenesVec=unlist(lapply(1:length(trGenesTx), function(tmp)
					paste(names(trGenesTx)[tmp], 
						trGenesTx[[tmp]]$tx_name,sep=",")))
				trGenes=unlist(strsplit(trGenesVec,split=","))[
					seq(from=1,by=2,length.out=length(trGenesVec))]
				names(trGenes)=unlist(strsplit(trGenesVec,split=","))[
					seq(from=2,by=2,length.out=length(trGenesVec))]
	
				gene_ids= unlist(sapply(trAnnoCollList, function(tmp)
					paste(unique(trGenes[tmp]), collapse=',')))
				names(gene_ids)= 
					as.character(unique(matOut[,"collapsed_transcripts_id"]))
				matOut$collapsed_gene_id=
					gene_ids[as.character(matOut[,"collapsed_transcripts_id"])]
			} else{
				warning("Gene annotations were NOT available !")
				annotateGeneIds=FALSE
			}
		}

		if(outFileTranscriptsAnnotation!=""){
			if(!annotateGeneIds){
				write.table(cbind(names(trAnnoColl),as.vector(trAnnoColl)), 
					outFileTranscriptsAnnotation, sep='\t', quote=FALSE, 
					col.names=c("id", "collapsed_transcripts"), 
					row.names=FALSE)
			} else {
				write.table(cbind(names(trAnnoColl),as.vector(trAnnoColl), 
					trGenes[as.vector(trAnnoColl)]),
					outFileTranscriptsAnnotation, sep='\t', quote=FALSE, 
					col.names=c("id", "collapsed_transcripts", "gene_id"), 
					row.names=FALSE)
			}
		}


	} else {
		introns <- GenomicFeatures::intronsByTranscript(human.txdb, 
			use.names=TRUE)
		
		if(ignore.strand){
			strMat=rep("*", 
				length(as.character(GenomicRanges::seqnames(unlist(exons))))+ 
				length(as.character(GenomicRanges::seqnames(unlist(introns)))))
		} else {
			strMat<- c(as.character(GenomicRanges::strand(unlist(exons))), 
				as.character(GenomicRanges::strand(unlist(introns))))
		}

		chrEx<- as.character(GenomicRanges::seqnames(unlist(exons)))
		chrInt<- as.character(GenomicRanges::seqnames(unlist(introns)))		
		stEx<- as.numeric(GenomicRanges::start(unlist(exons)))
		stInt<- as.numeric(GenomicRanges::start(unlist(introns)))
		endEx<- as.numeric(GenomicRanges::end(unlist(exons)))
		endInt<- as.numeric(GenomicRanges::end(unlist(introns)))
		noEx<- as.vector(unlist(lapply(1:length(exons), function(tmp) 
				return(seq(from=1, by=2, 
					length.out=length(exons[[tmp]]))))))
		noInt<- as.vector(unlist(lapply(1:length(introns), function(tmp) 
				return(seq(from=2, by=2, 
					length.out=length(introns[[tmp]]))))))

		exInt<- c(rep("exon",length(unlist(exons))), 
			rep("intron",length(unlist(introns))))
		genNames<- c(names(unlist(exons)), names(unlist(introns)))
		matTmp<- data.frame(chr=c(chrEx,chrInt), 
			begin=c(stEx,stInt),
			end=c(endEx,endInt),
			strand=strMat,
			int_ex_num=c(noEx,noInt),
			int_ex= exInt,
			transcript_id=genNames
			)
	
		matInd= unlist(tapply(1:nrow(matTmp), as.character(matTmp[,7]), 
			function(tmp)return( tmp[order(as.numeric(matTmp[tmp,5]), 
				decreasing=FALSE)] )))
		matOutTmp= data.frame(
			chr=as.character(matTmp[,1]),
			begin=as.numeric(matTmp[,2]), 
			end=as.numeric(matTmp[,3]), 
			strand=as.character(matTmp[,4]),
			int_ex_num=as.numeric(matTmp[,5]), 
			int_ex=as.character(matTmp[,6]), 
			transcript_id=as.character(matTmp[,7]), 
			stringsAsFactors=FALSE)[matInd,]

		matOut=matOutTmp
		
		if(annotateGeneIds){
			trGenesTx<- GenomicFeatures::transcriptsBy(human.txdb, by="gene")
			if(length(trGenesTx)>0){
				trGenesVec= unlist(lapply(1:length(trGenesTx), function(tmp)
					paste(names(trGenesTx)[tmp], trGenesTx[[tmp]]$tx_name,
						sep=",")))

				trGenes= unlist(strsplit(trGenesVec,split=","))[
					seq(from=1,by=2,length.out=length(trGenesVec))]
				names(trGenes)= unlist(strsplit(trGenesVec,split=","))[
					seq(from=2,by=2,length.out=length(trGenesVec))]
	
				matOut$gene_id= trGenes[as.character(matOut[,"transcript_id"])]
	
				if(outFileTranscriptsAnnotation!="")
					write.table(cbind(names(trGenes),as.vector(trGenes)), 
						outFileTranscriptsAnnotation, sep='\t', quote=FALSE, 
						col.names=c("transcript_id", "collapsed_transcripts"), 
						row.names=FALSE)
			} else {
				warning("Gene annotations were NOT available !")
				annotateGeneIds<-FALSE
			}

		}
#end else
	}

	#if(sourceBuild=="biomaRt")
	#	matOut[,"chr"]=paste("chr",matOut[,"chr"],sep="")

	if( ( (length(u12IntronsChr)>0 & length(u12IntronsBeg)>0 & 
		length(u12IntronsEnd)>0)|(!missing(u12IntronsRef)) ) ){
		matOutGr= GenomicRanges::GRanges( seqnames=matOut[,"chr"], 
			IRanges::IRanges(start=matOut[,"begin"] , end=matOut[,"end"] ))
		if(missing(u12IntronsRef)){
			u12IntGr= GenomicRanges::GRanges( seqnames=u12IntronsChr, 
				IRanges::IRanges(start=u12IntronsBeg , end=u12IntronsEnd ))
		} else {
			u12IntGr=u12IntronsRef
		}
		hitsU12Intron= GenomicRanges::findOverlaps(u12IntGr, matOutGr, 
			type="equal")
		matOut$int_type= rep(NA, nrow(matOut))
		matOut$int_type[matOut[,"int_ex"]=="intron"]= "U2"
		matOut$int_type[unique(S4Vectors::subjectHits(hitsU12Intron))]= "U12"
	}

	if(!ignore.strand & collapseExons){
			matOutTrGr=GenomicRanges::GRanges( seqnames=tapply(as.character(
					matOut[,"chr"]),
				matOut[,"collapsed_transcripts_id"],head, n=1), 
				IRanges::IRanges(start=tapply(as.numeric(matOut[,"begin"]),
					matOut[,"collapsed_transcripts_id"],min) ,
					end=tapply(as.numeric(matOut[,"end"]),
						matOut[,"collapsed_transcripts_id"],max) ), 
				strand= tapply(as.character(
				  matOut[,"strand"]),
				  matOut[,"collapsed_transcripts_id"],head, n=1))
			namesMatOutTrGr=unique(matOut[,"collapsed_transcripts_id"])
		hitsExMat= GenomicRanges::findOverlaps(exonsGR, matOutTrGr, 
			type="any", ignore.strand=ignore.strand)
		strTmp=tapply(strandsEx[S4Vectors::queryHits(hitsExMat)], 
			namesMatOutTrGr[S4Vectors::subjectHits(hitsExMat)], unique)
		strTmpVec=sapply(strTmp, function(tmp){
			if(length(tmp)==1){
				return(as.character(tmp))	
			} else {
				return("*")
			}	
		})
		names(strTmpVec)= names(strTmp)
		matStr=strTmpVec[as.character(matOut[,"collapsed_transcripts_id"])]
		matOut$strand=matStr
	}
	return(matOut)
}
