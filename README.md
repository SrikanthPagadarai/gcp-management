USAGE
-----
gcloud-reset:
$ bash gcloud-reset.sh

gcloud-setup:
$ chmod +x gcloud-setup.sh
$ PROJECT_ID=tonal-works-470115-q2 ZONE=us-central1-a INSTANCE_NAME=dl-dpd-vm ./gcloud-setup.sh

login to VM:
$ gcloud compute ssh srikanth_pagadarai@dl-dpd-vm --zone=us-central1-a

save artifacts to bucket:
RUN_ID=$(date +%F-%H%M%S)
gsutil cp *.png gs://dl-dpd/outputs/$RUN_ID/
