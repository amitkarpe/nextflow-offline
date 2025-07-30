#/bin/bash

export PIPE=rnafusion
nextflow inspect nf-core/${PIPE} -profile test,docker --outdir /tmp/out/ -concretize true -format json > ${PIPE}.list

# Download the pipeline
nextflow pull nf-core/${PIPE}



# Download all docker images
for i in $(cat ${PIPE}.list); do
  echo $i
  docker pull nfcore/${i}
done

# Run the pipeline
nextflow run nf-core/${PIPE} -profile test,docker --outdir /tmp/out/