USAGE
-----
gcloud-reset:<br>
`$ bash gcloud-reset.sh`

authenticate:<br>
`$ gcloud auth login`

set your project so that gsutil knows which project to use:<br>
`gcloud config set project <YOUR_PROJECT_ID>`

gcloud-setup:<br>
`$ chmod +x gcloud-setup.sh`<br>
`$ ./gcloud-setup.sh --project <YOUR_PROJECT_ID> --name <YOUR_VM_NAME> --zone us-central1-c`

login to VM:<br>
`$ gcloud compute ssh <YOUR_USERNAME>@<YOUR_VM_NAME> --zone=us-central1-c`

save artifacts to bucket:<br>
`$ RUN_ID=$(date +%F-%H%M%S)`<br>
`$ gsutil cp *.png gs://<YOUR_BUCKET>/outputs/$RUN_ID/`