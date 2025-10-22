USAGE
-----
gcloud-reset:<br>
`$ bash gcloud-reset.sh`

authenticate:<br>
`$ gcloud auth login`

set your project so that gsutil knows which project to use:<br>
`gcloud config set project tonal-works-470115-q2`

gcloud-setup:<br>
`$ chmod +x gcloud-setup.sh`<br>
`$ PROJECT_ID=tonal-works-470115-q2 ZONE=us-central1-a INSTANCE_NAME=dl-dpd-vm ./gcloud-setup.sh`

login to VM:<br>
`$ gcloud compute ssh srikanth_pagadarai@dl-dpd-vm --zone=us-central1-a`

save artifacts to bucket:<br>
`$ RUN_ID=$(date +%F-%H%M%S)`<br>
`$ gsutil cp *.png gs://dl-dpd/outputs/$RUN_ID/`
