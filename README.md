USAGE
-----
gcloud-reset:<br>
`$ bash gcloud-reset.sh`

gcloud-setup:<br>
`$ chmod +x gcloud-setup.sh`<br>
`$ PROJECT_ID=tonal-works-470115-q2 ZONE=us-central1-a INSTANCE_NAME=dl-dpd-vm ./gcloud-setup.sh`

login to VM:<br>
`$ gcloud compute ssh srikanth_pagadarai@dl-dpd-vm --zone=us-central1-a`

save artifacts to bucket:<br>
`$ RUN_ID=$(date +%F-%H%M%S)`<br>
`$ gsutil cp *.png gs://dl-dpd/outputs/$RUN_ID/`
